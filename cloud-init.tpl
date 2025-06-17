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

runcmd:
  - curl -sfL https://get.k3s.io | sh -
  - systemctl start docker
  - systemctl enable docker
  - mkdir -p /root/app
  - cd /root/app && docker build -t caloguessr-app:latest .
  - sleep 30
  - docker save caloguessr-app:latest | /usr/local/bin/k3s ctr images import -
  - /usr/local/bin/kubectl apply -f /root/app/k8s-deployment.yaml
  - /usr/local/bin/kubectl get pods --all-namespaces