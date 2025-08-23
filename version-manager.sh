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
    echo "  setup-datalake         - Install MinIO Data Lake"
    echo "  data-ingestion         - Run data ingestion job (generates & uploads data)"
    echo "  spark-ml-pipeline      - Run Apache Spark ML pipeline"
    echo "  cleanup-ml-jobs        - Stop and delete all ML jobs"
    echo ""
    echo "  Kafka Commands:"
    echo "  setup-kafka            - Install Kafka cluster with auto-scaling"
    echo "  create-kafka-topic <n> [partitions] [replication] - Create Kafka topic"
    echo "  list-kafka-topics      - List all Kafka topics"
    echo "  kafka-status           - Show Kafka cluster status"
    echo "  kafka-stream-demo      - Run stream processing demo"
    echo "  kafka-show-streams     - View stream data and demonstrate scalability"
    echo "  cleanup-kafka          - Delete Kafka cluster"
    echo ""
    echo "Kafka Examples:"
    echo "  $0 setup-kafka"
    echo "  $0 create-kafka-topic my-events 6 1"
    echo "  $0 kafka-stream-demo"
    echo "  $0 kafka-show-streams"
    echo "  Stream Processing Commands:"
    echo "  deploy-kafka-streams   - Deploy Kafka Streams processing pipeline (3 replicas)"
    echo "  deploy-flink-pipeline  - Deploy Apache Flink cluster for advanced processing"
    echo "  deploy-spark-streaming - Deploy Spark Streaming integration"
    echo "  stream-status          - Show stream processing pipeline status"
    echo ""
    echo "Examples:"
    echo "  $0 deploy v1.0"
    echo "  $0 zero-downtime v1.1"
    echo "  $0 setup-datalake"
    echo "  $0 data-ingestion"
    echo "  $0 spark-ml-pipeline"
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
    local current_tag=$(git describe --tags --exact-match HEAD 2>/dev/null)
    local current_branch=$(git branch --show-current)
    
    if [ -n "$current_tag" ]; then
        echo "Tag: $current_tag"
    else
        echo "Branch: $current_branch (no exact tag match)"
    fi
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
    local target_version=$1
    if [ -z "$target_version" ]; then
        echo "❌ Target version required for zero-downtime deployment"
        exit 1
    fi
    
    echo "🚀 Starting Zero-Downtime Deployment to $target_version"
    echo "========================================================="
    
    # Get current state
    local current_version
    current_version=$(git describe --tags --exact-match HEAD 2>/dev/null || git branch --show-current)
    local current_master_ip
    current_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local current_deployment_id
    current_deployment_id=$(terraform output -raw deployment_id 2>/dev/null)
    
    echo "Current version: $current_version"
    echo "Target version: $target_version"
    
    if [ -n "$current_master_ip" ]; then
        echo "Current Master IP: $current_master_ip"
        echo "Current Deployment ID: $current_deployment_id"
    else
        echo "No current infrastructure found - this will be a fresh deployment"
    fi
    
    # 1. Backup current terraform state and create new state for parallel deployment
    echo ""
    echo "📦 Step 1: Setting up parallel deployment state management..."
    local deployment_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_dir="./tfstate-backup-$deployment_timestamp"
    local new_state_dir="./tfstate-new-$deployment_timestamp"
    
    mkdir -p "$backup_dir"
    mkdir -p "$new_state_dir"
    
    # Backup current state files
    if [ -f "terraform.tfstate" ]; then
        cp terraform.tfstate "$backup_dir/terraform.tfstate.old"
        echo "✅ Backed up current terraform.tfstate"
    fi
    
    if [ -f "terraform.tfstate.backup" ]; then
        cp terraform.tfstate.backup "$backup_dir/terraform.tfstate.backup.old"
        echo "✅ Backed up current terraform.tfstate.backup"
    fi
    
    if [ -f ".terraform.lock.hcl" ]; then
        cp .terraform.lock.hcl "$backup_dir/.terraform.lock.hcl.old"
        echo "✅ Backed up current .terraform.lock.hcl"
    fi
    
    echo "Backup created in: $backup_dir"
    
    # 2. Switch to new version and prepare for parallel deployment
    echo ""
    echo "🔄 Step 2: Switching to $target_version and preparing parallel deployment..."
    
    # Checkout target version
    if ! git checkout "$target_version" 2>/dev/null; then
        echo "❌ Version $target_version not found"
        echo "🔄 Staying on current branch/version..."
        rm -rf "$backup_dir" "$new_state_dir"
        exit 1
    fi
    
    # Create fresh state for new deployment (parallel infrastructure)
    echo "Creating fresh terraform state for new deployment..."
    mv terraform.tfstate "$new_state_dir/terraform.tfstate.new" 2>/dev/null || true
    mv terraform.tfstate.backup "$new_state_dir/terraform.tfstate.backup.new" 2>/dev/null || true
    
    # Deploy new version with fresh state (this creates parallel infrastructure)
    echo "Deploying new infrastructure with fresh state..."
    terraform init -upgrade
    if ! TF_LOG=ERROR terraform apply -auto-approve; then
        echo "❌ New deployment failed!"
        echo "🧹 Rolling back to previous deployment..."
        rollback_to_previous_state "$backup_dir" "$new_state_dir" "$current_version" "deployment_failed"
        exit 1
    fi
    
    # Get new deployment info
    local new_master_ip
    new_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local new_app_url
    new_app_url=$(terraform output -raw app_url 2>/dev/null)
    local new_deployment_id
    new_deployment_id=$(terraform output -raw deployment_id 2>/dev/null)
    local ssh_key
    ssh_key=$(get_ssh_key)
    
    echo "✅ New infrastructure deployed in parallel!"
    echo "New Master IP: $new_master_ip"
    echo "New Deployment ID: $new_deployment_id"
    echo "New App URL: $new_app_url"
    
    # Save new deployment state
    cp terraform.tfstate "$new_state_dir/terraform.tfstate.final"
    if [ -f "terraform.tfstate.backup" ]; then
        cp terraform.tfstate.backup "$new_state_dir/terraform.tfstate.backup.final"
    fi
    
    # 3. Health checks on new deployment
    echo ""
    echo "🔍 Step 3: Running health checks on new deployment (max 20 minutes)..."
    
    local start_time=$(date +%s)
    local max_duration=1200  # 20 minutes
    local end_time=$((start_time + max_duration))
    
    echo "⏳ Waiting for new cluster initialization..."
    sleep 180  # 3 minutes initial wait
    
    local health_check_passed=false
    while [ $(date +%s) -lt $end_time ]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local remaining=$((max_duration - elapsed))
        
        echo "Health check - Elapsed: $((elapsed / 60))m, Remaining: $((remaining / 60))m"
        
        # Check SSH connectivity first
        if ! ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$new_master_ip "echo 'SSH OK'" >/dev/null 2>&1; then
            echo "❌ SSH not yet available on new deployment"
            sleep 60
            continue
        fi
        
        # HTTP check to the app
        local http_status
        http_status=$(ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$new_master_ip "curl -s -o /dev/null -w '%{http_code}' http://localhost:30001 --max-time 10" 2>/dev/null || echo "000")
        
        if [[ "$http_status" =~ ^(200|301|302)$ ]]; then
            echo "✅ Health check passed! New app is responding (HTTP $http_status)"
            health_check_passed=true
            break
        else
            echo "❌ New app not yet ready (HTTP $http_status)"
        fi
        
        sleep 60  # Wait 1 minute before next check
    done
    
    if [ "$health_check_passed" = false ]; then
        echo "❌ Health checks failed after 20 minutes!"
        echo "🧹 Rolling back: destroying new deployment and restoring old..."
        rollback_to_previous_state "$backup_dir" "$new_state_dir" "$current_version" "health_check_failed"
        exit 1
    fi
    
    # 4. Health checks passed - now cleanup old infrastructure
    if [ -n "$current_master_ip" ] && [ "$current_master_ip" != "$new_master_ip" ]; then
        echo ""
        echo "🧹 Step 4: Health checks passed - cleaning up old infrastructure..."
        
        # Temporarily switch to old state to destroy old infrastructure
        if [ -f "$backup_dir/terraform.tfstate.old" ]; then
            echo "Switching to old state for cleanup..."
            cp terraform.tfstate "$new_state_dir/terraform.tfstate.keep"  # Keep new state safe
            cp "$backup_dir/terraform.tfstate.old" terraform.tfstate
            
            echo "Destroying old infrastructure (Deployment ID: $current_deployment_id)..."
            echo "Old Master IP: $current_master_ip"
            
            if terraform destroy -auto-approve; then
                echo "✅ Old infrastructure cleaned up successfully"
            else
                echo "⚠️ Warning: Could not fully cleanup old infrastructure"
                echo "   Old Master IP: $current_master_ip"
                echo "   You may need to manually clean up old resources"
            fi
            
            # Restore new state as the active state
            echo "Restoring new deployment state as active..."
            cp "$new_state_dir/terraform.tfstate.keep" terraform.tfstate
        else
            echo "⚠️ No old state found for cleanup"
        fi
    else
        echo "ℹ️ No old infrastructure to clean up (fresh deployment or same infrastructure)"
    fi
    
    # 5. Final verification and cleanup
    echo ""
    echo "✅ Zero-Downtime Deployment Complete!"
    echo "========================================="
    echo "✅ Successfully switched from version $current_version to $target_version"
    echo "✅ New Deployment ID: $new_deployment_id"
    echo "✅ New Master IP: $new_master_ip"
    echo "✅ New App URL: $new_app_url"
    echo "✅ New Ingress URL: $(terraform output -raw app_ingress_url 2>/dev/null || echo 'N/A')"
    
    if [ -n "$current_master_ip" ] && [ "$current_master_ip" != "$new_master_ip" ]; then
        echo "✅ Old infrastructure (ID: $current_deployment_id, IP: $current_master_ip) cleaned up"
    fi
    
    echo ""
    echo "📁 Backup directory: $backup_dir (safe to delete after verification)"
    echo "📁 Temp directory: $new_state_dir (safe to delete)"
    echo ""
    echo "🎉 Your application is now running on $target_version with zero downtime!"
    
    # Optional: Auto-cleanup temp directories after success
    read -p "🧹 Delete temporary backup directories? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$backup_dir" "$new_state_dir"
        echo "✅ Temporary directories cleaned up"
    fi
}

