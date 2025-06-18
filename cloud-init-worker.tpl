#cloud-config
package_update: true
packages:
  - docker.io
  - curl

write_files:
  - path: /root/get-app-image.sh
    content: |
      #!/bin/bash
      echo "Getting application image from master..."
      MASTER_IP="${master_ip}"
      
      # Wait for master to have the image
      for i in {1..10}; do
        if ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "sudo docker images | grep -q caloguessr-app" 2>/dev/null; then
          echo "Master has the image, copying..."
          break
        fi
        echo "Attempt $i/10 - waiting for master to build image..."
        sleep 30
      done
      
      # Copy image from master
      ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "sudo docker save caloguessr-app:latest" | sudo docker load
      
      # Import to K3s
      sudo docker save caloguessr-app:latest | sudo /usr/local/bin/k3s ctr images import -
      
      echo "Application image ready on worker"
    permissions: '0755'

runcmd:
  # Docker Setup
  - systemctl start docker
  - systemctl enable docker
  - usermod -aG docker ubuntu
  
  # Wait for master to be ready
  - sleep 120
  - MASTER_IP="${master_ip}"
  
  # Wait for K3s API to be available
  - echo "Waiting for master K3s API at $MASTER_IP:6443..."
  - for i in {1..30}; do
  -   if curl -k --connect-timeout 5 https://$MASTER_IP:6443/ping 2>/dev/null; then
  -     echo "Master API is ready"
  -     break
  -   fi
  -   echo "Attempt $i/30 - API not ready yet, waiting..."
  -   sleep 10
  - done
  
  # Get join token from master
  - echo "Getting join token from master..."
  - for i in {1..10}; do
  -   TOKEN=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$MASTER_IP "sudo cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null)
  -   if [ ! -z "$TOKEN" ]; then
  -     echo "Got token successfully"
  -     break
  -   fi
  -   echo "Attempt $i/10 - failed to get token, retrying..."
  -   sleep 15
  - done
  
  # Join cluster if token was obtained
  - if [ ! -z "$TOKEN" ]; then
  -   echo "Joining cluster with token..."
  -   curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN=$TOKEN sh -
  -   echo "Successfully joined cluster"
  - else
  -   echo "Failed to get token, manual join required"
  - fi
  
  # Get application image
  - sleep 60  # Wait for worker to be fully joined
  - /root/get-app-image.sh || echo "Failed to get app image"
  
  # Verify join and image
  - sleep 30
  - systemctl status k3s-agent || echo "K3s agent not running"
  - sudo docker images | grep caloguessr || echo "App image not found"