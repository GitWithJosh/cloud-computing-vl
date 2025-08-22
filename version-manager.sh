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
    echo "  setup-kafka            - Install Kafka cluster"
    echo "  create-kafka-topic <name> [partitions] [replication] - Create Kafka topic"
    echo "  list-kafka-topics      - List all Kafka topics"
    echo "  kafka-status           - Show Kafka cluster status"
    echo "  cleanup-kafka          - Delete Kafka cluster"
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
# Aufgabe 5
# KAFKA CLUSTER FUNCTIONS
# ========================================

setup_kafka_cluster() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "Setting up Kafka Cluster"
    echo "======================================="
    
    # --- Local paths to YAML files ---
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local kafka_yaml="$script_dir/big-data/kafka-cluster.yaml"
    if [ ! -f "$kafka_yaml" ]; then
        echo "❌ kafka-cluster.yaml not found: $kafka_yaml"
        exit 1
    fi
    
    # Copy YAML files to remote server
    scp -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no "$kafka_yaml" ubuntu@$master_ip:/tmp/kafka-cluster.yaml
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo 'Installing Kafka Cluster...'
        kubectl apply -f /tmp/kafka-cluster.yaml
        
        echo 'Waiting for Zookeeper to be ready...'
        kubectl wait --for=condition=available --timeout=300s deployment/zookeeper -n kafka || echo 'Zookeeper taking longer than expected...'
        
        echo 'Waiting for Kafka Broker to be ready...'
        kubectl wait --for=condition=available --timeout=300s deployment/kafka-broker -n kafka || echo 'Kafka broker taking longer than expected...'
        
        echo 'Waiting for Kafka Manager to be ready...'
        kubectl wait --for=condition=available --timeout=300s deployment/kafka-manager -n kafka || echo 'Kafka manager taking longer than expected...'
        
        echo 'Kafka Cluster Status:'
        kubectl get pods -n kafka
        
        echo '✅ Kafka Cluster setup complete!'
        echo 'Kafka Broker: $master_ip:30092'
        echo 'Kafka Manager UI: http://$master_ip:30910'
        
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
        echo "Usage: ./version-manager.sh create-kafka-topic <topic-name> [partitions] [replication-factor]"
        exit 1
    fi
    
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "Creating Kafka Topic: $topic_name (partitions: $partitions, replication: $replication)"
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        # Run kafka-topics command inside the kafka broker pod
        KAFKA_POD=\$(kubectl get pods -n kafka -l app=kafka -o jsonpath='{.items[0].metadata.name}')
        
        echo 'Using Kafka pod: '\$KAFKA_POD
        
        kubectl exec -n kafka \$KAFKA_POD -- \
          kafka-topics --create --topic $topic_name \
          --partitions $partitions \
          --replication-factor $replication \
          --bootstrap-server kafka-service:9092
          
        echo 'Topic $topic_name created successfully!'
        echo 'Listing all topics:'
        kubectl exec -n kafka \$KAFKA_POD -- \
          kafka-topics --list --bootstrap-server kafka-service:9092
    "
}

list_kafka_topics() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "Listing Kafka Topics"
    
    ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
        # Run kafka-topics command inside the kafka broker pod
        KAFKA_POD=\$(kubectl get pods -n kafka -l app=kafka -o jsonpath='{.items[0].metadata.name}')
        
        echo 'Using Kafka pod: '\$KAFKA_POD
        
        echo 'Available Kafka topics:'
        kubectl exec -n kafka \$KAFKA_POD -- \
          kafka-topics --list --bootstrap-server kafka-service:9092
    "
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
        echo '=== Kafka Pods ==='
        kubectl get pods -n kafka
        
        echo '=== Kafka Services ==='
        kubectl get svc -n kafka
        
        echo '=== Kafka Broker Details ==='
        KAFKA_POD=\$(kubectl get pods -n kafka -l app=kafka -o jsonpath='{.items[0].metadata.name}')
        if [ -n \"\$KAFKA_POD\" ]; then
            echo 'Broker Pod: '\$KAFKA_POD
            kubectl exec -n kafka \$KAFKA_POD -- kafka-broker-api-versions --bootstrap-server kafka-service:9092
        else
            echo 'No Kafka broker pod found'
        fi
        
        echo '=== Access Information ==='
        echo 'Kafka Broker: $master_ip:30092'
        echo 'Kafka Manager UI: http://$master_ip:30910'
    "
}

cleanup_kafka() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local ssh_key=$(get_ssh_key)
    
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "🧹 Cleaning up Kafka Cluster..."
    read -p "Are you sure you want to delete the Kafka cluster? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
            echo 'Deleting Kafka namespace and all resources...'
            kubectl delete namespace kafka
            echo '✅ Kafka cluster removed successfully'
        "
    else
        echo "Cleanup cancelled"
    fi
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
        setup_kafka_cluster
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
    "cleanup-kafka")
        cleanup_kafka
        ;;
    *)
        show_help
        ;;
esac