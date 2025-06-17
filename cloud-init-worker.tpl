#cloud-config
package_update: true
packages:
  - docker.io
  - curl

runcmd:
  # Docker Setup
  - systemctl start docker
  - systemctl enable docker
  - usermod -aG docker ubuntu
  
  # Wait for master to be ready and join cluster
  - sleep 90
  - MASTER_IP="${master_ip}"
  - for i in {1..20}; do
  -   if curl -k https://$MASTER_IP:6443/ping 2>/dev/null; then break; fi
  -   sleep 10
  - done
  - TOKEN=$(curl -sfk https://$MASTER_IP:6443/cacerts 2>/dev/null && ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP "sudo cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null || echo "")
  - if [ ! -z "$TOKEN" ]; then curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN=$TOKEN sh -; fi