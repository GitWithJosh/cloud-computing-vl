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
  
  # Verify join
  - sleep 30
  - systemctl status k3s-agent || echo "K3s agent not running"