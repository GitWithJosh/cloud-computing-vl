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

# Robuste Terraform Workspace Management Funktion
safe_workspace_delete() {
    local workspace_name=$1
    local current_workspace
    current_workspace=$(terraform workspace show 2>/dev/null)
    
    if [ -z "$workspace_name" ]; then
        echo "⚠️ No workspace name provided for deletion"
        return 1
    fi
    
    # Prüfe ob Workspace existiert
    if ! terraform workspace list 2>/dev/null | grep -q -E "^\s*${workspace_name}$|^\*\s*${workspace_name}$"; then
        echo "ℹ️ Workspace '$workspace_name' does not exist, skipping deletion"
        return 0
    fi
    
    # Prüfe ob wir in der zu löschenden Workspace sind
    if [ "$current_workspace" = "$workspace_name" ]; then
        echo "🔄 Switching away from workspace '$workspace_name' before deletion..."
        if ! terraform workspace select default 2>/dev/null; then
            echo "❌ Could not switch to default workspace, which is required to delete '$workspace_name'"
            return 1
        fi
    fi
    
    # Lösche Workspace
    echo "🗑️ Deleting workspace '$workspace_name'..."
    if terraform workspace delete "$workspace_name" 2>/dev/null; then
        echo "✅ Workspace '$workspace_name' deleted successfully"
        return 0
    else
        echo "⚠️ Could not delete workspace '$workspace_name'. It might not be empty."
        echo "   Attempting to destroy resources in '$workspace_name' before deleting again."
        
        # Temporär zum Workspace wechseln, um 'destroy' auszuführen
        if ! terraform workspace select "$workspace_name" 2>/dev/null; then
            echo "❌ Could not switch to workspace '$workspace_name' to destroy it."
            terraform workspace select default >/dev/null 2>&1
            return 1
        fi

        # Zerstöre die Ressourcen in diesem Workspace
        if ! terraform destroy -auto-approve > /dev/null 2>&1; then
            echo "❌ Failed to destroy resources in '$workspace_name'. Manual cleanup required."
            terraform workspace select default >/dev/null 2>&1
            return 1
        fi
        
        echo "✅ Resources in '$workspace_name' destroyed."
        
        # Zurück zum Default-Workspace und erneut versuchen zu löschen
        if ! terraform workspace select default 2>/dev/null; then
            echo "❌ Could not switch back to default workspace after destroying '$workspace_name'."
            return 1
        fi
        
        echo "🗑️ Retrying to delete workspace '$workspace_name'..."
        if terraform workspace delete "$workspace_name" 2>/dev/null; then
            echo "✅ Workspace '$workspace_name' deleted successfully on second attempt."
            return 0
        else
            echo "❌ Failed to delete workspace '$workspace_name' even after destroying resources. Manual cleanup required."
            return 1
        fi
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
    echo "📦 Installing ML dependencies (this usually takes 10-15 minutes)..."
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

    # Sicherstellen, dass der 'default' Workspace existiert
    if ! terraform workspace list 2>/dev/null | grep -q 'default'; then
        terraform workspace new default >/dev/null 2>&1
    fi
    terraform workspace select default >/dev/null 2>&1
    
    # Check if current infrastructure exists
    if [ ! -f terraform.tfstate ] || [ ! -s terraform.tfstate ] || [ -z "$(terraform state list 2>/dev/null)" ]; then
        echo "ℹ️ No existing infrastructure found in 'default' workspace. Using 'deploy' for initial deployment."
        deploy_version "$new_version"
        exit $?
    fi
    
    # Get current infrastructure details
    echo "📊 Current infrastructure status (Workspace: default):"
    local current_master_ip
    current_master_ip=$(terraform output -raw master_ip 2>/dev/null)
    local current_deployment_id
    current_deployment_id=$(terraform output -raw deployment_id 2>/dev/null)

    if [ -z "$current_master_ip" ]; then
        echo "❌ Cannot determine current master IP from 'default' workspace. Please check the state."
        exit 1
    fi
    
    echo "Current Master IP: $current_master_ip"
    echo "Current Deployment ID: $current_deployment_id"
    
    # Get current version and create backup
    local current_version
    current_version=$(git describe --tags --exact-match HEAD 2>/dev/null || echo "main")
    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local blue_workspace="blue-$backup_timestamp"
    local green_workspace="green-$backup_timestamp"
    
    echo "Current version: $current_version"
    echo "Target version: $new_version"
    
    # Rename 'default' workspace to 'blue' to preserve it
    echo "🔵 Renaming 'default' workspace to '$blue_workspace' to preserve the current Blue environment."
    if ! terraform workspace new "$blue_workspace" 2>/dev/null; then
        echo "❌ Failed to create backup workspace '$blue_workspace'."
        exit 1
    fi
    cp terraform.tfstate.d/default/terraform.tfstate "terraform.tfstate.d/$blue_workspace/terraform.tfstate"
    terraform workspace select default >/dev/null 2>&1
    # Empty the default state
    rm terraform.tfstate 2>/dev/null || true


    # Checkout new version
    echo "🔄 Switching to version $new_version..."
    if ! git checkout "$new_version" 2>/dev/null; then
        echo "❌ Version $new_version not found"
        # Rollback workspace rename
        safe_workspace_delete "$blue_workspace"
        exit 1
    fi
    
    # Create and deploy green environment in the 'default' workspace
    echo "🟢 Creating Green environment in 'default' workspace..."
    
    terraform init -upgrade > /dev/null 2>&1 || {
        echo "❌ Terraform init failed for Green environment"
        git checkout "$current_version" >/dev/null 2>&1
        safe_workspace_delete "$blue_workspace"
        exit 1
    }
    
    if ! TF_LOG=ERROR terraform apply -auto-approve; then
        echo "❌ Green deployment failed, cleaning up..."
        terraform destroy -auto-approve >/dev/null 2>&1 # Cleanup failed green deployment
        git checkout "$current_version" >/dev/null 2>&1
        # Restore blue workspace
        echo "🔄 Restoring Blue environment..."
        mv "terraform.tfstate.d/$blue_workspace/terraform.tfstate" "terraform.tfstate.d/default/terraform.tfstate"
        safe_workspace_delete "$blue_workspace"
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
        terraform destroy -auto-approve > /dev/null 2>&1
        git checkout "$current_version" >/dev/null 2>&1
        # Restore blue workspace
        mv "terraform.tfstate.d/$blue_workspace/terraform.tfstate" "terraform.tfstate.d/default/terraform.tfstate"
        safe_workspace_delete "$blue_workspace"
        exit 1
    fi
    
    echo ""
    echo "✅ Green environment deployed!"
    echo "New Master IP: $new_master_ip"
    echo "New Deployment ID: $new_deployment_id"
    
    # Health check on green environment
    echo "🏥 Health checking Green environment..."
    local health_check_retries=10
    local new_cluster_healthy=false
    
    for i in $(seq 1 $health_check_retries); do
        echo "Health check attempt $i/$health_check_retries..."
        
        local health_check_result=1 # Default to failure
        ssh -i ~/.ssh/"$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "ubuntu@$new_master_ip" "
            kubectl get nodes --no-headers 2>/dev/null | grep -q Ready &&
            kubectl get deployment caloguessr-deployment -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '^[1-9]' &&
            timeout 10 curl -s --connect-timeout 5 http://localhost:30001 >/dev/null 2>&1
        " 2>/dev/null && health_check_result=$?
        
        if [ $health_check_result -eq 0 ]; then
            new_cluster_healthy=true
            echo "✅ Green environment is healthy!"
            break
        fi
        
        echo "⏳ Green environment not ready yet, waiting 60 seconds..."
        sleep 60
    done
    
    if [ "$new_cluster_healthy" = false ]; then
        echo "❌ Green environment failed health check, rolling back..."
        terraform destroy -auto-approve > /dev/null 2>&1 # Destroy failed green
        git checkout "$current_version" >/dev/null 2>&1
        # Restore blue workspace
        mv "terraform.tfstate.d/$blue_workspace/terraform.tfstate" "terraform.tfstate.d/default/terraform.tfstate"
        safe_workspace_delete "$blue_workspace"
        echo "🔄 Rollback completed"
        exit 1
    fi
    
    # Green is healthy, so it is now the new production environment.
    # The 'default' workspace is already managing the green environment.
    echo "✅ Switch successful! The new Green environment is now live in the 'default' workspace."
    
    # Cleanup old Blue environment
    echo "🧹 Cleaning up old Blue environment (from workspace '$blue_workspace')..."
    
    # Switch to the blue workspace to destroy it
    if ! terraform workspace select "$blue_workspace" 2>/dev/null; then
        echo "⚠️ Warning: Could not switch to '$blue_workspace' to clean it up. Manual cleanup may be required."
    else
        if terraform destroy -auto-approve > /dev/null 2>&1; then
            echo "✅ Old Blue environment cleanup successful"
        else
            echo "⚠️ Warning: Blue environment cleanup had issues. Manual cleanup may be required."
        fi
        # Switch back to default and delete the now-empty blue workspace
        terraform workspace select default >/dev/null 2>&1
        safe_workspace_delete "$blue_workspace"
    fi
    
    echo ""
    echo "🎉 Zero-downtime deployment completed successfully!"
    echo "================================================="
    echo "Final Master IP: $new_master_ip"
    echo "App URL: $(terraform output -raw app_url 2>/dev/null)"
    echo "Ingress URL: $(terraform output -raw app_ingress_url 2>/dev/null)"
    echo "Version: $new_version"
    echo ""
    echo "🔍 Final status check:"
    check_app_status "$new_master_ip" "$ssh_key"
}

