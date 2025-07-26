#!/bin/bash

source openrc.sh

# Function to get SSH key from terraform output
get_ssh_key() {
    if [ -f terraform.tfstate ]; then
        # Extract SSH key from terraform output: "ssh -i ~/.ssh/keyname user@ip"
        SSH_KEY=$(terraform output -raw ssh_master 2>/dev/null | grep -o "~/.ssh/[^ ]*" | sed 's|~/.ssh/||')
        if [ -n "$SSH_KEY" ]; then
            echo "$SSH_KEY"
        fi
    else
        # Fallback: try to get from terraform.tfvars
        SSH_KEY=$(grep "key_pair" terraform.tfvars 2>/dev/null | cut -d'"' -f2)
        echo "$SSH_KEY"
    fi
}

show_help() {
    echo "  Kubernetes Cluster Version Manager"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  deploy <version>       - Deploy specific version"
    echo "  zero-downtime <version> - Zero-downtime deployment (Production!)"
    echo "  rollback <version>     - Rollback to version"
    echo "  create <version>       - Create new version tag"
    echo "  list                   - List all versions"
    echo "  status                 - Show cluster status"
    echo "  scale <replicas>       - Scale application"
    echo "  monitoring|dashboard   - Open monitoring dashboard"
    echo "  import-dashboard       - Import Grafana dashboard"
    echo "  cleanup                - Destroy infrastructure"
    echo "  logs                   - Show application logs"
    echo ""
    echo "  Big Data Commands:"
    echo "  setup-datalake         - Install MinIO + Python ML data lake"
    echo "  ml-pipeline            - Run Python ML pipeline on big data"
    echo "  cleanup-ml-jobs        - Stop and delete all ML jobs"
    echo ""
    echo "Examples:"
    echo "  $0 deploy v1.0"
    echo "  $0 zero-downtime v1.1"
    echo "  $0 setup-datalake"
    echo "  $0 setup-streaming"
    echo "  $0 start-stream"
    echo "  $0 run-batch-job food-analysis"
    echo "  $0 start-stream"
}


deploy_version() {
    local version=$1
    if [ -z "$version" ]; then
        echo "❌ Version required"
        exit 1
    fi
    
    echo "Deploying version $version..."
    
    # Checkout version
    git checkout $version 2>/dev/null || {
        echo "❌ Version $version not found"
        exit 1
    }
    
    # Deploy with suppressed warnings
    terraform init -upgrade
    TF_LOG=ERROR terraform apply -auto-approve
    
    # Get SSH key
    local ssh_key=$(get_ssh_key)
    if [ -z "$ssh_key" ]; then
        echo "❌ Could not determine SSH key name"
        exit 1
    fi
    
    # Show results
    echo ""
    echo "✅ Deployment complete!"
    echo "Master IP: $(terraform output -raw master_ip)"
    echo "App URL: $(terraform output -raw app_url)"
    echo "Ingress URL: $(terraform output -raw app_ingress_url)"
    echo "SSH: $(terraform output -raw ssh_master)"
    echo ""
    echo "Waiting for cluster to be ready..."
    
    # Längeres Warten für ML-Dependencies
    echo "Installing ML dependencies (this usually takes 10-15 minutes)..."
    sleep 180  # 3 Minuten warten für initiale Installation
    
    # Check cluster status
    local master_ip=$(terraform output -raw master_ip)
    echo "Cluster status:"
    
    # Check with proper timing
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$master_ip "
        echo '=== Nodes ==='
        kubectl get nodes
        echo
        echo '=== System Pods ==='
        kubectl get pods -n kube-system
        echo
        echo '=== App Status ==='
        kubectl get deployment caloguessr-deployment 2>/dev/null || echo 'App still deploying...'
        kubectl get pods -l app=caloguessr 2>/dev/null || echo 'App pods starting...'
        kubectl get svc caloguessr-service 2>/dev/null || echo 'Service starting...'
        kubectl get hpa caloguessr-hpa 2>/dev/null || echo 'HPA starting...'
        echo
        echo '=== Deployment Progress ==='
        # Check if Docker build is still running
        if pgrep -f 'docker build' > /dev/null; then
            echo 'Docker build still in progress...'
        elif docker images | grep -q caloguessr-app; then
            echo '✅ Docker image ready'
            # Check pod status
            if kubectl get pods -l app=caloguessr --no-headers 2>/dev/null | grep -q Running; then
                echo '✅ App pods running'
            elif kubectl get pods -l app=caloguessr --no-headers 2>/dev/null | grep -q Pending; then
                echo 'App pods pending...'
            else
                echo 'App pods starting...'
            fi
        else
            echo 'Building application image...'
        fi
    " 2>/dev/null || echo "Cluster still initializing..."
    
    # Final status check after more time
    echo ""
    echo "Final check in 12 minutes..."
    sleep 720
    check_app_status $master_ip $ssh_key
}