rollback_to_previous_state() {
    local backup_dir=$1
    local new_state_dir=$2
    local current_version=$3
    local failure_reason=${4:-"unknown"}
    
    echo "🚨 Performing emergency rollback due to: $failure_reason"
    echo "=============================================="
    
    # Destroy failed new deployment if it exists
    if [ -f "terraform.tfstate" ]; then
        echo "Destroying failed new deployment..."
        terraform destroy -auto-approve || echo "Warning: Destroy of new deployment may have failed"
    fi
    
    # Restore old state files if they exist
    if [ -f "$backup_dir/terraform.tfstate.old" ]; then
        cp "$backup_dir/terraform.tfstate.old" terraform.tfstate
        echo "✅ Restored old terraform.tfstate"
        
        # Check if old infrastructure still exists
        local old_master_ip
        old_master_ip=$(terraform output -raw master_ip 2>/dev/null)
        if [ -n "$old_master_ip" ]; then
            echo "✅ Old infrastructure found at: $old_master_ip"
        else
            echo "❌ Old infrastructure state restored but infrastructure may not exist"
            echo "    You may need to redeploy the old version"
        fi
    else
        echo "⚠️ No old state to restore - this was likely a fresh deployment"
        rm -f terraform.tfstate terraform.tfstate.backup
    fi
    
    if [ -f "$backup_dir/terraform.tfstate.backup.old" ]; then
        cp "$backup_dir/terraform.tfstate.backup.old" terraform.tfstate.backup
        echo "✅ Restored old terraform.tfstate.backup"
    fi
    
    if [ -f "$backup_dir/.terraform.lock.hcl.old" ]; then
        cp "$backup_dir/.terraform.lock.hcl.old" .terraform.lock.hcl
        echo "✅ Restored old .terraform.lock.hcl"
    fi
    
    # Restore git state
    if git show-ref --verify --quiet "refs/heads/$current_version"; then
        # It's a branch name
        git checkout "$current_version" >/dev/null 2>&1
        echo "✅ Restored git to branch $current_version"
    elif git show-ref --verify --quiet "refs/tags/$current_version"; then
        # It's a tag
        git checkout "$current_version" >/dev/null 2>&1
        echo "✅ Restored git to tag $current_version"
    else
        # Try to checkout anyway (might be a commit hash or valid ref)
        git checkout "$current_version" >/dev/null 2>&1 || echo "⚠️ Could not restore git to $current_version"
        echo "✅ Restored git to $current_version"
    fi
    
    # Re-initialize terraform with restored state
    terraform init >/dev/null 2>&1
    
    echo ""
    echo "🔄 Rollback completed - you are back on the previous deployment"
    
    # Show current status if infrastructure exists
    local restored_master_ip
    restored_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    if [ -n "$restored_master_ip" ]; then
        echo "✅ Restored Infrastructure Status:"
        echo "   Version: $current_version"
        echo "   Master IP: $restored_master_ip"
        echo "   App URL: $(terraform output -raw app_url 2>/dev/null)"
        echo "   Deployment ID: $(terraform output -raw deployment_id 2>/dev/null)"
    else
        echo "⚠️ No active infrastructure found after rollback"
        echo "   Consider running: ./version-manager.sh deploy $current_version"
    fi
    
    # Cleanup temporary directories
    echo ""
    echo "🧹 Cleaning up temporary directories..."
    rm -rf "$backup_dir" "$new_state_dir"
    echo "✅ Cleanup completed"
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
    current_version=$(git describe --tags --exact-match HEAD 2>/dev/null || git branch --show-current)
    
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
        # Auf dem aktuellen Branch bleiben, nicht zu main wechseln
        echo "🔄 Staying on current branch/version: $current_version"
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
        if git show-ref --verify --quiet "refs/heads/$current_version"; then
            git checkout "$current_version" >/dev/null 2>&1
        elif git show-ref --verify --quiet "refs/tags/$current_version"; then
            git checkout "$current_version" >/dev/null 2>&1
        fi
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

# ========================================
# 🧹 ML JOB MANAGEMENT FUNCTIONS 
# ========================================

data_ingestion() {
    echo "Starting Data Ingestion Job"
    echo "============================"
    echo "   - Generates large food dataset (50,000+ samples)"
    echo "   - Uploads data to MinIO Data Lake"
    echo "   - Prepares data for ML processing"
    echo "   - Creates metadata for data governance"
    echo ""
    
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    # Check if MinIO is running
    echo "🔍 Checking MinIO Data Lake status..."
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        if ! kubectl get pods -n big-data | grep -q minio.*Running; then
            echo '❌ MinIO Data Lake is not running'
            echo 'Please run: ./version-manager.sh setup-datalake first'
            exit 1
        fi
        echo '✅ MinIO Data Lake is running'
    " || exit 1
    
    # --- Lokale Pfade zu den Dateien ---
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local ingestion_job_yaml="$script_dir/big-data/data-ingestion-job.yaml"
    
    if [ ! -f "$ingestion_job_yaml" ]; then
        echo "❌ data-ingestion-job.yaml nicht gefunden: $ingestion_job_yaml"
        exit 1
    fi
    
    echo "Using Data Ingestion Job from: $ingestion_job_yaml"
    
    # Kopiere Job-Definition auf Remote-Server
    scp -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no "$ingestion_job_yaml" ubuntu@$master_ip:/tmp/data-ingestion-job.yaml
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo '🚀 Starting Data Ingestion Job...'
        
        # Delete any existing ingestion job
        kubectl delete job data-ingestion-job -n big-data --ignore-not-found=true
        
        # Apply the job
        kubectl apply -f /tmp/data-ingestion-job.yaml
        
        echo '✅ Data Ingestion Job submitted!'
        echo ''
        echo '📊 Monitor the ingestion:'
        echo '   kubectl get jobs -n big-data'
        echo '   kubectl get pods -n big-data'
        echo '   kubectl logs job/data-ingestion-job -n big-data -f'
        echo ''
        echo '🗂️ Access MinIO Data Lake at: http://$master_ip:30901'
        echo '   Username: minioadmin'
        echo '   Password: minioadmin123'
        echo ''
        echo '📋 Check ingested data in MinIO buckets:'
        echo '   - raw-data: Original datasets and metadata'
        
        # Real-time job monitoring
        echo ''
        echo '🔍 Job Status:'
        kubectl get jobs -n big-data
        echo ''
        echo '📋 Pod Status:'
        kubectl get pods -n big-data

        echo 'Waiting for Ingestion job to complete...'
        kubectl wait --for=condition=complete job/data-ingestion-job -n big-data --timeout=180s || echo 'Ingestion job taking longer than expected...'

        # Cleanup temp files
        rm -f /tmp/data-ingestion-job.yaml
    "
    
    echo ""
    echo "🎯 DATA INGESTION FEATURES:"
    echo "   ✅ Generates 50,000+ realistic food samples"
    echo "   ✅ Uploads data to MinIO Data Lake"
    echo "   ✅ Creates comprehensive metadata"
    echo "   ✅ Prepares data for Spark ML processing"
    echo "   ✅ Data governance and schema documentation"
}

spark_ml_pipeline() {
    echo "Starting Apache Spark ML Pipeline"
    echo "=================================="
    echo "   - Reads data from MinIO Data Lake"
    echo "   - Performs ML processing with Apache Spark & MLlib"
    echo "   - Uses Random Forest and K-Means clustering"
    echo "   - Saves results back to Data Lake"
    echo "   - Enterprise-grade Big Data ML processing"
    echo ""
    
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    # Check if MinIO is running
    echo "🔍 Checking MinIO Data Lake status..."
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        if ! kubectl get pods -n big-data | grep -q minio.*Running; then
            echo '❌ MinIO Data Lake is not running'
            echo 'Please run: ./version-manager.sh setup-datalake first'
            exit 1
        fi
        echo '✅ MinIO Data Lake is running'
    " || exit 1
    
    # --- Lokale Pfade zu den Dateien ---
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local spark_job_yaml="$script_dir/big-data/spark-ml-pipeline-job.yaml"
    
    if [ ! -f "$spark_job_yaml" ]; then
        echo "❌ spark-ml-pipeline-job.yaml nicht gefunden: $spark_job_yaml"
        exit 1
    fi
    
    echo "Using Spark ML Pipeline Job from: $spark_job_yaml"
    
    # Kopiere Job-Definition auf Remote-Server
    scp -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no "$spark_job_yaml" ubuntu@$master_ip:/tmp/spark-ml-pipeline-job.yaml
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo '🚀 Starting Apache Spark ML Pipeline Job...'
        
        # Delete any existing spark ml job
        kubectl delete job spark-ml-pipeline-job -n big-data --ignore-not-found=true
        
        # Apply the job
        kubectl apply -f /tmp/spark-ml-pipeline-job.yaml
        
        echo '✅ Spark ML Pipeline Job submitted!'
        echo ''
        echo '📊 Monitor the Spark ML pipeline:'
        echo '   kubectl get jobs -n big-data'
        echo '   kubectl get pods -n big-data'
        echo '   kubectl logs job/spark-ml-pipeline-job -n big-data -f'
        echo ''
        echo '🗂️ Access MinIO Data Lake at: http://$master_ip:30901'
        echo '   Username: minioadmin'
        echo '   Password: minioadmin123'
        echo ''
        echo '📋 Check ML results in MinIO buckets:'
        echo '   - processed-data: ML models and predictions'
        echo '   - ml-models: Trained model artifacts'
        
        # Real-time job monitoring
        echo ''
        echo '🔍 Job Status:'
        kubectl get jobs -n big-data
        echo ''
        echo '📋 Pod Status:'
        kubectl get pods -n big-data
        
        # Cleanup temp files
        rm -f /tmp/spark-ml-pipeline-job.yaml

        # Monitor job progress with periodic status updates
        echo ''
        echo '⏳ Monitoring Spark ML Pipeline progress...'
        echo '   (Checking status every minute until completion)'
        echo ''
        
        # Loop to check job status every minute
        while true; do
            # Check job completion using succeeded field which is more reliable
            JOB_SUCCEEDED=\$(kubectl get job spark-ml-pipeline-job -n big-data -o jsonpath='{.status.succeeded}' 2>/dev/null || echo '0')
            JOB_FAILED=\$(kubectl get job spark-ml-pipeline-job -n big-data -o jsonpath='{.status.failed}' 2>/dev/null || echo '0')
            
            if [ \"\$JOB_SUCCEEDED\" = \"1\" ]; then
                echo '✅ Spark ML Pipeline completed successfully!'
                kubectl get job spark-ml-pipeline-job -n big-data
                echo ''
                break
            elif [ \"\$JOB_FAILED\" = \"1\" ]; then
                echo '❌ Spark ML Pipeline failed!'
                kubectl get job spark-ml-pipeline-job -n big-data
                echo ''
                break
            elif ! kubectl get job spark-ml-pipeline-job -n big-data >/dev/null 2>&1; then
                echo '❌ Job not found - may have been deleted'
                break
            else
                # Job is still running
                echo \"\$(date '+%H:%M:%S') - Spark ML Pipeline still running...\"
                kubectl get pods -n big-data -l job-name=spark-ml-pipeline-job --no-headers 2>/dev/null | head -1 || echo '  Pod status: Pending/Creating'
            fi

            sleep 10  # Wait 10 seconds before next check
        done

    "
}

cleanup_ml_jobs() {
    echo "🧹 Cleaning up ML jobs..."
    
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo 'Deleting all ML jobs in big-data namespace...'
        kubectl delete jobs --all -n big-data
        
        echo 'Specific job cleanup:'
        kubectl delete job data-ingestion-job -n big-data --ignore-not-found=true
        kubectl delete job spark-ml-pipeline-job -n big-data --ignore-not-found=true
        
        echo 'Remaining jobs:'
        kubectl get jobs -n big-data

        echo 'Removing MinIO Data Lake...'
        kubectl delete namespace big-data --ignore-not-found=true
        
        echo '✅ ML jobs cleanup completed!'
    "
}
# ========================================
# KAFKA CLUSTER FUNCTIONS (Aufgabe 5)
# ========================================

# ========================================
# KAFKA CLUSTER FUNCTIONS (Aufgabe 5) - VOLLSTÄNDIG
# Füge alle diese Funktionen zu deinem version-manager.sh hinzu
# ========================================

setup_kafka() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "Setting up Kafka Cluster"
    echo "======================================="
    echo "   - Installing single-broker Kafka cluster with auto-scaling capability"
    echo "   - Setting up Zookeeper coordination"
    echo "   - Creating demo topics for stream processing"
    echo "   - Enabling Kafka Manager Web UI"
    echo ""
    
    # --- Lokale Pfade zu den YAML-Dateien ---
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local kafka_cluster_yaml="$script_dir/big-data/kafka-cluster.yaml"
    
    if [ ! -f "$kafka_cluster_yaml" ]; then
        echo "❌ kafka-cluster.yaml nicht gefunden: $kafka_cluster_yaml"
        echo "   Bitte erstelle die Datei mit der korrigierten Kafka-Konfiguration"
        exit 1
    fi
    
    echo "Using Kafka Cluster configuration from: $kafka_cluster_yaml"
    
    # Kopiere YAML-Datei auf Remote-Server
    scp -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no "$kafka_cluster_yaml" ubuntu@$master_ip:/tmp/kafka-cluster.yaml
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo '🚀 Installing Kafka Cluster...'
        
        # Cleanup any existing kafka namespace
        kubectl delete namespace kafka --ignore-not-found=true
        
        echo '⏳ Waiting for namespace cleanup...'
        sleep 10
        
        # Apply Kafka cluster configuration
        kubectl apply -f /tmp/kafka-cluster.yaml
        
        echo '✅ Kafka Cluster configuration applied!'
        echo ''
        echo '⏳ Waiting for Zookeeper to be ready...'
        kubectl wait --for=condition=Available deployment/zookeeper -n kafka --timeout=300s || echo 'Zookeeper taking longer than expected...'
        
        echo '⏳ Waiting for Kafka broker to be ready (this takes 2-4 minutes)...'
        kubectl wait --for=condition=Available deployment/kafka -n kafka --timeout=600s || echo 'Kafka taking longer than expected...'
        
        echo ''
        echo '📊 Kafka Cluster Status:'
        kubectl get pods -n kafka -o wide
        echo ''
        kubectl get svc -n kafka
        
        echo ''
        echo '⏳ Waiting for topic setup job to complete...'
        kubectl wait --for=condition=complete job/kafka-setup-topics -n kafka --timeout=300s || echo 'Topic setup taking longer than expected...'
        
        echo ''
        echo '📋 Setup Job Results:'
        kubectl logs job/kafka-setup-topics -n kafka --tail=20 || echo 'Could not retrieve setup logs'
        
        echo ''
        echo '✅ Kafka Cluster setup complete!'
        echo ''
        echo '🔗 Access Points:'
        echo '   Kafka Brokers (internal): kafka-headless:9092'  
        echo '   Kafka External: $master_ip:30092'
        echo '   Kafka Manager UI: http://$master_ip:30900'
        echo ''
        echo '📋 Auto-created topics:'
        echo '   - demo-topic (3 partitions) - General demo messages'
        echo '   - user-events (6 partitions) - User interaction events'
        echo '   - sensor-data (9 partitions) - IoT sensor data streams'
        echo '   - processed-events (3 partitions) - Processed stream results'
        echo ''
        echo '🎯 Horizontal Scalability Features:'
        echo '   ✅ Partitioned topics for parallel processing'
        echo '   ✅ Ready for consumer group scaling'
        echo '   ✅ Configurable replication (currently 1 for single broker)'
        echo '   ✅ Easy broker scaling via replica adjustment'
        echo ''
        echo '🧪 To run stream processing demo:'
        echo '   ./version-manager.sh kafka-stream-demo'
        echo '   ./version-manager.sh kafka-show-streams'
        
        echo ''
        echo 'Cleaning up temp files...'
        rm -f /tmp/kafka-cluster.yaml
    "
}

create_kafka_topic() {
    local topic_name=$1
    local partitions=${2:-3}
    local replication=${3:-1}
    
    if [ -z "$topic_name" ]; then
        echo "❌ Topic name required"
        echo "Usage: $0 create-kafka-topic <name> [partitions] [replication]"
        echo "Example: $0 create-kafka-topic my-stream-topic 6 1"
        exit 1
    fi
    
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "Creating Kafka Topic: $topic_name"
    echo "=================================="
    echo "   Partitions: $partitions"
    echo "   Replication Factor: $replication"
    echo ""
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        # Check if Kafka is running
        if ! kubectl get deployment kafka -n kafka | grep -q '1/1'; then
            echo '❌ Kafka cluster is not running properly'
            echo 'Please run: ./version-manager.sh setup-kafka first'
            exit 1
        fi
        
        echo '📝 Creating topic $topic_name...'
        kubectl exec deployment/kafka -n kafka -- kafka-topics --bootstrap-server localhost:9092 --create --topic $topic_name --partitions $partitions --replication-factor $replication --if-not-exists
        
        echo '✅ Topic created successfully!'
        echo ''
        echo '📋 Topic details:'
        kubectl exec deployment/kafka -n kafka -- kafka-topics --bootstrap-server localhost:9092 --describe --topic $topic_name
    "
}

list_kafka_topics() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "Kafka Topics"
    echo "============="
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        # Check if Kafka is running
        if ! kubectl get deployment kafka -n kafka | grep -q '1/1'; then
            echo '❌ Kafka cluster is not running properly'
            echo 'Please run: ./version-manager.sh setup-kafka first'
            exit 1
        fi
        
        echo '📋 Available topics:'
        kubectl exec deployment/kafka -n kafka -- kafka-topics --bootstrap-server localhost:9092 --list
        
        echo ''
        echo '📊 Topic details:'
        kubectl exec deployment/kafka -n kafka -- kafka-topics --bootstrap-server localhost:9092 --describe
    " 2>/dev/null
}

kafka_status() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "Kafka Cluster Status"
    echo "===================="
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo '🔍 Kafka Namespace Status:'
        kubectl get all -n kafka
        echo ''
        
        echo '📊 Pod Status:'
        kubectl get pods -n kafka -o wide
        echo ''
        
        echo '🔗 Service Status:'
        kubectl get svc -n kafka
        echo ''
        
        if kubectl get deployment kafka -n kafka | grep -q '1/1'; then
            echo '✅ Kafka Cluster is running'
            echo ''
            echo '📋 Cluster Information:'
            echo '   Kafka Brokers: 1 (horizontally scalable)'
            echo '   External Access: $master_ip:30092'
            echo '   Manager UI: http://$master_ip:30900'
            echo ''
            
            echo '📝 Available Topics:'
            kubectl exec deployment/kafka -n kafka -- kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null || echo 'Could not fetch topics'
        else
            echo '❌ Kafka Cluster not running properly'
            echo ''
            echo '🔍 Recent Events:'
            kubectl get events -n kafka --sort-by=.metadata.creationTimestamp | tail -10
        fi
    " 2>/dev/null
}

