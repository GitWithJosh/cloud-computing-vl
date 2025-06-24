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
    echo "  deploy <version>    - Deploy specific version"
    echo "  rollback <version>  - Rollback to version"
    echo "  create <version>    - Create new version tag"
    echo "  list               - List all versions"
    echo "  status             - Show cluster status"
    echo "  scale <replicas>   - Scale application"
    echo "  cleanup            - Destroy infrastructure"
    echo "  logs               - Show application logs"
    echo "  debug              - Debug cluster issues"
    echo ""
    echo "Examples:"
    echo "  $0 deploy v1.0"
    echo "  $0 create v1.1"
    echo "  $0 scale 5"
    echo "  $0 status"
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
            echo "App URL: $(terraform output -raw app_url)"
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

# Command handling
case $1 in
    "deploy")
        deploy_version $2
        ;;
    "create")
        create_version $2
        ;;
    "rollback")
        deploy_version $2
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