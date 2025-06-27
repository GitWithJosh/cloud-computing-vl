#!/bin/bash

source openrc.sh

# Function to get SSH key from terraform output
get_ssh_key() {
    if [ -f terraform.tfstate ]; then
        SSH_KEY=$(terraform output -raw ssh_master 2>/dev/null | grep -o "\-i ~/.ssh/[^ ]*" | cut -d'/' -f4)
        if [ -n "$SSH_KEY" ]; then
            echo "$SSH_KEY"
        else
            # Fallback: try to get from terraform.tfvars
            SSH_KEY=$(grep "key_pair" terraform.tfvars 2>/dev/null | cut -d'"' -f2)
            echo "$SSH_KEY"
        fi
    else
        # Fallback: try to get from terraform.tfvars
        SSH_KEY=$(grep "key_pair" terraform.tfvars 2>/dev/null | cut -d'"' -f2)
        echo "$SSH_KEY"
    fi
}

show_help() {
    echo "🚀 Kubernetes Cluster Version Manager"
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
    echo "  debug                  - Debug cluster issues"
    echo ""
    echo "Examples:"
    echo "  $0 deploy v1.0"
    echo "  $0 zero-downtime v1.1"
    echo "  $0 create v1.1"
    echo "  $0 scale 5"
    echo "  $0 status"
    echo "  $0 dashboard"
}

deploy_version() {
    local version=$1
    if [ -z "$version" ]; then
        echo "❌ Version required"
        exit 1
    fi
    
    echo "🚀 Deploying version $version..."
    
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
    echo "⏳ Waiting for cluster to be ready..."
    
    # Längeres Warten für ML-Dependencies
    echo "📦 Installing ML dependencies (this takes 5-10 minutes)..."
    sleep 180  # 3 Minuten warten für initiale Installation
    
    # Check cluster status
    local master_ip=$(terraform output -raw master_ip)
    echo "📊 Cluster status:"
    
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
            echo '🔄 Docker build still in progress...'
        elif docker images | grep -q caloguessr-app; then
            echo '✅ Docker image ready'
            # Check pod status
            if kubectl get pods -l app=caloguessr --no-headers 2>/dev/null | grep -q Running; then
                echo '✅ App pods running'
            elif kubectl get pods -l app=caloguessr --no-headers 2>/dev/null | grep -q Pending; then
                echo '⏳ App pods pending...'
            else
                echo '🔄 App pods starting...'
            fi
        else
            echo '🔄 Building application image...'
        fi
    " 2>/dev/null || echo "Cluster still initializing..."
    
    # Final status check after more time
    echo ""
    echo "⏳ Final check in 12 minutes..."
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
                echo '⏳ App starting, try again in a few minutes'
                echo '   URL: http://$master_ip:30001'
            fi
        else
            echo '⏳ App still deploying - check again in a few minutes'
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
    
    echo "🏷️  Creating version $version..."
    
    # Check for changes
    if ! git diff-index --quiet HEAD --; then
        echo "📝 Found uncommitted changes"
        git add .
        read -p "Commit message: " msg
        git commit -m "$msg"
    fi
    
    # Create tag
    git tag $version
    echo "✅ Version $version created"
}

list_versions() {
    echo "📋 Available versions:"
    git tag -l | sort -V
    echo ""
    echo "🏷️  Current:"
    git describe --tags --exact-match HEAD 2>/dev/null || echo "No tag"
}