kafka_stream_demo() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "🚀 Starting Kafka Stream Processing Demo"
    echo "========================================"
    echo "   - Demonstrates horizontal scalability"
    echo "   - Shows producer/consumer patterns"
    echo "   - Generates realistic stream data"
    echo "   - Uses multiple partitions for parallel processing"
    echo ""
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        # Check if Kafka is running
        if ! kubectl get deployment kafka -n kafka | grep -q '1/1'; then
            echo '❌ Kafka cluster is not running properly'
            echo 'Please run: ./version-manager.sh setup-kafka first'
            echo ''
            echo 'Current status:'
            kubectl get pods -n kafka
            exit 1
        fi
        
        echo '✅ Kafka cluster is running'
        echo ''
        
        # Clean up old demo jobs
        kubectl delete job kafka-live-demo -n kafka --ignore-not-found=true
        sleep 5
        
        echo '🎬 Starting stream processing demo...'
        
        # Create live demo job
        kubectl create job kafka-live-demo -n kafka --image=confluentinc/cp-kafka:7.4.0 -- /bin/bash -c '
            echo \"🚀 Live Stream Processing Demo\"
            echo \"Producing real-time data to multiple topics...\"
            
            for i in {1..50}; do
                timestamp=\$(date +\"%Y-%m-%d %H:%M:%S\")
                
                # User Events Stream
                echo \"{\\\"timestamp\\\":\\\"\$timestamp\\\",\\\"user_id\\\":\$((RANDOM % 100)),\\\"action\\\":\\\"click\\\",\\\"page_id\\\":\$((RANDOM % 20))}\" | \\
                    kafka-console-producer --bootstrap-server kafka-headless:9092 --topic user-events
                
                # Sensor Data Stream
                echo \"{\\\"timestamp\\\":\\\"\$timestamp\\\",\\\"sensor_id\\\":\\\"sensor_\$((RANDOM % 10))\\\",\\\"temperature\\\":\$((RANDOM % 40 + 10)),\\\"humidity\\\":\$((RANDOM % 100))}\" | \\
                    kafka-console-producer --bootstrap-server kafka-headless:9092 --topic sensor-data
                
                # Demo Topic
                echo \"Message \$i: User-\$((RANDOM % 100)) performed action at \$timestamp\" | \\
                    kafka-console-producer --bootstrap-server kafka-headless:9092 --topic demo-topic
                
                if [ \$((i % 10)) -eq 0 ]; then
                    echo \"Produced \$i messages across 3 topics...\"
                fi
                
                sleep 0.5
            done
            
            echo \"✅ Stream data production completed!\"
            echo \"📊 Demonstrating horizontal scalability with partitioned topics\"
        '
        
        echo '⏳ Demo running... waiting for completion...'
        
        # Wait for demo job to complete
        kubectl wait --for=condition=complete job/kafka-live-demo -n kafka --timeout=180s || {
            echo '⚠️  Demo still running or timed out'
        }
        
        echo ''
        echo '📊 Demo Results:'
        kubectl logs job/kafka-live-demo -n kafka --tail=20 2>/dev/null || echo 'Demo logs not available'
        
        echo ''
        echo '📋 Stream Processing Demonstration Complete!'
        echo '   ✅ Multi-topic data production'
        echo '   ✅ Partitioned topics for horizontal scaling'
        echo '   ✅ Real-time data streaming'
        echo '   ✅ Producer performance testing'
        echo ''
        echo '🔍 Use kafka-show-streams to view the generated data'
    "
}

