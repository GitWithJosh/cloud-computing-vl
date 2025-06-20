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
  - path: /root/deploy-app.sh
    content: |
      #!/bin/bash
      # Deploy app in background and exit quickly
      (
        sleep 30
        cd /root/app
        docker build -t caloguessr-app:latest . 2>/dev/null
        docker save caloguessr-app:latest | /usr/local/bin/k3s ctr images import - 2>/dev/null
        kubectl apply -f k8s-deployment.yaml 2>/dev/null
        echo "App deployment initiated" > /tmp/app-deploy.log
      ) &
    permissions: '0755'
  - path: /root/share-token.sh
    content: |
      #!/bin/bash
      # Quick token sharing setup
      while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
        sleep 5
      done
      mkdir -p /tmp/web
      cp /var/lib/rancher/k3s/server/node-token /tmp/web/token
      echo "K3s Master Ready" > /tmp/web/ready
      cd /tmp/web
      python3 -m http.server 8080 >/dev/null 2>&1 &
    permissions: '0755'

runcmd:
  # Docker Setup
  - systemctl start docker
  - systemctl enable docker
  
  # Install K3s master
  - curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode=644 --disable=traefik" sh -
  
  # Quick wait for K3s
  - sleep 30
  
  # Setup kubectl for ubuntu user
  - mkdir -p /home/ubuntu/.kube
  - cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
  - chown ubuntu:ubuntu /home/ubuntu/.kube/config
  
  # Share token with workers
  - /root/share-token.sh
  
  # Deploy app in background
  - /root/deploy-app.sh
  
  # Signal completion
  - echo "Master setup completed at $(date)" > /tmp/setup-complete.log