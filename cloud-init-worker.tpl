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
      
      # Additional wait for master to be fully ready
      for i in {1..30}; do
        if curl -s --connect-timeout 5 http://$MASTER_IP/ready 2>/dev/null || [ -f /tmp/master-ready-confirmed ]; then
          echo "Master signals ready"
          touch /tmp/master-ready-confirmed
          break
        fi
        echo "Attempt $i/30 - Waiting for master ready signal..."
        sleep 20
      done
    permissions: '0755'
  - path: /root/get-token.sh
    content: |
      #!/bin/bash
      MASTER_IP="${master_ip}"
      echo "Getting join token from master..."
      
      # Try multiple methods to get the token
      for i in {1..20}; do
        # Method 1: Direct SSH to ubuntu user, then sudo
        TOKEN=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null ubuntu@$MASTER_IP "sudo cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null)
        
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "" ]; then
          echo "Got token via ubuntu user: ${TOKEN:0:20}..."
          echo "$TOKEN" > /tmp/k3s-token
          return 0
        fi
        
        # Method 2: Try direct root access (if SSH keys are set up)
        TOKEN=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null root@$MASTER_IP "cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null)
        
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "" ]; then
          echo "Got token via root user: ${TOKEN:0:20}..."
          echo "$TOKEN" > /tmp/k3s-token
          return 0
        fi
        
        echo "Attempt $i/20 - Failed to get token, retrying in 15s..."
        sleep 15
      done
      
      echo "Failed to get token after all attempts"
      return 1
    permissions: '0755'
  - path: /root/join-cluster.sh
    content: |
      #!/bin/bash
      MASTER_IP="${master_ip}"
      
      if [ ! -f /tmp/k3s-token ]; then
        echo "No token file found"
        return 1
      fi
      
      TOKEN=$(cat /tmp/k3s-token)
      if [ -z "$TOKEN" ]; then
        echo "Empty token"
        return 1
      fi
      
      echo "Joining cluster with token: ${TOKEN:0:20}..."
      
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
      
      return 0
    permissions: '0755'
  - path: /root/get-app-image.sh
    content: |
      #!/bin/bash
      echo "Getting application image from master..."
      MASTER_IP="${master_ip}"
      
      # Wait for master to have the image and be accessible
      for i in {1..20}; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null ubuntu@$MASTER_IP "sudo docker images | grep -q caloguessr-app" 2>/dev/null; then
          echo "Master has the image, copying..."
          
          # Copy image from master
          if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$MASTER_IP "sudo docker save caloguessr-app:latest" | sudo docker load; then
            echo "Image copied successfully"
            
            # Import to K3s if K3s is running
            if command -v /usr/local/bin/k3s >/dev/null 2>&1; then
              sudo docker save caloguessr-app:latest | sudo /usr/local/bin/k3s ctr images import - || echo "K3s import failed"
            fi
            
            echo "Application image ready on worker"
            return 0
          else
            echo "Failed to copy image, retrying..."
          fi
        fi
        echo "Attempt $i/20 - waiting for master image ($(date))..."
        sleep 30
      done
      
      echo "Failed to get app image"
      return 1
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
  
  # Get application image (in background)
  - nohup /root/get-app-image.sh > /tmp/image-copy.log 2>&1 &
  
  # Final verification
  - sleep 30
  - systemctl status k3s-agent || echo "K3s agent status check failed"
  - sudo docker images | grep caloguessr || echo "App image not found yet"