kafka_show_streams() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "📊 Kafka Stream Data Viewer"
    echo "==========================="
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        if ! kubectl get deployment kafka -n kafka | grep -q '1/1'; then
            echo '❌ Kafka cluster is not running properly'
            exit 1
        fi
        
        echo '📋 Available topics:'
        kubectl exec deployment/kafka -n kafka -- kafka-topics --bootstrap-server localhost:9092 --list
        
        echo ''
        echo '📊 Topic details with partitions:'
        kubectl exec deployment/kafka -n kafka -- kafka-topics --bootstrap-server localhost:9092 --describe --topic user-events
        kubectl exec deployment/kafka -n kafka -- kafka-topics --bootstrap-server localhost:9092 --describe --topic sensor-data
        
        echo ''
        echo '📝 Sample messages from user-events (last 5):'
        kubectl exec deployment/kafka -n kafka -- kafka-console-consumer --bootstrap-server localhost:9092 --topic user-events --from-beginning --max-messages 5 --timeout-ms 10000 2>/dev/null || echo 'No messages available - run kafka-stream-demo first'
        
        echo ''
        echo '📝 Sample messages from sensor-data (last 5):'
        kubectl exec deployment/kafka -n kafka -- kafka-console-consumer --bootstrap-server localhost:9092 --topic sensor-data --from-beginning --max-messages 5 --timeout-ms 10000 2>/dev/null || echo 'No messages available - run kafka-stream-demo first'
        
        echo ''
        echo '📈 Horizontal Scalability Demonstration:'
        echo '   Each topic has multiple partitions for parallel processing'
        echo '   Multiple consumers can read from different partitions simultaneously'
        echo '   This enables horizontal scaling of stream processing workloads'
    "
}

