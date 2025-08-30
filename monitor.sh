#!/bin/bash

source openrc.sh

# Function to get SSH key
get_ssh_key() {
    if [ -f terraform.tfstate ]; then
        SSH_KEY=$(terraform output -raw ssh_master 2>/dev/null | grep -o "\-i ~/.ssh/[^ ]*" | cut -d'/' -f4)
        if [ -n "$SSH_KEY" ]; then
            echo "$SSH_KEY"
        else
            SSH_KEY=$(grep "key_pair" terraform.tfvars 2>/dev/null | cut -d'"' -f2)
            echo "$SSH_KEY"
        fi
    else
        SSH_KEY=$(grep "key_pair" terraform.tfvars 2>/dev/null | cut -d'"' -f2)
        echo "$SSH_KEY"
    fi
}

MASTER_IP=$(terraform output -raw master_ip 2>/dev/null)
SSH_KEY=$(get_ssh_key)

if [ -z "$MASTER_IP" ]; then
    echo "❌ No cluster found. Deploy first with: ./version-manager.sh deploy v1.0"
    exit 1
fi

if [ -z "$SSH_KEY" ]; then
    echo "❌ Could not determine SSH key. Check terraform.tfvars"
    exit 1
fi

echo "🔍 Starting cluster monitoring..."
echo "Master IP: $MASTER_IP"
echo "SSH Key: $SSH_KEY"
echo "Press Ctrl+C to exit"
echo ""

while true; do
    clear
    echo "=== Kubernetes Cluster Monitor ==="
    echo "Time: $(date)"
    echo "Master: $MASTER_IP"
    echo "SSH Key: $SSH_KEY"
    echo ""
    
    if ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$MASTER_IP "echo" 2>/dev/null; then
        echo "📊 Nodes:"
        ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl get nodes" 2>/dev/null
        echo ""
        
        echo "🚀 All Pods:"
        ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl get pods -A -o wide" 2>/dev/null
        echo ""
        
        echo "📱 App Pods:"
        ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl get pods -l app=caloguessr -o wide" 2>/dev/null || echo "No app pods found"
        echo ""
        
        echo "🌐 Services:"
        ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl get svc" 2>/dev/null
        echo ""
        
        echo "📈 Resource Usage:"
        ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "kubectl top nodes 2>/dev/null || echo 'Metrics not available'"
        echo ""
        
        # Test app connectivity
        echo "🔗 App Status:"
        if ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "curl -s -o /dev/null -w '%{http_code}' http://localhost:30001" 2>/dev/null | grep -q "200\|302"; then
            echo "✅ App responding at: http://$MASTER_IP:30001"
        else
            echo "❌ App not responding at: http://$MASTER_IP:30001"
        fi
    else
        echo "❌ Cannot connect to cluster"
        echo "Check:"
        echo "- SSH key exists: ~/.ssh/$SSH_KEY"
        echo "- Security groups allow SSH"
        echo "- Instance is running"
    fi
    
    sleep 10
done