rollback_deployment() {
    local target_version=$1
    if [ -z "$target_version" ]; then
        echo "❌ Target version required for rollback"
        exit 1
    fi
    
    echo "🔄 Starting Rollback to version $target_version..."
    echo "================================================="
    
    # Sicherstellen, dass wir im default workspace sind
    terraform workspace select default >/dev/null 2>&1

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
    read -p "⚠️  This will DESTROY the current infrastructure and redeploy version $target_version. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "❌ Rollback cancelled"
        exit 1
    fi
    
    # Checkout target version first
    echo "🔄 Switching to version $target_version..."
    if ! git checkout "$target_version" 2>/dev/null; then
        echo "❌ Version $target_version not found"
        # Zurück zum ursprünglichen Git-Status, falls der Checkout fehlschlägt
        git checkout "$current_version" >/dev/null 2>&1
        exit 1
    fi

    # Destroy current infrastructure
    echo "🗑️  Destroying current infrastructure (from workspace 'default')..."
    if ! terraform destroy -auto-approve; then
        echo "⚠️  Warning: Infrastructure destruction may have failed. Continuing with deployment anyway."
    fi
    
    # Deploy target version
    echo "🚀 Deploying version $target_version..."
    deploy_version "$target_version"

    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "❌ Rollback deployment failed."
        # Versuch, zum vorherigen Git-Status zurückzukehren
        git checkout "$current_version" >/dev/null 2>&1
        exit $exit_code
    fi
    
    echo ""
    echo "🎉 Rollback to version $target_version completed!"
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
    *)
        show_help
        ;;
esac