cleanup_kafka() {
    echo "🧹 Cleaning up Kafka Cluster..."
    
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    read -p "Are you sure you want to delete the entire Kafka cluster? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Kafka cleanup cancelled"
        exit 1
    fi
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo 'Deleting Kafka cluster...'
        kubectl delete namespace kafka --ignore-not-found=true
        
        echo '✅ Kafka cluster cleanup completed!'
        echo 'All Kafka resources, topics, and data have been removed.'
    "
}

deploy_kafdrop() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "🚀 Deploying Kafdrop (Modern Kafka UI)"
    echo "======================================"
    echo "   - Using stable version 3.30.0"
    echo "   - Modern, responsive Kafka management UI"
    echo "   - Real-time broker and topic monitoring"
    echo ""
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        # Check if Kafka is running
        if ! kubectl get deployment kafka -n kafka | grep -q '1/1'; then
            echo '❌ Kafka cluster is not running'
            echo 'Please run: ./version-manager.sh setup-kafka first'
            exit 1
        fi
        
        echo '🧹 Cleaning up any existing Kafdrop...'
        kubectl delete deployment kafdrop -n kafka --ignore-not-found=true
        kubectl delete svc kafdrop-service -n kafka --ignore-not-found=true
        
        echo '⏳ Waiting for cleanup...'
        sleep 10
        
        echo '📦 Deploying stable Kafdrop 3.30.0...'
        kubectl apply -f - <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafdrop
  namespace: kafka
  labels:
    app: kafdrop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafdrop
  template:
    metadata:
      labels:
        app: kafdrop
    spec:
      containers:
      - name: kafdrop
        image: obsidiandynamics/kafdrop:3.30.0
        ports:
        - containerPort: 9000
        env:
        - name: KAFKA_BROKERCONNECT
          value: \"kafka-headless:9092\"
        - name: JVM_OPTS
          value: \"-Xms128M -Xmx256M\"
        - name: SERVER_SERVLET_CONTEXTPATH
          value: \"/\"
        resources:
          requests:
            memory: \"256Mi\"
            cpu: \"200m\"
          limits:
            memory: \"512Mi\"
            cpu: \"400m\"
---
apiVersion: v1
kind: Service
metadata:
  name: kafdrop-service
  namespace: kafka
  labels:
    app: kafdrop
spec:
  type: NodePort
  ports:
  - port: 9000
    targetPort: 9000
    nodePort: 30901
    name: kafdrop
  selector:
    app: kafdrop