check_app_status() {
    local master_ip=$1
    local ssh_key=$2
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo '=== Final Cluster Status ==='
        kubectl get nodes
        echo
        echo '=== All Pods ==='
        kubectl get pods -A -o wide
        echo
        echo '=== App Status ==='
        kubectl get deployment,pods,svc,hpa -l app=caloguessr 2>/dev/null || echo 'App components not found'
        echo
        echo '=== App Connectivity Test ==='
        if kubectl get pods -l app=caloguessr --no-headers 2>/dev/null | grep -q Running; then
            echo '✅ App pods are running'
            echo 'Testing app URL...'
            if curl -s -o /dev/null -w '%{http_code}' http://localhost:30001 | grep -q '200\|302'; then
                echo '✅ App is responding at http://$master_ip:30001'
            else
                echo 'App starting, try again in a few minutes'
                echo '   URL: http://$master_ip:30001'
            fi
        else
            echo 'App still deploying - check again in a few minutes'
            kubectl describe pods -l app=caloguessr 2>/dev/null || echo 'No app pods yet'
        fi
    " 2>/dev/null
}

create_version() {
    local version=$1
    if [ -z "$version" ]; then
        echo "❌ Version required"
        exit 1
    fi
    
    echo "Creating version $version..."
    
    # Check for changes
    if ! git diff-index --quiet HEAD --; then
        echo "Found uncommitted changes"
        git add .
        read -p "Commit message: " msg
        git commit -m "$msg"
    fi
    
    # Create tag
    git tag $version
    echo "✅ Version $version created"
}

list_versions() {
    echo "Available versions:"
    git tag -l | sort -V
    echo ""
    echo "Current:"
    git describe --tags --exact-match HEAD 2>/dev/null || echo "No tag"
}

show_status() {
    echo "Cluster Status"
    echo "=================="
    
    if [ -f terraform.tfstate ]; then
        local master_ip=$(terraform output -raw master_ip 2>/dev/null)
        local ssh_key=$(get_ssh_key)
        
        if [ -n "$master_ip" ]; then
            echo "✅ Infrastructure: Deployed"
            echo "Master IP: $master_ip"
            echo "App URL (NodePort): $(terraform output -raw app_url)"
            echo "App URL (Ingress): $(terraform output -raw app_ingress_url)"
            echo "SSH Key: $ssh_key"
            echo ""
            echo "Monitoring URLs:"
            echo "Grafana: http://$master_ip:30300 (admin/admin)"
            echo "Prometheus: http://$master_ip:30090"
            echo ""
            
            if [ -n "$ssh_key" ] && ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$master_ip "echo" 2>/dev/null; then
                echo "Kubernetes Status:"
                ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
                    echo '=== Nodes ==='
                    kubectl get nodes
                    echo
                    echo '=== Pods ==='
                    kubectl get pods -A -o wide
                    echo
                    echo '=== Services ==='
                    kubectl get svc -A
                    echo
                    echo '=== HPA Status ==='
                    kubectl get hpa -A
                    echo
                    echo '=== Monitoring Stack ==='
                    kubectl get pods -n monitoring
                " 2>/dev/null
            else
                echo "❌ Cannot connect to cluster (SSH Key: $ssh_key)"
            fi
        else
            echo "❌ No infrastructure deployed"
        fi
    else
        echo "❌ No terraform state found"
    fi
}

