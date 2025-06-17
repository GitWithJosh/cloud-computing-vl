#cloud-config
package_update: true
packages:
  - docker.io
  - git
  - curl

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
  - path: /root/deploy-app.sh
    content: |
      #!/bin/bash
      set -e
      echo "Building and deploying application..."
      cd /root/app
      
      # Build Docker image
      docker build -t caloguessr-app:latest .
      echo "Docker image built successfully"
      
      # Import to K3s
      docker save caloguessr-app:latest | /usr/local/bin/k3s ctr images import -
      echo "Image imported to K3s"
      
      # Wait for K3s to be fully ready
      while ! kubectl get nodes | grep -q Ready; do
        echo "Waiting for K3s to be ready..."
        sleep 10
      done
      
      # Deploy application
      kubectl apply -f k8s-deployment.yaml
      echo "Application deployed"
      
      # Wait for pods to be ready
      echo "Waiting for pods to start..."
      kubectl wait --for=condition=ready pod -l app=caloguessr --timeout=300s || true
      
      # Show status
      kubectl get pods -l app=caloguessr
      kubectl get svc caloguessr-service
    permissions: '0755'

runcmd:
  # Docker Setup
  - systemctl start docker
  - systemctl enable docker
  - usermod -aG docker ubuntu
  
  # Install K3s as master
  - curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode=644 --node-external-ip=$(hostname -I | awk '{print $1}')" sh -
  - sleep 30
  
  # Setup kubectl for ubuntu user
  - mkdir -p /home/ubuntu/.kube
  - cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
  - chown ubuntu:ubuntu /home/ubuntu/.kube/config
  - sed -i 's/127.0.0.1/'"$(hostname -I | awk '{print $1}')"'/g' /home/ubuntu/.kube/config
  
  # Deploy application with retry mechanism
  - mkdir -p /root/app
  - sleep 30  # Wait for K3s to be fully ready
  - /root/deploy-app.sh || echo "Initial deployment failed, will retry"
  - sleep 30
  - /root/deploy-app.sh || echo "Second deployment attempt failed"
  
  # Final status
  - /usr/local/bin/kubectl get nodes
  - /usr/local/bin/kubectl get pods --all-namespaces
  - /usr/local/bin/kubectl get svc