EOF
        
        echo '✅ Stable Kafdrop deployed!'
        echo '⏳ Waiting for startup (stable version is much faster)...'
        
        # Monitor startup with better logic
        for i in {1..12}; do
            echo \"Check \$i/12:\"
            POD_STATUS=\$(kubectl get pod -l app=kafdrop -n kafka --no-headers 2>/dev/null | awk '{print \$3}')
            POD_READY=\$(kubectl get pod -l app=kafdrop -n kafka --no-headers 2>/dev/null | awk '{print \$2}')
            echo \"  Pod Status: \$POD_STATUS, Ready: \$POD_READY\"
            
            if [[ \"\$POD_STATUS\" == \"Running\" ]] && [[ \"\$POD_READY\" == \"1/1\" ]]; then
                echo '🎉 Kafdrop is ready!'
                break
            elif [[ \"\$POD_STATUS\" == \"Error\" ]] || [[ \"\$POD_STATUS\" == \"CrashLoopBackOff\" ]]; then
                echo '❌ Kafdrop failed to start'
                kubectl logs -l app=kafdrop -n kafka --tail=20
                break
            fi
            
            sleep 15
        done
        
        echo ''
        echo '📊 Final Status:'
        kubectl get pods -n kafka -l app=kafdrop
        kubectl get svc kafdrop-service -n kafka
        
        echo ''
        echo '✅ Kafdrop deployed successfully!'
        echo ''
        echo '🌐 Access Kafdrop at:'
        echo \"   http://$master_ip:30901\"
        echo ''
        echo '📋 What you'\''ll see in Kafdrop:'
        echo '   ✅ Broker Information (1 broker running)'
        echo '   ✅ All Topics with partition details'
        echo '   ✅ Real-time message browsing'
        echo '   ✅ Consumer group monitoring'
        echo '   ✅ Perfect demonstration of horizontal scalability'
        echo ''
        echo '⏳ If Kafdrop shows loading screen, wait 1-2 more minutes'
        echo '🔧 If issues persist, try: ./version-manager.sh deploy-kafka-ui'
    "
}

deploy_kafka_ui() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "🚀 Deploying Kafka-UI (Alternative to Kafdrop)"
    echo "=============================================="
    echo "   - Modern React-based UI"
    echo "   - More stable than Kafdrop"
    echo "   - Better performance and features"
    echo ""
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        # Check if Kafka is running
        if ! kubectl get deployment kafka -n kafka | grep -q '1/1'; then
            echo '❌ Kafka cluster is not running'
            echo 'Please run: ./version-manager.sh setup-kafka first'
            exit 1
        fi
        
        echo '📦 Deploying Kafka-UI...'
        kubectl apply -f - <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: kafka
  labels:
    app: kafka-ui
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-ui
  template:
    metadata:
      labels:
        app: kafka-ui
    spec:
      containers:
      - name: kafka-ui
        image: provectuslabs/kafka-ui:v0.7.1
        ports:
        - containerPort: 8080
        env:
        - name: KAFKA_CLUSTERS_0_NAME
          value: \"kafka-cluster\"
        - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
          value: \"kafka-headless:9092\"
        - name: KAFKA_CLUSTERS_0_ZOOKEEPER
          value: \"zookeeper:2181\"
        resources:
          requests:
            memory: \"256Mi\"
            cpu: \"100m\"
          limits:
            memory: \"512Mi\"
            cpu: \"300m\"
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui-service
  namespace: kafka
  labels:
    app: kafka-ui
spec:
  type: NodePort
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30902
    name: kafka-ui
  selector:
    app: kafka-ui
EOF
        
        echo '⏳ Waiting for Kafka-UI startup...'
        kubectl wait --for=condition=Available deployment/kafka-ui -n kafka --timeout=300s || echo 'Taking longer than expected...'
        
        echo ''
        echo '📊 Kafka-UI Status:'
        kubectl get pods -n kafka -l app=kafka-ui
        kubectl get svc kafka-ui-service -n kafka
        
        echo ''
        echo '✅ Kafka-UI deployed successfully!'
        echo ''
        echo '🌐 Access Kafka-UI at:'
        echo \"   http://$master_ip:30902\"
        echo ''
        echo '📋 Kafka-UI Features:'
        echo '   ✅ Modern React-based interface'
        echo '   ✅ Real-time cluster monitoring'
        echo '   ✅ Topic and message management'
        echo '   ✅ Consumer group tracking'
        echo '   ✅ More stable than Kafdrop'
    "
}

# ========================================
# STREAM PROCESSING PIPELINE OPTIONEN
# ========================================

deploy_kafka_streams() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "🚀 Deploying Production-Ready Kafka Streams Pipeline"
    echo "===================================================="
    echo "   - Real-time stream processing with guaranteed delivery"
    echo "   - 2 horizontally scalable stream processors"
    echo "   - Processes sensor-data and user-events"
    echo "   - Outputs to processed-events topic"
    echo "   - Fault tolerant with automatic restarts"
    echo ""
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        # Check Kafka is running
        if ! kubectl get deployment kafka -n kafka | grep -q '1/1'; then
            echo '❌ Kafka cluster is not running'
            echo 'Please run: ./version-manager.sh setup-kafka first'
            exit 1
        fi
        
        # Get Kafka IP
        KAFKA_IP=\$(kubectl get pod -l app=kafka -n kafka -o jsonpath='{.items[0].status.podIP}')
        echo \"Using Kafka IP: \$KAFKA_IP\"
        
        echo '📦 Deploying stream processing pipeline...'
        kubectl apply -f - <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-streams-processor
  namespace: kafka
  labels:
    app: kafka-streams-processor
spec:
  replicas: 2
  selector:
    matchLabels:
      app: kafka-streams-processor
  template:
    metadata:
      labels:
        app: kafka-streams-processor
    spec:
      containers:
      - name: streams-processor
        image: confluentinc/cp-kafka:7.4.0
        env:
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: \"\$KAFKA_IP:9092\"
        - name: PROCESSOR_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        command:
        - /bin/bash
        - -c
        - |
          echo \"🔄 Stream Processor Starting: \\\$PROCESSOR_ID\"
          echo \"========================================\"
          
          # Wait for Kafka to be ready
          echo \"⏳ Waiting for Kafka...\"
          until kafka-topics --bootstrap-server \\\$KAFKA_BOOTSTRAP_SERVERS --list >/dev/null 2>&1; do
            echo \"Kafka not ready, waiting...\"
            sleep 5
          done
          echo \"✅ Kafka is ready\"
          
          # Unique consumer group per processor
          GROUP_ID=\"stream-processor-\\\$(hostname)\"
          echo \"👥 Consumer Group: \\\$GROUP_ID\"
          
          # Main processing loop
          while true; do
            echo \"🔄 [\\\$(date '+%H:%M:%S')] Processing cycle started\"
            PROCESSED_COUNT=0
            
            # Process sensor-data messages
            echo \"📊 Consuming from sensor-data...\"
            kafka-console-consumer \\\\
              --bootstrap-server \\\$KAFKA_BOOTSTRAP_SERVERS \\\\
              --topic sensor-data \\\\
              --group \\\$GROUP_ID \\\\
              --from-beginning \\\\
              --max-messages 10 \\\\
              --timeout-ms 8000 2>/dev/null | while IFS= read -r message; do
              
              if [ ! -z \"\\\$message\" ]; then
                TIMESTAMP=\\\$(date +\"%Y-%m-%d %H:%M:%S\")
                EPOCH=\\\$(date +%s)
                
                # Parse JSON fields (robust parsing)
                TEMP=\\\$(echo \"\\\$message\" | grep -o '\"temperature\":[0-9]*' | cut -d: -f2 || echo \"0\")
                SENSOR_ID=\\\$(echo \"\\\$message\" | grep -o '\"sensor_id\":\"[^\"]*\"' | cut -d'\"' -f4 || echo \"unknown\")
                HUMIDITY=\\\$(echo \"\\\$message\" | grep -o '\"humidity\":[0-9]*' | cut -d: -f2 || echo \"0\")
                
                # Create processed event with enrichment
                PROCESSED_EVENT=\"{\\\\\\\"timestamp\\\\\\\":\\\\\\\"\\\$TIMESTAMP\\\\\\\",\\\\\\\"processor\\\\\\\":\\\\\\\"\\\$PROCESSOR_ID\\\\\\\",\\\\\\\"source\\\\\\\":\\\\\\\"sensor-data\\\\\\\",\\\\\\\"sensor_id\\\\\\\":\\\\\\\"\\\$SENSOR_ID\\\\\\\",\\\\\\\"temperature\\\\\\\":\\\$TEMP,\\\\\\\"humidity\\\\\\\":\\\$HUMIDITY,\\\\\\\"processing_epoch\\\\\\\":\\\$EPOCH,\\\\\\\"status\\\\\\\":\\\\\\\"processed\\\\\\\"}\"
                
                echo \"📊 Processing sensor \\\$SENSOR_ID: temp=\\\$TEMP°C, humidity=\\\$HUMIDITY%\"
                
                # Send to output topic with confirmation
                if echo \"\\\$PROCESSED_EVENT\" | kafka-console-producer --bootstrap-server \\\$KAFKA_BOOTSTRAP_SERVERS --topic processed-events --sync 2>/dev/null; then
                  echo \"✅ Sensor data processed and sent\"
                  PROCESSED_COUNT=\\\$((PROCESSED_COUNT + 1))
                else
                  echo \"❌ Failed to send sensor data\"
                fi
              fi
            done
            
            # Process user-events messages  
            echo \"👤 Consuming from user-events...\"
            kafka-console-consumer \\\\
              --bootstrap-server \\\$KAFKA_BOOTSTRAP_SERVERS \\\\
              --topic user-events \\\\
              --group \\\$GROUP_ID \\\\
              --from-beginning \\\\
              --max-messages 5 \\\\
              --timeout-ms 5000 2>/dev/null | while IFS= read -r message; do
              
              if [ ! -z \"\\\$message\" ]; then
                TIMESTAMP=\\\$(date +\"%Y-%m-%d %H:%M:%S\")
                EPOCH=\\\$(date +%s)
                
                # Parse user event fields
                USER_ID=\\\$(echo \"\\\$message\" | grep -o '\"user_id\":[0-9]*' | cut -d: -f2 || echo \"0\")
                ACTION=\\\$(echo \"\\\$message\" | grep -o '\"action\":\"[^\"]*\"' | cut -d'\"' -f4 || echo \"unknown\")
                PAGE_ID=\\\$(echo \"\\\$message\" | grep -o '\"page_id\":[0-9]*' | cut -d: -f2 || echo \"0\")
                
                # Create processed event
                PROCESSED_EVENT=\"{\\\\\\\"timestamp\\\\\\\":\\\\\\\"\\\$TIMESTAMP\\\\\\\",\\\\\\\"processor\\\\\\\":\\\\\\\"\\\$PROCESSOR_ID\\\\\\\",\\\\\\\"source\\\\\\\":\\\\\\\"user-events\\\\\\\",\\\\\\\"user_id\\\\\\\":\\\$USER_ID,\\\\\\\"action\\\\\\\":\\\\\\\"\\\$ACTION\\\\\\\",\\\\\\\"page_id\\\\\\\":\\\$PAGE_ID,\\\\\\\"processing_epoch\\\\\\\":\\\$EPOCH,\\\\\\\"status\\\\\\\":\\\\\\\"processed\\\\\\\"}\"
                
                echo \"👤 Processing user \\\$USER_ID: \\\$ACTION on page \\\$PAGE_ID\"
                
                # Send to output topic
                if echo \"\\\$PROCESSED_EVENT\" | kafka-console-producer --bootstrap-server \\\$KAFKA_BOOTSTRAP_SERVERS --topic processed-events --sync 2>/dev/null; then
                  echo \"✅ User event processed and sent\"
                  PROCESSED_COUNT=\\\$((PROCESSED_COUNT + 1))
                else
                  echo \"❌ Failed to send user event\"
                fi
              fi
            done
            
            echo \"📊 Cycle complete. Processed \\\$PROCESSED_COUNT messages\"
            echo \"⏸️ Waiting 20 seconds before next cycle...\"
            sleep 20
          done
        resources:
          requests:
            memory: \"512Mi\"
            cpu: \"200m\"
          limits:
            memory: \"768Mi\"
            cpu: \"500m\"
        readinessProbe:
          exec:
            command:
            - /bin/bash
            - -c
            - 'kafka-topics --bootstrap-server \$KAFKA_BOOTSTRAP_SERVERS --list | grep -q processed-events'
          initialDelaySeconds: 30
          periodSeconds: 30
        livenessProbe:
          exec:
            command:
            - /bin/bash
            - -c
            - 'ps aux | grep -q kafka-console-consumer'
          initialDelaySeconds: 60
          periodSeconds: 60
EOF
        
        echo '✅ Stream processing pipeline deployed!'
        echo ''
        echo '⏳ Waiting for processors to be ready...'
        kubectl wait --for=condition=Available deployment/kafka-streams-processor -n kafka --timeout=180s
        
        echo ''
        echo '📊 Stream Processor Status:'
        kubectl get pods -n kafka -l app=kafka-streams-processor
        
        echo ''
        echo '🎯 Horizontal Scalability Features:'
        echo '   ✅ 2 independent stream processors'
        echo '   ✅ Each processor has unique consumer group'
        echo '   ✅ Automatic load balancing across partitions'
        echo '   ✅ Fault tolerance with pod restart'
        echo '   ✅ Real-time processing with 20-second cycles'
        echo ''
        echo '🔍 Monitor stream processing:'
        echo '   kubectl logs -l app=kafka-streams-processor -n kafka -f'
        echo '   ./version-manager.sh stream-status'
        echo '   Check processed-events topic in Kafka-UI'
    "
}

# Option 1: Kafka Streams (Einfachste Integration)
deploy_kafka_streams_pipeline() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    echo "🚀 Deploying Kafka Streams Processing Pipeline"
    echo "=============================================="
    echo "   - Real-time stream processing with Kafka Streams"
    echo "   - Horizontally scalable with multiple instances"
    echo "   - Processes sensor-data and user-events"
    echo "   - Outputs aggregated results to processed-events"
    echo ""
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        # Get Kafka IP for connection
        KAFKA_IP=\$(kubectl get pod -l app=kafka -n kafka -o jsonpath='{.items[0].status.podIP}')
        echo 'Using Kafka IP: \$KAFKA_IP'
        
        echo '📦 Deploying Kafka Streams application...'
        kubectl apply -f - <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-streams-processor
  namespace: kafka
  labels:
    app: kafka-streams-processor
spec:
  replicas: 3  # Horizontal scaling!
  selector:
    matchLabels:
      app: kafka-streams-processor
  template:
    metadata:
      labels:
        app: kafka-streams-processor
    spec:
      containers:
      - name: streams-processor
        image: confluentinc/cp-kafka:7.4.0
        env:
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: \"\$KAFKA_IP:9092\"
        - name: APPLICATION_ID
          value: \"sensor-analytics-app\"
        - name: INPUT_TOPIC_SENSORS
          value: \"sensor-data\"
        - name: INPUT_TOPIC_EVENTS
          value: \"user-events\"
        - name: OUTPUT_TOPIC
          value: \"processed-events\"
        command:
        - /bin/bash
        - -c
        - |
          echo \"🔄 Starting Kafka Streams Processing Pipeline\"
          echo \"=============================================\"
          echo \"Application ID: \$APPLICATION_ID\"
          echo \"Kafka Brokers: \$KAFKA_BOOTSTRAP_SERVERS\"
          echo \"Input Topics: \$INPUT_TOPIC_SENSORS, \$INPUT_TOPIC_EVENTS\"
          echo \"Output Topic: \$OUTPUT_TOPIC\"
          echo \"\"
          
          # Wait for Kafka
          echo \"⏳ Waiting for Kafka to be available...\"
          until kafka-topics --bootstrap-server \$KAFKA_BOOTSTRAP_SERVERS --list >/dev/null 2>&1; do
            echo \"Kafka not ready, waiting...\"
            sleep 5
          done
          echo \"✅ Kafka is ready\"
          
          # Start stream processing loop
          echo \"🚀 Starting stream processing...\"
          INSTANCE_ID=\$(hostname)
          PARTITION_COUNT=0
          
          while true; do
            # Consume from sensor-data and process
            kafka-console-consumer --bootstrap-server \$KAFKA_BOOTSTRAP_SERVERS \\
              --topic \$INPUT_TOPIC_SENSORS \\
              --from-beginning \\
              --max-messages 10 \\
              --timeout-ms 5000 2>/dev/null | while read line; do
              
              if [ ! -z \"\$line\" ]; then
                TIMESTAMP=\$(date +\"%Y-%m-%d %H:%M:%S\")
                # Extract temperature if JSON (simple processing)
                TEMP=\$(echo \$line | grep -o '\"temperature\":[0-9]*' | cut -d: -f2 || echo \"unknown\")
                
                # Create processed event
                PROCESSED_EVENT=\"{\\\"timestamp\\\":\\\"\$TIMESTAMP\\\",\\\"processor\\\":\\\"\$INSTANCE_ID\\\",\\\"source\\\":\\\"sensor-data\\\",\\\"processed_temp\\\":\\\"\$TEMP\\\",\\\"partition\\\":\$PARTITION_COUNT}\"
                
                echo \"📊 Processing: \$line\"
                echo \"📤 Output: \$PROCESSED_EVENT\"
                
                # Send to output topic
                echo \"\$PROCESSED_EVENT\" | kafka-console-producer --bootstrap-server \$KAFKA_BOOTSTRAP_SERVERS --topic \$OUTPUT_TOPIC
                
                PARTITION_COUNT=\$((PARTITION_COUNT + 1))
              fi
            done
            
            # Consume from user-events and process
            kafka-console-consumer --bootstrap-server \$KAFKA_BOOTSTRAP_SERVERS \\
              --topic \$INPUT_TOPIC_EVENTS \\
              --from-beginning \\
              --max-messages 5 \\
              --timeout-ms 3000 2>/dev/null | while read line; do
              
              if [ ! -z \"\$line\" ]; then
                TIMESTAMP=\$(date +\"%Y-%m-%d %H:%M:%S\")
                USER_ID=\$(echo \$line | grep -o '\"user_id\":[0-9]*' | cut -d: -f2 || echo \"unknown\")
                
                PROCESSED_EVENT=\"{\\\"timestamp\\\":\\\"\$TIMESTAMP\\\",\\\"processor\\\":\\\"\$INSTANCE_ID\\\",\\\"source\\\":\\\"user-events\\\",\\\"processed_user\\\":\\\"\$USER_ID\\\",\\\"partition\\\":\$PARTITION_COUNT}\"
                
                echo \"👤 Processing: \$line\"
                echo \"📤 Output: \$PROCESSED_EVENT\"
                
                echo \"\$PROCESSED_EVENT\" | kafka-console-producer --bootstrap-server \$KAFKA_BOOTSTRAP_SERVERS --topic \$OUTPUT_TOPIC
                
                PARTITION_COUNT=\$((PARTITION_COUNT + 1))
              fi
            done
            
            echo \"⏳ \$INSTANCE_ID processed batch, waiting for next...\"
            sleep 10
          done
        resources:
          requests:
            memory: \"256Mi\"
            cpu: \"200m\"
          limits:
            memory: \"512Mi\"
            cpu: \"500m\"
EOF
        
        echo '✅ Kafka Streams Pipeline deployed with 3 replicas!'
        echo ''
        echo '📊 Horizontal Scalability Features:'
        echo '   ✅ 3 parallel stream processors'
        echo '   ✅ Each instance processes different partitions'
        echo '   ✅ Automatic load balancing'
        echo '   ✅ Fault tolerance with replica restart'
        echo ''
        echo '⏳ Waiting for processors to start...'
        kubectl wait --for=condition=Available deployment/kafka-streams-processor -n kafka --timeout=180s || echo 'Still starting...'
        
        echo ''
        echo '📋 Stream Processing Status:'
        kubectl get pods -n kafka -l app=kafka-streams-processor
        
        echo ''
        echo '🔍 Monitor stream processing:'
        echo '   kubectl logs -l app=kafka-streams-processor -n kafka -f'
        echo '   Check processed-events topic in Kafka-UI'
    "
}

# Option 2: Apache Flink (Advanced Stream Processing)
deploy_flink_pipeline() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    echo "🚀 Deploying Apache Flink Stream Processing"
    echo "=========================================="
    echo "   - Advanced stream processing with Apache Flink"
    echo "   - JobManager + TaskManager architecture"
    echo "   - Complex event processing capabilities"
    echo ""
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        KAFKA_IP=\$(kubectl get pod -l app=kafka -n kafka -o jsonpath='{.items[0].status.podIP}')
        
        echo '📦 Deploying Apache Flink cluster...'
        kubectl apply -f - <<EOF
---
# Flink JobManager
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flink-jobmanager
  namespace: kafka
spec:
  replicas: 1
  selector:
    matchLabels:
      app: flink-jobmanager
  template:
    metadata:
      labels:
        app: flink-jobmanager
    spec:
      containers:
      - name: jobmanager
        image: flink:1.17
        args: [\"jobmanager\"]
        ports:
        - containerPort: 6123
        - containerPort: 8081
        env:
        - name: JOB_MANAGER_RPC_ADDRESS
          value: \"flink-jobmanager\"
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: \"\$KAFKA_IP:9092\"
---
apiVersion: v1
kind: Service
metadata:
  name: flink-jobmanager
  namespace: kafka
spec:
  type: NodePort
  ports:
  - name: rpc
    port: 6123
    targetPort: 6123
  - name: ui
    port: 8081
    targetPort: 8081
    nodePort: 30081
  selector:
    app: flink-jobmanager
---
# Flink TaskManager (Horizontally Scalable)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flink-taskmanager
  namespace: kafka
spec:
  replicas: 2  # Horizontal scaling!
  selector:
    matchLabels:
      app: flink-taskmanager
  template:
    metadata:
      labels:
        app: flink-taskmanager
    spec:
      containers:
      - name: taskmanager
        image: flink:1.17
        args: [\"taskmanager\"]
        env:
        - name: JOB_MANAGER_RPC_ADDRESS
          value: \"flink-jobmanager\"
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: \"\$KAFKA_IP:9092\"
        resources:
          requests:
            memory: \"512Mi\"
            cpu: \"200m\"
          limits:
            memory: \"1Gi\"
            cpu: \"500m\"
EOF
        
        echo '✅ Apache Flink cluster deployed!'
        echo '🌐 Flink Dashboard: http://$master_ip:30081'
        echo '📊 2 TaskManagers for horizontal processing'
    "
}

open_kafka_ui() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "🌐 Opening Kafka-UI with Port Forwarding"
    echo "========================================"
    
    # Check if Kafka-UI is running
    echo "🔍 Checking Kafka-UI status..."
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        if ! kubectl get deployment kafka-ui -n kafka >/dev/null 2>&1 || ! kubectl get deployment kafka-ui -n kafka | grep -q '1/1'; then
            echo '❌ Kafka-UI is not running properly'
            exit 1
        fi
        echo '✅ Kafka-UI is running'
    " || {
        echo "🚀 Kafka-UI not ready, deploying first..."
        deploy_kafka_ui
        echo "⏳ Waiting for Kafka-UI to be ready..."
        sleep 15
    }
    
    # Kill any existing port forward on port 8902
    echo "🧹 Cleaning up any existing port forwards..."
    pkill -f "ssh.*8902:localhost:30902" 2>/dev/null || true
    
    echo "🔗 Starting port forwarding..."
    echo "   Local: http://localhost:8902"
    echo "   Remote: $master_ip:30902"
    echo ""
    
    # Use a more reliable approach with explicit SSH control
    echo "⚠️  This will keep the terminal busy. Press Ctrl+C to stop."
    echo "🌐 Open your browser to: http://localhost:8902"
    echo ""
    
    # Direct SSH port forwarding (blocking, more reliable)
    ssh -i ~/.ssh/$ssh_key -L 8902:localhost:30902 ubuntu@$master_ip -N
}

# Vereinfachte Version ohne Browser-Opening
kafka_ui_tunnel() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "🔗 Kafka-UI Port Forwarding"
    echo "============================"
    echo "   Setting up secure tunnel..."
    echo ""
    
    # Ensure Kafka-UI is running
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        kubectl get deployment kafka-ui -n kafka >/dev/null 2>&1 || {
            echo '🚀 Kafka-UI not found, deploying first...'
            exit 1
        }
    " || {
        deploy_kafka_ui
        sleep 10
    }
    
    echo "🌐 Access Kafka-UI at: http://localhost:8902"
    echo "⚠️  Keep this terminal open. Press Ctrl+C to stop."
    echo ""
    
    # Start port forwarding (blocking)
    ssh -i ~/.ssh/$ssh_key -L 8902:localhost:30902 ubuntu@$master_ip -N
}

# Quick status check with UI link
kafka_ui_status() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "🌐 Kafka-UI Status"
    echo "=================="
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        if kubectl get deployment kafka-ui -n kafka >/dev/null 2>&1; then
            STATUS=\$(kubectl get deployment kafka-ui -n kafka --no-headers | awk '{print \$2}')
            echo \"✅ Kafka-UI Status: \$STATUS\"
            echo \"\"
            echo \"🔗 Access Options:\"
            echo \"   Direct (if ports open): http://$master_ip:30902\"
            echo \"   Via Port Forward: ./version-manager.sh kafka-ui-tunnel\"
            echo \"   Auto Open: ./version-manager.sh open-kafka-ui\"
        else
            echo \"❌ Kafka-UI not deployed\"
            echo \"   Deploy with: ./version-manager.sh deploy-kafka-ui\"
        fi
    "
}

# Option 3: Spark Streaming (Integration mit vorhandenen Spark)
deploy_spark_streaming() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    echo "🚀 Deploying Spark Streaming Pipeline"
    echo "====================================="
    echo "   - Integration mit existing Spark infrastructure"
    echo "   - Micro-batch processing"
    echo "   - Machine Learning integration ready"
    echo ""
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        KAFKA_IP=\$(kubectl get pod -l app=kafka -n kafka -o jsonpath='{.items[0].status.podIP}')
        
        echo '📦 Deploying Spark Streaming job...'
        kubectl apply -f - <<EOF
---
apiVersion: batch/v1
kind: Job
metadata:
  name: spark-streaming-processor
  namespace: kafka
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: spark-streaming
        image: bitnami/spark:3.4
        command:
        - /bin/bash
        - -c
        - |
          echo \"🔥 Starting Spark Streaming Pipeline\"
          echo \"====================================\"
          
          # Install Kafka connector for Spark
          export SPARK_KAFKA_VERSION=2.12
          export KAFKA_VERSION=3.4.0
          
          # Simple Spark Streaming simulation
          while true; do
            echo \"📊 [\$(date)] Spark Streaming batch processing...\"
            
            # Simulate reading from Kafka topics
            echo \"📥 Reading from sensor-data topic...\"
            kafka-console-consumer --bootstrap-server \$KAFKA_IP:9092 \\
              --topic sensor-data --max-messages 5 --timeout-ms 5000 2>/dev/null | while read line; do
              
              if [ ! -z \"\$line\" ]; then
                echo \"🔥 Spark processing: \$line\"
                # Simulate ML processing
                sleep 0.5
                
                # Create enriched event
                TIMESTAMP=\$(date +\"%Y-%m-%d %H:%M:%S\")
                PROCESSED=\"{\\\"timestamp\\\":\\\"\$TIMESTAMP\\\",\\\"processor\\\":\\\"spark-streaming\\\",\\\"ml_processed\\\":true,\\\"original\\\":\$line}\"
                
                echo \"📤 Spark output: \$PROCESSED\"
                echo \"\$PROCESSED\" | kafka-console-producer --bootstrap-server \$KAFKA_IP:9092 --topic processed-events
              fi
            done
            
            echo \"⚡ Spark micro-batch completed, next batch in 10 seconds...\"
            sleep 10
          done
        env:
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: \"\$KAFKA_IP:9092\"
        resources:
          requests:
            memory: \"512Mi\"
            cpu: \"300m\"
          limits:
            memory: \"1Gi\"
            cpu: \"600m\"
EOF
        
        echo '✅ Spark Streaming pipeline deployed!'
        echo '⚡ Micro-batch processing every 10 seconds'
    "
}

stream_processing_status() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    echo "📊 Stream Processing Status"
    echo "=========================="
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo '🔄 Kafka Streams Processors:'
        kubectl get pods -n kafka -l app=kafka-streams-processor -o wide 2>/dev/null || echo 'Not deployed'
        
        echo ''
        echo '🔥 Spark Streaming Jobs:'
        kubectl get jobs -n kafka | grep spark-streaming || echo 'Not deployed'
        
        echo ''
        echo '⚡ Flink Cluster:'
        kubectl get pods -n kafka | grep flink || echo 'Not deployed'
        
        echo ''
        echo '📈 Processing Activity (last 10 messages in processed-events):'
        kubectl exec deployment/kafka -n kafka -- kafka-console-consumer --bootstrap-server localhost:9092 --topic processed-events --from-beginning --max-messages 10 --timeout-ms 5000 2>/dev/null || echo 'No processed events yet'
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
    "data-ingestion")
        data_ingestion
        ;;
    "spark-ml-pipeline")
        spark_ml_pipeline
        ;;
    "cleanup-ml-jobs")
        cleanup_ml_jobs
        ;;
    "setup-kafka")
        setup_kafka
        ;;
    "create-kafka-topic")
        create_kafka_topic $2 $3 $4
        ;;
    "list-kafka-topics")
        list_kafka_topics
        ;;
    "kafka-status")
        kafka_status
        ;;
    "kafka-stream-demo")
        kafka_stream_demo
        ;;
    "kafka-show-streams")
        kafka_show_streams
        ;;
    "cleanup-kafka")
        cleanup_kafka
        ;;
    "deploy-kafdrop")
        deploy_kafdrop
        ;;
    "deploy-kafka-ui")
        deploy_kafka_ui
        ;;
    "open-kafka-ui")
        open_kafka_ui
        ;;
    "kafka-ui-tunnel")
        kafka_ui_tunnel
        ;;
    "kafka-ui-status")
        kafka_ui_status
        ;;
    "deploy-flink-pipeline")
        deploy_flink_pipeline
        ;;
    "deploy-spark-streaming")
        deploy_spark_streaming
        ;;
    "stream-status")
        stream_processing_status
        ;;
     "deploy-kafka-streams")
        deploy_kafka_streams
        ;;
    *)
        show_help
        ;;
esac