monitoring_dashboard() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "Opening Monitoring Dashboard..."
    echo "Grafana: http://$master_ip:30300"
    echo "Prometheus: http://$master_ip:30090"
    echo ""
    echo "Default Grafana login: admin/admin"
    
    # Versuche Browser zu öffnen (auf macOS)
    if command -v open >/dev/null 2>&1; then
        open "http://$master_ip:30300"
    fi
}

show_logs() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    if [ -z "$ssh_key" ]; then
        echo "❌ Could not determine SSH key"
        exit 1
    fi
    
    echo "Application Logs"
    echo "==================="
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo '=== Recent Pod Events ==='
        kubectl get events --sort-by=.metadata.creationTimestamp | tail -10
        echo
        echo '=== Caloguessr Pod Logs ==='
        kubectl logs -l app=caloguessr --tail=50 || echo 'No logs available'
        echo
        echo '=== System Logs (Docker) ==='
        sudo journalctl -u docker --no-pager --lines=10
    " 2>/dev/null
}

scale_app() {
    local replicas=$1
    if [ -z "$replicas" ]; then
        echo "❌ Number of replicas required"
        exit 1
    fi
    
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    if [ -z "$ssh_key" ]; then
        echo "❌ Could not determine SSH key"
        exit 1
    fi
    
    echo "Scaling to $replicas replicas..."
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "kubectl scale deployment caloguessr-deployment --replicas=$replicas"
    
    echo "Waiting for scaling..."
    sleep 10
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "kubectl get pods -l app=caloguessr"
}

cleanup() {
    echo "Cleaning up infrastructure..."
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform destroy -auto-approve
        echo "✅ Cleanup complete"
    fi
}

import_dashboard() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "Importing Grafana Dashboard..."
    
    # Warten bis Grafana bereit ist
    echo "Waiting for Grafana to be ready..."
    sleep 30
    
    # Dashboard importieren
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        # Dashboard JSON zur Grafana API senden
        kubectl exec -n monitoring deployment/grafana -- /bin/bash -c '
            sleep 10
            curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
            -H \"Content-Type: application/json\" \
            -d @- << EOF
$(cat grafana-dashboard-caloguessr.json)
EOF
        '
    " 2>/dev/null
    
    echo "✅ Dashboard imported successfully!"
    echo "Access at: http://$master_ip:30300 (admin/admin)"
    echo "Look for 'Caloguessr Scaling Demo Dashboard'"
}

