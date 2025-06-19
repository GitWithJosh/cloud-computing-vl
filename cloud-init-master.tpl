#cloud-config
package_update: true
packages:
  - docker.io
  - git
  - curl

ssh_authorized_keys:
  - ${ssh_public_key}

write_files:
  - path: /root/app/caloguessr.py
    content: ${caloguessr_py}
    encoding: b64
  - path: /root/app/Dockerfile
    content: ${dockerfile}
    encoding: b64
  - path: /root/app/requirements.txt
    content: ${requirements_txt}
    encoding: b64
  - path: /root/app/k8s-deployment.yaml
    content: ${k8s_deployment}
    encoding: b64
  - path: /root/setup-ssh.sh
    content: |
      #!/bin/bash
      # Setup SSH for inter-node communication
      mkdir -p /home/ubuntu/.ssh
      cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys 2>/dev/null || true
      chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true
      
      # Generate SSH key for master to access workers if needed
      if [ ! -f /root/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 2048 -f /root/.ssh/id_rsa -N ""
        cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
      fi
      
      # Set proper permissions
      chmod 700 /root/.ssh
      chmod 600 /root/.ssh/id_rsa
      chmod 644 /root/.ssh/id_rsa.pub
      chown -R root:root /root/.ssh
    permissions: '0755'
  - path: /root/wait-for-k3s.sh
    content: |
      #!/bin/bash
      echo "Waiting for K3s to be fully ready..."
      
      # Wait for K3s service
      for i in {1..60}; do
        if systemctl is-active --quiet k3s; then
          echo "K3s service is active"
          break
        fi
        echo "Attempt $i/60 - K3s service not ready..."
        sleep 10
      done
      
      # Wait for kubectl to work
      for i in {1..30}; do
        if kubectl get nodes --no-headers 2>/dev/null | grep -q Ready; then
          echo "K3s API is ready"
          break
        fi
        echo "Attempt $i/30 - K3s API not ready..."
        sleep 10
      done
      
      # Wait for system pods
      for i in {1..30}; do
        if kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -q Running; then
          echo "System pods are running"
          return 0
        fi
        echo "Attempt $i/30 - System pods not ready..."
        sleep 10
      done
    permissions: '0755'
  - path: /root/deploy-app.sh
    content: |
      #!/bin/bash
      set -e
      echo "Building and deploying application..."
      cd /root/app
      
      # Check if already deployed
      if kubectl get deployment caloguessr-deployment 2>/dev/null; then
        echo "Application already deployed, skipping..."
        exit 0
      fi
      
      # Build Docker image only if it doesn't exist
      if ! docker images | grep -q "caloguessr-app.*latest"; then
        echo "Building Docker image..."
        docker build -t caloguessr-app:latest . || {
          echo "Docker build failed, retrying..."
          sleep 30
          docker build -t caloguessr-app:latest .
        }
        echo "Docker image built successfully"
        
        # Import to K3s
        docker save caloguessr-app:latest | /usr/local/bin/k3s ctr images import -
        echo "Image imported to K3s"
      else
        echo "Docker image already exists"
      fi
      
      # Deploy application
      kubectl apply -f k8s-deployment.yaml
      echo "Application deployed"
      
      # Wait for deployment to be ready
      echo "Waiting for deployment to be ready..."
      kubectl wait --for=condition=available deployment/caloguessr-deployment --timeout=600s || {
        echo "Deployment not ready, checking status..."
        kubectl get pods -l app=caloguessr
        kubectl describe pods -l app=caloguessr
      }
      
      # Show final status
      kubectl get pods -l app=caloguessr
      kubectl get svc caloguessr-service
    permissions: '0755'
  - path: /root/master-ready-signal.sh
    content: |
      #!/bin/bash
      # Signal that master is ready for workers
      echo "Master setup complete at $(date)" > /tmp/master-ready
      echo "Token: $(cat /var/lib/rancher/k3s/server/node-token)" >> /tmp/master-ready
      echo "API: https://$(hostname -I | awk '{print $1}'):6443" >> /tmp/master-ready
      chmod 644 /tmp/master-ready
      
      # Also create a simple HTTP endpoint for workers to check
      echo "K3s Master Ready" > /var/www/html/ready 2>/dev/null || echo "K3s Master Ready" > /tmp/ready
    permissions: '0755'

runcmd:
  # Docker Setup
  - systemctl start docker
  - systemctl enable docker
  - usermod -aG docker ubuntu
  
  # Setup SSH access
  - /root/setup-ssh.sh
  
  # Install K3s as master with proper configuration
  - echo "Installing K3s master..."
  - curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode=644 --node-external-ip=$(hostname -I | awk '{print $1}') --disable=traefik" sh -
  
  # Wait for K3s to be ready
  - /root/wait-for-k3s.sh
  
  # Setup kubectl for ubuntu user
  - mkdir -p /home/ubuntu/.kube
  - cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
  - chown ubuntu:ubuntu /home/ubuntu/.kube/config
  - sed -i 's/127.0.0.1/'"$(hostname -I | awk '{print $1}')"'/g' /home/ubuntu/.kube/config
  
  # Signal master is ready for worker connections
  - /root/master-ready-signal.sh
  
  # Deploy application (background to not block worker joining)
  - nohup /root/deploy-app.sh > /tmp/deploy.log 2>&1 &
  
  # Final status after some time
  - sleep 60
  - /usr/local/bin/kubectl get nodes
  - /usr/local/bin/kubectl get pods --all-namespaces