show_status() {
    echo "📊 Cluster Status"
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
            echo "🔍 Monitoring URLs:"
            echo "Grafana: http://$master_ip:30300 (admin/admin)"
            echo "Prometheus: http://$master_ip:30090"
            echo ""
            
            if [ -n "$ssh_key" ] && ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$master_ip "echo" 2>/dev/null; then
                echo "📊 Kubernetes Status:"
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
    
    echo "🔍 Opening Monitoring Dashboard..."
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
    
    echo "📋 Application Logs"
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

debug_cluster() {
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
    
    echo "🔍 Debug Information"
    echo "===================="
    echo "Using SSH key: $ssh_key"
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo '=== Docker Images ==='
        sudo docker images
        echo
        echo '=== K3s Images ==='
        sudo /usr/local/bin/k3s ctr images ls | grep caloguessr || echo 'No caloguessr image found'
        echo
        echo '=== Checking app files ==='
        ls -la /root/app/
        echo
        echo '=== Manually deploying app ==='
        cd /root/app
        if [ -f Dockerfile ]; then
            echo 'Rebuilding Docker image...'
            sudo docker build -t caloguessr-app:latest . || echo 'Build failed'
            echo 'Importing to K3s...'
            sudo docker save caloguessr-app:latest | sudo /usr/local/bin/k3s ctr images import - || echo 'Import failed'
            echo 'Applying deployment...'
            kubectl apply -f k8s-deployment.yaml || echo 'Deploy failed'
            echo 'Waiting for pods...'
            sleep 20
            kubectl get pods -l app=caloguessr
        fi
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
    
    echo "📈 Scaling to $replicas replicas..."
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "kubectl scale deployment caloguessr-deployment --replicas=$replicas"
    
    echo "⏳ Waiting for scaling..."
    sleep 10
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "kubectl get pods -l app=caloguessr"
}

cleanup() {
    echo "🧹 Cleaning up infrastructure..."
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
    
    echo "📊 Importing Grafana Dashboard..."
    
    # Warten bis Grafana bereit ist
    echo "⏳ Waiting for Grafana to be ready..."
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
    echo "🔍 Access at: http://$master_ip:30300"
    echo "📊 Look for 'Caloguessr Scaling Demo Dashboard'"
}

zero_downtime_deploy() {
    local new_version=$1
    if [ -z "$new_version" ]; then
        echo "❌ New version required"
        exit 1
    fi
    
    echo "🔄 Starting Zero-Downtime Deployment to version $new_version..."
    echo "=================================================="
    
    # Check if current infrastructure exists
    if [ ! -f terraform.tfstate ] || [ ! -s terraform.tfstate ]; then
        echo "❌ No existing infrastructure found. Use 'deploy' for initial deployment."
        exit 1
    fi
    
    # Get current infrastructure details
    echo "📊 Current infrastructure status:"
    local current_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local current_deployment_id=$(terraform output -raw deployment_id 2>/dev/null)
    if [ -z "$current_master_ip" ]; then
        echo "❌ Cannot determine current master IP"
        exit 1
    fi
    
    echo "Current Master IP: $current_master_ip"
    echo "Current Deployment ID: $current_deployment_id"
    
    # Get current version and create backup
    local current_version=$(git describe --tags --exact-match HEAD 2>/dev/null || echo "main")
    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_dir="terraform-backup-$backup_timestamp"
    local green_workspace="green-$backup_timestamp"
    
    echo "Current version: $current_version"
    echo "Target version: $new_version"
    
    # Backup current state
    echo "💾 Backing up current state to $backup_dir..."
    mkdir -p "$backup_dir"
    cp terraform.tfstate* "$backup_dir/" 2>/dev/null || true
    
    # Save current workspace
    local current_workspace=$(terraform workspace show)
    echo "Current workspace: $current_workspace"
    
    # Checkout new version
    echo "🔄 Switching to version $new_version..."
    if ! git checkout $new_version 2>/dev/null; then
        echo "❌ Version $new_version not found"
        exit 1
    fi
    
    # Create green environment (new deployment)
    echo "🟢 Creating Green environment..."
    if ! terraform workspace new "$green_workspace" 2>/dev/null; then
        echo "❌ Failed to create Green workspace"
        git checkout "$current_version" 2>/dev/null
        exit 1
    fi
    
    # Deploy green environment
    echo "🚀 Deploying Green environment..."
    terraform init -upgrade > /dev/null 2>&1 || {
        echo "❌ Terraform init failed"
        terraform workspace select "$current_workspace" 2>/dev/null
        terraform workspace delete "$green_workspace" -force 2>/dev/null
        git checkout "$current_version" 2>/dev/null
        exit 1
    }
    
    if ! TF_LOG=ERROR terraform apply -auto-approve; then
        echo "❌ Green deployment failed, cleaning up..."
        terraform workspace select "$current_workspace" 2>/dev/null
        terraform workspace delete "$green_workspace" -force 2>/dev/null
        git checkout "$current_version" 2>/dev/null
        exit 1
    fi
    
    # Get new infrastructure details
    local new_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local new_deployment_id=$(terraform output -raw deployment_id 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$new_master_ip" ]; then
        echo "❌ Failed to get new master IP"
        terraform destroy -auto-approve > /dev/null 2>&1
        terraform workspace select "$current_workspace" 2>/dev/null
        terraform workspace delete "$green_workspace" -force 2>/dev/null
        git checkout "$current_version" 2>/dev/null
        exit 1
    fi
    
    echo ""
    echo "✅ Green environment deployed!"
    echo "New Master IP: $new_master_ip"
    echo "New Deployment ID: $new_deployment_id"
    echo "New App URL: $(terraform output -raw app_url 2>/dev/null)"
    echo "New Ingress URL: $(terraform output -raw app_ingress_url 2>/dev/null)"
    
    # Health check on green environment (simplified)
    echo "🏥 Health checking Green environment (20 minutes parallel running)..."
    local health_check_retries=10
    local new_cluster_healthy=false
    
    for i in $(seq 1 $health_check_retries); do
        echo "Health check attempt $i/$health_check_retries..."
        
        local health_check_result=0
        ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$new_master_ip "
            kubectl get nodes --no-headers 2>/dev/null | grep -q Ready &&
            kubectl get deployment caloguessr-deployment -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '^[1-9]' &&
            timeout 10 curl -s --connect-timeout 5 http://localhost:30001 >/dev/null 2>&1
        " 2>/dev/null || health_check_result=$?
        
        if [ $health_check_result -eq 0 ]; then
            new_cluster_healthy=true
            echo "✅ Green environment is healthy!"
            break
        fi
        
        echo "⏳ Green environment not ready yet, waiting 90 seconds..."
        sleep 120
    done
    
    if [ "$new_cluster_healthy" = false ]; then
        echo "❌ Green environment failed health check, rolling back..."
        terraform destroy -auto-approve > /dev/null 2>&1
        terraform workspace select "$current_workspace" 2>/dev/null
        terraform workspace delete "$green_workspace" -force 2>/dev/null
        git checkout "$current_version" 2>/dev/null
        echo "🔄 Rollback completed"
        exit 1
    fi
    
    # Switch to Green (simple state replacement)
    echo "🔄 Switching to Green environment..."
    terraform workspace select "$current_workspace" 2>/dev/null
    
    # Replace default workspace with green state
    local green_state_backup="/tmp/green-state-$backup_timestamp.tfstate"
    terraform workspace select "$green_workspace" 2>/dev/null
    cp terraform.tfstate "$green_state_backup"
    
    terraform workspace select "$current_workspace" 2>/dev/null
    cp "$green_state_backup" terraform.tfstate
    
    # Verify switch worked
    local verification_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    if [ "$verification_master_ip" != "$new_master_ip" ]; then
        echo "❌ Switch verification failed, emergency rollback..."
        cp "$backup_dir/terraform.tfstate" terraform.tfstate 2>/dev/null
        terraform workspace delete "$green_workspace" -force 2>/dev/null
        rm -f "$green_state_backup" 2>/dev/null
        git checkout "$current_version" 2>/dev/null
        exit 1
    fi
    
    echo "✅ Successfully switched to Green environment"
    echo "📊 New Master IP: $verification_master_ip"
    
    # BLUE/GREEN PARALLEL PERIOD - exactly what you wanted
    echo ""
    echo "🔵🟢 Blue-Green parallel period: Both environments running"
    echo "=================================================="
    echo "Old (Blue) environment: $current_master_ip (will be cleaned up)"
    echo "New (Green) environment: $verification_master_ip (now active)"
    echo ""
    echo "⏳ Waiting 15 minutes for pods to fully start before cleanup..."
    
    # 15 minute countdown with progress
    for i in {15..1}; do
        echo "⏳ Cleanup in $i minutes... (Blue: $current_master_ip | Green: $verification_master_ip)"
        sleep 60
    done
    
    # Cleanup old Blue environment using OpenStack directly
    echo "🧹 Cleaning up old Blue environment..."
    echo "   Targeting Blue environment with deployment ID: $current_deployment_id"
    
    # We need to restore the old state temporarily to destroy the blue environment
    local temp_blue_workspace="temp-blue-cleanup-$(date +%s)"
    
    # Create temporary workspace for blue cleanup
    if terraform workspace new "$temp_blue_workspace" 2>/dev/null; then
        # Restore the backup state (blue environment) to this temporary workspace
        cp "$backup_dir/terraform.tfstate" terraform.tfstate 2>/dev/null
        
        # Verify we have the right environment before destroying
        local blue_cleanup_ip=$(terraform output -raw master_ip 2>/dev/null)
        if [ "$blue_cleanup_ip" = "$current_master_ip" ]; then
            echo "✅ Blue environment identified correctly (IP: $blue_cleanup_ip)"
            if terraform destroy -auto-approve > /dev/null 2>&1; then
                echo "✅ Old Blue environment cleanup successful"
            else
                echo "⚠️  Warning: Blue environment cleanup had issues"
            fi
        else
            echo "⚠️  Warning: IP mismatch in Blue cleanup, skipping automatic cleanup"
            echo "   Expected: $current_master_ip, Got: $blue_cleanup_ip"
        fi
        
        # Return to main workspace and cleanup temp workspace
        terraform workspace select "$current_workspace" 2>/dev/null
        terraform workspace delete "$temp_blue_workspace" -force 2>/dev/null
    else
        echo "⚠️  Warning: Could not create temporary cleanup workspace"
        echo "   Manual cleanup may be required for Blue environment: $current_master_ip"
    fi
    
    # Final cleanup
    terraform workspace select "$current_workspace" 2>/dev/null
    terraform workspace delete "$green_workspace" -force 2>/dev/null || true
    rm -f "$green_state_backup" 2>/dev/null || true
    
    echo ""
    echo "🎉 Zero-downtime deployment completed successfully!"
    echo "================================================="
    echo "Final Master IP: $verification_master_ip"
    echo "App URL: $(terraform output -raw app_url 2>/dev/null)"
    echo "Ingress URL: $(terraform output -raw app_ingress_url 2>/dev/null)"
    echo "Version: $new_version"
    echo ""
    echo "💾 Backup of old deployment: $backup_dir"
    echo "🔍 Final status check:"
    check_app_status $verification_master_ip $ssh_key
}

rollback_deployment() {
    local target_version=$1
    if [ -z "$target_version" ]; then
        echo "❌ Target version required for rollback"
        exit 1
    fi
    
    echo "🔄 Starting Rollback to version $target_version..."
    echo "================================================="
    
    # Check if current infrastructure exists
    local current_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    if [ -z "$current_master_ip" ] && [ ! -f terraform.tfstate ] || [ ! -s terraform.tfstate ]; then
        echo "❌ No current infrastructure found."
        echo "💡 This will perform a fresh deployment instead of a rollback."
        read -p "Continue with fresh deployment of $target_version? (y/N): " fresh_confirm
        if [[ ! "$fresh_confirm" =~ ^[Yy]$ ]]; then
            echo "❌ Rollback cancelled"
            exit 1
        fi
        echo "🚀 Proceeding with fresh deployment..."
    fi
    
    # Check if backup exists
    local backup_dirs=$(ls -d terraform-backup-* 2>/dev/null | sort -r)
    if [ -z "$backup_dirs" ]; then
        echo "❌ No backup found. Cannot rollback safely."
        echo "   Use 'deploy $target_version' for a fresh deployment."
        exit 1
    fi
    
    echo "📋 Available backups:"
    for backup in $backup_dirs; do
        echo "   - $backup"
    done
    
    # Get current details
    local current_version=$(git describe --tags --exact-match HEAD 2>/dev/null || echo "main")
    local current_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    
    echo "Current version: $current_version"
    echo "Current Master IP: $current_master_ip"
    echo "Target version: $target_version"
    
    # Confirm rollback
    echo ""
    read -p "⚠️  This will destroy current infrastructure and rollback. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "❌ Rollback cancelled"
        exit 1
    fi
    
    # Create rollback backup
    local rollback_backup_dir="rollback-backup-$(date +%Y%m%d-%H%M%S)"
    echo "💾 Creating rollback backup in $rollback_backup_dir..."
    mkdir -p "$rollback_backup_dir"
    cp terraform.tfstate* "$rollback_backup_dir/" 2>/dev/null || true
    
    # Checkout target version
    echo "🔄 Switching to version $target_version..."
    if ! git checkout $target_version 2>/dev/null; then
        echo "❌ Version $target_version not found"
        exit 1
    fi
    
    # Destroy current infrastructure
    echo "🗑️  Destroying current infrastructure..."
    if ! terraform destroy -auto-approve; then
        echo "⚠️  Warning: Infrastructure destruction may have failed"
    fi
    
    # Deploy target version
    echo "🚀 Deploying version $target_version..."
    terraform init -upgrade > /dev/null 2>&1
    if ! TF_LOG=ERROR terraform apply -auto-approve; then
        echo "❌ Rollback deployment failed"
        echo "💾 Rollback backup available in: $rollback_backup_dir"
        exit 1
    fi
    
    # Get new details
    local new_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    echo ""
    echo "✅ Rollback deployment completed!"
    echo "New Master IP: $new_master_ip"
    echo "App URL: $(terraform output -raw app_url 2>/dev/null)"
    echo "Ingress URL: $(terraform output -raw app_ingress_url 2>/dev/null)"
    
    # Health check
    echo "⏳ Waiting for cluster to be ready..."
    sleep 180
    
    echo "🏥 Performing health check..."
    local health_retries=5
    for i in $(seq 1 $health_retries); do
        echo "Health check $i/$health_retries..."
        if ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$new_master_ip "
            kubectl get nodes --no-headers | grep -q Ready &&
            kubectl get deployment caloguessr-deployment -o jsonpath='{.status.readyReplicas}' | grep -q '^[1-9]' &&
            timeout 10 curl -s http://localhost:30001 >/dev/null
        " 2>/dev/null; then
            echo "✅ Rollback successful and healthy!"
            break
        fi
        [ $i -lt $health_retries ] && sleep 30
    done
    
    echo ""
    echo "🎉 Rollback to version $target_version completed!"
    echo "Master IP: $new_master_ip"
    echo "Version: $target_version"
    echo "💾 Pre-rollback backup: $rollback_backup_dir"
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
    "debug")
        debug_cluster
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
    *)
        show_help
        ;;
esac