zero_downtime_deploy() {
    local new_version=$1
    if [ -z "$new_version" ]; then
        echo "❌ New version required"
        exit 1
    fi

    echo "Starting Zero-Downtime Deployment to version $new_version..."
    echo "=================================================="
    
    # Check if current infrastructure exists (tfstate in current directory)
    if [ ! -f terraform.tfstate ] || [ ! -s terraform.tfstate ] || [ -z "$(terraform state list 2>/dev/null)" ]; then
        echo "No existing infrastructure found. Using 'deploy' for initial deployment."
        deploy_version "$new_version"
        exit $?
    fi
    
    # Get current infrastructure details
    echo "Current infrastructure status:"
    local current_master_ip
    current_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local current_deployment_id
    current_deployment_id=$(terraform output -raw deployment_id 2>/dev/null)

    if [ -z "$current_master_ip" ]; then
        echo "❌ Cannot determine current master IP. Please check terraform.tfstate."
        exit 1
    fi
    
    echo "Current Master IP: $current_master_ip"
    echo "Current Deployment ID: $current_deployment_id"
    
    # Get current version and create backup timestamp
    local current_version
    current_version=$(git describe --tags --exact-match HEAD 2>/dev/null || echo "main")
    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d-%H%M%S)
    
    echo "Current version: $current_version"
    echo "Target version: $new_version"
    
    # Backup current terraform state files
    echo "Backing up current terraform state..."
    cp terraform.tfstate "terraform.tfstate.backup-$backup_timestamp"
    if [ -f terraform.tfstate.backup ]; then
        cp terraform.tfstate.backup "terraform.tfstate.backup.orig-$backup_timestamp"
    fi
    
    # Checkout new version
    echo "Switching to version $new_version..."
    if ! git checkout "$new_version" 2>/dev/null; then
        echo "❌ Version $new_version not found"
        exit 1
    fi
    
    # Deploy new (green) environment
    echo "Deploying new Green environment..."
    
    # Sicherstellen, dass die OpenStack-Credentials verfügbar sind
    echo "Ensuring OpenStack credentials are available..."
    source openrc.sh
    
    echo "Initializing Terraform for new version..."
    if ! terraform init -upgrade; then
        echo "❌ Terraform init failed for Green environment"
        git checkout "$current_version" >/dev/null 2>&1
        echo "Rollback to original version completed due to init failure"
        exit 1
    fi
    
    echo "Applying new deployment..."
    if ! TF_LOG=ERROR terraform apply -auto-approve; then
        echo "❌ Green deployment failed, cleaning up..."
        
        # Try to cleanup failed deployment
        terraform destroy -auto-approve >/dev/null 2>&1
        
        # Restore original state and version
        echo "Restoring original state..."
        git checkout "$current_version" >/dev/null 2>&1
        cp "terraform.tfstate.backup-$backup_timestamp" terraform.tfstate
        if [ -f "terraform.tfstate.backup.orig-$backup_timestamp" ]; then
            cp "terraform.tfstate.backup.orig-$backup_timestamp" terraform.tfstate.backup
        fi
        
        # Reinitialize terraform for original version
        terraform init -upgrade >/dev/null 2>&1
        
        echo "Rollback completed - original environment restored"
        exit 1
    fi
    
    # Get new infrastructure details
    local new_master_ip
    new_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local new_deployment_id
    new_deployment_id=$(terraform output -raw deployment_id 2>/dev/null)
    local ssh_key
    ssh_key=$(get_ssh_key)
    
    if [ -z "$new_master_ip" ]; then
        echo "❌ Failed to get new master IP for Green environment"
        
        # Cleanup and rollback
        terraform destroy -auto-approve >/dev/null 2>&1
        git checkout "$current_version" >/dev/null 2>&1
        cp "terraform.tfstate.backup-$backup_timestamp" terraform.tfstate
        if [ -f "terraform.tfstate.backup.orig-$backup_timestamp" ]; then
            cp "terraform.tfstate.backup.orig-$backup_timestamp" terraform.tfstate.backup
        fi
        terraform init -upgrade >/dev/null 2>&1
        
        echo "Rollback completed - original environment restored"
        exit 1
    fi
    
    echo ""
    echo "✅ Green environment deployed!"
    echo "New Master IP: $new_master_ip"
    echo "New Deployment ID: $new_deployment_id"
    
    # Health check on green environment (max 20 minutes)
    echo "Health checking Green environment (max 20 minutes)..."
    local health_check_retries=20  # 20 attempts * 60 seconds = 20 minutes
    local new_cluster_healthy=false
    
    for i in $(seq 1 $health_check_retries); do
        echo "Health check attempt $i/$health_check_retries ($i minutes)..."
        
        local health_check_result=1 # Default to failure
        ssh -i ~/.ssh/"$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "ubuntu@$new_master_ip" "
            kubectl get nodes --no-headers 2>/dev/null | grep -q Ready &&
            kubectl get deployment caloguessr-deployment -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '^[1-9]' &&
            timeout 10 curl -s --connect-timeout 5 http://localhost:30001 >/dev/null 2>&1
        " 2>/dev/null && health_check_result=$?
        
        if [ $health_check_result -eq 0 ]; then
            new_cluster_healthy=true
            echo "✅ Green environment is healthy after $i minutes!"
            break
        fi
        
        echo "Green environment not ready yet, waiting 60 seconds..."
        sleep 60
    done
    
    if [ "$new_cluster_healthy" = false ]; then
        echo "❌ Green environment failed health check after 20 minutes, rolling back..."
        
        # Sicherstellen, dass die OpenStack-Credentials verfügbar sind
        echo "Ensuring OpenStack credentials are available for cleanup..."
        source openrc.sh
        
        echo "Destroying failed Green environment..."
        terraform destroy -auto-approve
        
        # Switch back to original version and restore state
        echo "Switching back to the original version..."
        git checkout "$current_version" >/dev/null 2>&1
        
        echo "Restoring original terraform state..."
        cp "terraform.tfstate.backup-$backup_timestamp" terraform.tfstate
        if [ -f "terraform.tfstate.backup.orig-$backup_timestamp" ]; then
            cp "terraform.tfstate.backup.orig-$backup_timestamp" terraform.tfstate.backup
        fi
        
        # Reinitialize terraform for original version
        terraform init -upgrade >/dev/null 2>&1
        
        echo "Verifying restored environment connectivity..."
        local restored_master_ip
        restored_master_ip=$(terraform output -raw master_ip 2>/dev/null)
        if [ -n "$restored_master_ip" ]; then
            echo "✅ Original environment successfully restored and operational"
            echo "Restored Master IP: $restored_master_ip"
        else
            echo "⚠️ Original environment state restored but verification failed"
            echo "Manual intervention may be required"
        fi
        
        echo "Rollback completed"
        exit 1
    fi
    
    # Green environment is healthy! Now cleanup the old blue environment
    echo "✅ Green environment is healthy! Cleaning up old Blue environment..."
    
    # Switch back to original version to cleanup old infrastructure
    echo "Temporarily switching to original version to cleanup old infrastructure..."
    git checkout "$current_version" >/dev/null 2>&1
    
    # Restore old state temporarily for cleanup
    cp "terraform.tfstate.backup-$backup_timestamp" terraform.tfstate
    if [ -f "terraform.tfstate.backup.orig-$backup_timestamp" ]; then
        cp "terraform.tfstate.backup.orig-$backup_timestamp" terraform.tfstate.backup
    fi
    
    # Reinitialize and cleanup old infrastructure
    terraform init -upgrade >/dev/null 2>&1
    
    echo "Destroying old Blue environment resources..."
    if terraform destroy -auto-approve; then
        echo "✅ Old Blue environment cleanup successful"
    else
        echo "Warning: Old Blue environment cleanup had issues. Manual cleanup may be required."
    fi
    
    # Switch back to new version
    echo "Switching back to new version..."
    git checkout "$new_version" >/dev/null 2>&1
    
    # The new terraform.tfstate should already be there from the successful deployment
    # Reinitialize terraform for the new version
    terraform init -upgrade >/dev/null 2>&1
    
    # Cleanup backup files
    echo "Cleaning up backup files..."
    rm -f "terraform.tfstate.backup-$backup_timestamp" "terraform.tfstate.backup.orig-$backup_timestamp"
    
    echo ""
    echo "Zero-downtime deployment completed successfully!"
    echo "================================================="
    echo "Final Master IP: $new_master_ip"
    echo "App URL: $(terraform output -raw app_url 2>/dev/null)"
    echo "Ingress URL: $(terraform output -raw app_ingress_url 2>/dev/null)"
    echo "Version: $new_version"
    echo ""
    echo "Final status check:"
    check_app_status "$new_master_ip" "$ssh_key"
}

