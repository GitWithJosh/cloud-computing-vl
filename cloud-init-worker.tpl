#cloud-config
package_update: true
packages:
  - docker.io
  - curl

ssh_authorized_keys:
  - ${ssh_public_key}

write_files:
  - path: /root/wait-for-master.sh
    content: |
      #!/bin/bash
      MASTER_IP="${master_ip}"
      echo "Waiting for master to be ready at $MASTER_IP..."
      
      # Wait for master to be pingable
      for i in {1..60}; do
        if ping -c 1 -W 3 $MASTER_IP > /dev/null 2>&1; then
          echo "Master is pingable"
          break
        fi
        echo "Attempt $i/60 - Master not pingable..."
        sleep 10
      done
      
      # Wait for K3s API to be available  
      for i in {1..60}; do
        if curl -k --connect-timeout 5 --max-time 10 https://$MASTER_IP:6443/ping 2>/dev/null | grep -q pong; then
          echo "Master K3s API is ready"
          break
        fi
        echo "Attempt $i/60 - Master API not ready..."
        sleep 10
      done
      
      # Wait for token sharing service
      for i in {1..30}; do
        if curl -s --connect-timeout 5 http://$MASTER_IP:8080/ready 2>/dev/null | grep -q "K3s Master Ready"; then
          echo "Master token service ready"
          break
        fi
        echo "Attempt $i/30 - Waiting for master token service..."
        sleep 20
      done
    permissions: '0755'
  - path: /root/get-token.sh
    content: |
      #!/bin/bash
      MASTER_IP="${master_ip}"
      echo "Getting join token from master..."
      
      # Try to get token via HTTP service
      for i in {1..20}; do
        TOKEN=$(curl -s --connect-timeout 10 http://$MASTER_IP:8080/token 2>/dev/null)
        
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "" ] && [[ ! "$TOKEN" =~ "404" ]] && [[ ! "$TOKEN" =~ "error" ]]; then
          echo "Got token via HTTP service: $${TOKEN:0:20}..."
          echo "$TOKEN" > /tmp/k3s-token
          exit 0
        fi
        
        # Fallback: Try SSH to ubuntu user
        TOKEN=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null ubuntu@$MASTER_IP "sudo cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null)
        
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "" ]; then
          echo "Got token via SSH to ubuntu user: $${TOKEN:0:20}..."
          echo "$TOKEN" > /tmp/k3s-token
          exit 0
        fi
        
        echo "Attempt $i/20 - Failed to get token, retrying in 15s..."
        sleep 15
      done
      
      echo "Failed to get token after all attempts"
      exit 1
    permissions: '0755'
  - path: /root/join-cluster.sh
    content: |
      #!/bin/bash
      MASTER_IP="${master_ip}"
      
      if [ ! -f /tmp/k3s-token ]; then
        echo "No token file found"
        exit 1
      fi
      
      TOKEN=$(cat /tmp/k3s-token)
      if [ -z "$TOKEN" ]; then
        echo "Empty token"
        exit 1
      fi
      
      echo "Joining cluster with token: $${TOKEN:0:20}..."
      
      # Install K3s agent
      curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN=$TOKEN sh -
      
      # Wait for agent to be ready
      for i in {1..30}; do
        if systemctl is-active --quiet k3s-agent; then
          echo "K3s agent is active"
          break
        fi
        echo "Attempt $i/30 - K3s agent not ready..."
        sleep 10
      done
      
      echo "Worker joined cluster successfully"
      exit 0
    permissions: '0755'

runcmd:
  # Docker Setup
  - systemctl start docker
  - systemctl enable docker
  - usermod -aG docker ubuntu
  
  # Wait for master to be ready
  - /root/wait-for-master.sh
  
  # Get join token
  - /root/get-token.sh
  
  # Join cluster
  - /root/join-cluster.sh
  
  # Final verification
  - sleep 30
  - systemctl status k3s-agent || echo "K3s agent status check failed"
  - echo "Worker setup completed"