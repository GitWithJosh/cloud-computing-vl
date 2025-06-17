#!/bin/bash

source openrc.sh

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
    
    # Deploy
    terraform init
    terraform apply -auto-approve
    
    # Show results
    echo ""
    echo "✅ Deployment complete!"
    echo "Master IP: $(terraform output -raw master_ip)"
    echo "App URL: $(terraform output -raw app_url)"
    echo "SSH: $(terraform output -raw ssh_master)"
    echo ""
    echo "⏳ Waiting for cluster to be ready..."
    sleep 120  # Mehr Zeit für die App-Erstellung
    
    # Check cluster and deploy app if needed
    local master_ip=$(terraform output -raw master_ip)
    echo "📊 Cluster status:"
    
    # Mit korrekten SSH-Optionen
    ssh -i ~/.ssh/shooosh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$master_ip "
        echo '=== Nodes ==='
        kubectl get nodes
        echo
        echo '=== Pods ==='
        kubectl get pods -A
        echo
        echo '=== Checking if app is deployed ==='
        if ! kubectl get deployment caloguessr-deployment 2>/dev/null; then
            echo 'App not found, deploying now...'
            cd /root/app
            if [ -f k8s-deployment.yaml ]; then
                kubectl apply -f k8s-deployment.yaml
                echo 'Waiting for app to start...'
                sleep 30
                kubectl get pods
            else
                echo 'Deployment file not found!'
            fi
        fi
    " 2>/dev/null || echo "Cluster still starting..."
    
    # Final status check
    echo ""
    echo "🔍 Final status check..."
    sleep 30
    check_app_status $master_ip
}

check_app_status() {
    local master_ip=$1
    ssh -i ~/.ssh/shooosh -o StrictHostKeyChecking=no ubuntu@$master_ip "
        echo '=== Final App Status ==='
        kubectl get pods -l app=caloguessr
        echo
        echo '=== Services ==='
        kubectl get svc caloguessr-service
        echo
        echo '=== Testing app connectivity ==='
        if kubectl get pods -l app=caloguessr --no-headers | grep -q Running; then
            echo '✅ App pods are running'
            echo 'Testing app URL...'
            if curl -s -o /dev/null -w '%{http_code}' http://localhost:30001 | grep -q '200\|302'; then
                echo '✅ App is responding'
            else
                echo '⚠️  App not responding yet, may still be starting'
            fi
        else
            echo '❌ App pods not running'
            echo 'Checking pod logs:'
            kubectl logs -l app=caloguessr --tail=10 || echo 'No logs available'
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
        if [ -n "$master_ip" ]; then
            echo "✅ Infrastructure: Deployed"
            echo "Master IP: $master_ip"
            echo "App URL: $(terraform output -raw app_url)"
            echo ""
            
            if ssh -i ~/.ssh/shooosh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$master_ip "echo" 2>/dev/null; then
                echo "📊 Kubernetes Status:"
                ssh -i ~/.ssh/shooosh -o StrictHostKeyChecking=no ubuntu@$master_ip "
                    echo '=== Nodes ==='
                    kubectl get nodes
                    echo
                    echo '=== Pods ==='
                    kubectl get pods -o wide
                    echo
                    echo '=== Services ==='
                    kubectl get svc
                    echo
                    echo '=== App-specific Status ==='
                    echo 'Caloguessr Deployment:'
                    kubectl get deployment caloguessr-deployment 2>/dev/null || echo 'Not found'
                    echo 'Caloguessr Pods:'
                    kubectl get pods -l app=caloguessr 2>/dev/null || echo 'Not found'
                    echo
                    echo '=== HPA ==='
                    kubectl get hpa 2>/dev/null || echo 'HPA not available'
                " 2>/dev/null
            else
                echo "❌ Cannot connect to cluster"
            fi
        else
            echo "❌ No infrastructure deployed"
        fi
    else
        echo "❌ No terraform state found"
    fi
}

show_logs() {
    local master_ip=$(terraform output -raw master_ip 2>/dev/null)
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "📋 Application Logs"
    echo "==================="
    ssh -i ~/.ssh/shooosh -o StrictHostKeyChecking=no ubuntu@$master_ip "
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
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "🔍 Debug Information"
    echo "===================="
    
    ssh -i ~/.ssh/shooosh -o StrictHostKeyChecking=no ubuntu@$master_ip "
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
    if [ -z "$master_ip" ]; then
        echo "❌ No cluster deployed"
        exit 1
    fi
    
    echo "📈 Scaling to $replicas replicas..."
    ssh -i ~/.ssh/shooosh -o StrictHostKeyChecking=no ubuntu@$master_ip "kubectl scale deployment caloguessr-deployment --replicas=$replicas"
    
    echo "⏳ Waiting for scaling..."
    sleep 10
    
    ssh -i ~/.ssh/shooosh -o StrictHostKeyChecking=no ubuntu@$master_ip "kubectl get pods -l app=caloguessr"
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
    "cleanup")
        cleanup
        ;;
    *)
        show_help
        ;;
esac