rollback_deployment() {
    local target_version=$1
    if [ -z "$target_version" ]; then
        echo "❌ Target version required for rollback"
        exit 1
    fi
    
    echo "Starting Rollback to version $target_version..."
    echo "================================================="

    # Überprüfen, ob eine Infrastruktur zum Zurücksetzen vorhanden ist
    local current_master_ip
    current_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    if [ -z "$current_master_ip" ]; then
        echo "ℹ️ No current infrastructure found. Performing a fresh deployment of $target_version."
        deploy_version "$target_version"
        exit $?
    fi
    
    # Get current details
    local current_version
    current_version=$(git describe --tags --exact-match HEAD 2>/dev/null || echo "main")
    
    echo "Current version: $current_version"
    echo "Current Master IP: $current_master_ip"
    echo "Target version for rollback: $target_version"
    
    # Confirm rollback
    echo ""
    read -p "This will DESTROY the current infrastructure and redeploy version $target_version. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "❌ Rollback cancelled"
        exit 1
    fi
    
    # Checkout target version first
    echo "Switching to version $target_version..."
    if ! git checkout "$target_version" 2>/dev/null; then
        echo "❌ Version $target_version not found"
        # Zurück zum ursprünglichen Git-Status, falls der Checkout fehlschlägt
        git checkout "$current_version" >/dev/null 2>&1
        exit 1
    fi

    # Destroy current infrastructure
    echo "Destroying current infrastructure..."
    if ! terraform destroy -auto-approve; then
        echo "Warning: Infrastructure destruction may have failed. Continuing with deployment anyway."
    fi
    
    # Deploy target version
    echo "Deploying version $target_version..."
    deploy_version "$target_version"

    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "❌ Rollback deployment failed."
        # Versuch, zum vorherigen Git-Status zurückzukehren
        git checkout "$current_version" >/dev/null 2>&1
        exit $exit_code
    fi
    
    echo ""
    echo "Rollback to version $target_version completed!"
}

# ========================================
# BIG DATA FUNCTIONS (Aufgabe 4)
# ========================================

setup_datalake() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "Setting up Data Lake (MinIO)"
    echo "======================================="
    
    # --- Lokale Pfade zu den YAML-Dateien ---
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local spark_datalake_yaml="$script_dir/big-data/datalake.yaml"
    if [ ! -f "$spark_datalake_yaml" ]; then
        echo "❌ datalake.yaml nicht gefunden: $spark_datalake_yaml"
        exit 1
    fi
    
    # Kopiere YAML-Dateien auf Remote-Server
    scp -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no "$spark_datalake_yaml" ubuntu@$master_ip:/tmp/datalake.yaml
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo 'Installing MinIO Data Lake...'
        kubectl create namespace big-data || true
        
        # Apply YAML definitions from file
        kubectl apply -f /tmp/datalake.yaml
        
        echo 'Waiting for MinIO to be ready...'
        kubectl wait --for=condition=Ready pod -l app=minio -n big-data --timeout=120s || echo 'MinIO taking longer than expected...'
        
        echo 'MinIO Status:'
        kubectl get pods -n big-data -l app=minio
        
        echo 'Waiting for MinIO setup job to complete...'
        kubectl wait --for=condition=complete job/minio-setup-job -n big-data --timeout=180s || echo 'Setup job taking longer than expected...'
        
        echo 'Setup job logs:'
        kubectl logs job/minio-setup-job -n big-data || echo 'Could not retrieve logs'
        
        echo '✅ Data Lake setup complete!'
        echo 'MinIO Console: http://$master_ip:30901 (minioadmin/minioadmin123)'
        echo 'Created buckets: raw-data & processed-data'
        echo 'Sample files uploaded for demo purposes'
        
        echo 'Cleaning up temp files...'
        rm -f /tmp/datalake.yaml
    "
}

ml_pipeline() {
    echo "Running ML Pipeline on Big Data"
    echo "=================================="
    
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    # --- Lokale Pfade zu den Python-Dateien ---
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local ml_pipeline_py="$script_dir/big-data/ml-pipeline.py"
    if [ ! -f "$ml_pipeline_py" ]; then
        echo "❌ ml-pipeline.py nicht gefunden: $ml_pipeline_py"
        exit 1
    fi
    
    echo "Using ML Pipeline from file: $ml_pipeline_py"
    
    # Kopiere Python-Datei auf Remote-Server
    scp -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no "$ml_pipeline_py" ubuntu@$master_ip:/tmp/ml-pipeline.py
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo 'Creating ML Pipeline ConfigMap...'
        
        # Create/Update ConfigMap with the ml-pipeline.py file
        kubectl delete configmap ml-pipeline-updated-code -n big-data 2>/dev/null || true
        kubectl create configmap ml-pipeline-updated-code \
            --from-file=ml-pipeline.py=/tmp/ml-pipeline.py \
            --namespace=big-data
        
        echo 'Starting ML Pipeline Job with updated code...'
        
        # Generiere einen einheitlichen Timestamp im Format YYYYMMDD-HHMMSS für Job und Dateien
        JOB_TIMESTAMP=\$(date +%Y%m%d-%H%M%S)
        echo 'Using unified timestamp for job and files: '\$JOB_TIMESTAMP
        
        # Create ML Pipeline Job using the ConfigMap
        kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ml-food-pipeline-\${JOB_TIMESTAMP}
  namespace: big-data
spec:
  template:
    spec:
      containers:
      - name: ml-pipeline
        image: python:3.9-slim
        command: ['/bin/bash']
        args: ['-c', 'apt-get update -qq && apt-get install -y -qq wget curl && pip install --no-cache-dir --quiet pandas numpy scikit-learn requests && wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc && chmod +x /usr/local/bin/mc && python /app/ml-pipeline.py']
        env:
        - name: ML_JOB_TIMESTAMP
          value: "\${JOB_TIMESTAMP}"
        volumeMounts:
        - name: ml-code
          mountPath: /app
        resources:
          requests:
            memory: '512Mi'
            cpu: '250m'
          limits:
            memory: '1Gi'
            cpu: '1'
      volumes:
      - name: ml-code
        configMap:
          name: ml-pipeline-updated-code
      restartPolicy: Never
  backoffLimit: 3
EOF

        echo '🧹 Cleaning up temp files...'
        rm -f /tmp/ml-pipeline.py
        
        echo 'ML Pipeline Job submitted!'
        echo 'Check status with SSH:'
        echo '   ssh -i ~/.ssh/$ssh_key ubuntu@$master_ip kubectl get jobs -n big-data'
        echo 'View logs with SSH:'
        echo '   ssh -i ~/.ssh/$ssh_key ubuntu@$master_ip kubectl logs job/ml-food-pipeline-'\${JOB_TIMESTAMP}' -n big-data'
    "
}

# ========================================
# 🧹 ML JOB MANAGEMENT FUNCTIONS 
# ========================================

cleanup_ml_jobs() {
    echo "🧹 Cleaning up ML jobs..."
    
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo 'Deleting all jobs in big-data namespace...'
        kubectl delete jobs --all -n big-data
        
        echo 'Remaining jobs:'
        kubectl get jobs -n big-data
        
        echo '✅ ML jobs cleanup completed!'
    "
}


# Command handling
case $1 in
    "deploy")
        deploy_version $2
        ;;
    "zero-downtime")
        zero_downtime_deploy $2
        ;;
    "create")
        create_version $2
        ;;
    "rollback")
        rollback_deployment $2
        ;;
    "list")
        list_versions
        ;;
    "status")
        show_status
        ;;
    "scale")
        scale_app $2
        ;;
    "logs")
        show_logs
        ;;
    "monitoring"|"dashboard")
        monitoring_dashboard
        ;;
    "import-dashboard")
        import_dashboard
        ;;
    "cleanup")
        cleanup
        ;;
    "setup-datalake")
        setup_datalake
        ;;
    "ml-pipeline")
        ml_pipeline
        ;;
    "cleanup-ml-jobs")
        cleanup_ml_jobs
        ;;
    *)
        show_help
        ;;
esac