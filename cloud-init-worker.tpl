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
      
      # Try to get token via HTTP service first (primary method)
      for i in {1..20}; do
        TOKEN=$(curl -s --connect-timeout 10 http://$MASTER_IP:8080/token 2>/dev/null)
        
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "" ] && [[ ! "$TOKEN" =~ "404" ]] && [[ ! "$TOKEN" =~ "error" ]]; then
          echo "Got token via HTTP service: $${TOKEN:0:20}..."
          echo "$TOKEN" > /tmp/k3s-token
          exit 0
        fi
        
        echo "HTTP attempt $i/20 failed, trying SSH fallback..."
        # Only try SSH as fallback when HTTP fails
        TOKEN=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null ubuntu@$MASTER_IP "sudo cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null)
        
        if [ -n "$TOKEN" ] && [ "$TOKEN" != "" ]; then
          echo "Got token via SSH: $${TOKEN:0:20}..."
          echo "$TOKEN" > /tmp/k3s-token
          exit 0
        fi
        
        echo "Both HTTP and SSH failed for attempt $i/20, retrying in 15s..."
        sleep 15
      done
      
      echo "Failed to get token after all attempts"
      exit 1
    permissions: '0755'
  - path: /root/join-cluster.sh
    content: |
      #!/bin/bash
      # Enhanced cluster joining with patient image download
      MASTER_IP="${master_ip}"
      MAX_RETRIES=60
      IMAGE_MAX_RETRIES=120  # 30 minutes for image build
      RETRY_COUNT=0
      
      echo "Starting cluster join process..." > /var/log/join-cluster.log
      
      # Wait for master to be ready
      while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if curl -s http://$MASTER_IP:8080/ready > /dev/null 2>&1; then
          echo "Master is ready" >> /var/log/join-cluster.log
          break
        fi
        sleep 10
        RETRY_COUNT=$((RETRY_COUNT + 1))
      done
      
      if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo "Failed to reach master after $MAX_RETRIES attempts" >> /var/log/join-cluster.log
        exit 1
      fi
      
      # Use token from get-token.sh or download it
      if [ -f /tmp/k3s-token ]; then
        TOKEN=$(cat /tmp/k3s-token)
        echo "Using token from get-token.sh" >> /var/log/join-cluster.log
      else
        echo "Token file not found, downloading directly..." >> /var/log/join-cluster.log
        TOKEN=$(curl -s http://$MASTER_IP:8080/token)
      fi
      
      if [ -z "$TOKEN" ]; then
        echo "Failed to get token" >> /var/log/join-cluster.log
        exit 1
      fi
      
      # Join cluster
      echo "Joining cluster..." >> /var/log/join-cluster.log
      curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN=$TOKEN sh -
      
      # Wait for Docker image with extended patience
      echo "Waiting for Docker image (this may take up to 30 minutes)..." >> /var/log/join-cluster.log
      RETRY_COUNT=0
      while [ $RETRY_COUNT -lt $IMAGE_MAX_RETRIES ]; do
        IMAGE_STATUS=$(curl -s http://$MASTER_IP:8080/image-status 2>/dev/null || echo "unreachable")
        
        case "$IMAGE_STATUS" in
          "ready")
            echo "Docker image is ready for download" >> /var/log/join-cluster.log
            break
            ;;
          "building")
            echo "Docker image is still building... (attempt $((RETRY_COUNT + 1))/$IMAGE_MAX_RETRIES)" >> /var/log/join-cluster.log
            ;;
          "failed")
            echo "Docker image build failed on master" >> /var/log/join-cluster.log
            exit 1
            ;;
          "pending")
            echo "Docker image build not yet started... (attempt $((RETRY_COUNT + 1))/$IMAGE_MAX_RETRIES)" >> /var/log/join-cluster.log
            ;;
          *)
            echo "Cannot reach master or unknown status: $IMAGE_STATUS (attempt $((RETRY_COUNT + 1))/$IMAGE_MAX_RETRIES)" >> /var/log/join-cluster.log
            ;;
        esac
        
        sleep 15
        RETRY_COUNT=$((RETRY_COUNT + 1))
      done
      
      # Download and import Docker image
      if [ "$IMAGE_STATUS" = "ready" ]; then
        echo "Downloading Docker image..." >> /var/log/join-cluster.log
        
        # Verbesserte Download-Strategie mit erhöhter Zuverlässigkeit
        MAX_DOWNLOAD_ATTEMPTS=5
        for i in $(seq 1 $MAX_DOWNLOAD_ATTEMPTS); do
          echo "Download-Versuch $i von $MAX_DOWNLOAD_ATTEMPTS..." >> /var/log/join-cluster.log
          
          if curl -s --connect-timeout 30 --max-time 300 http://$MASTER_IP:8080/caloguessr-app.tar -o /tmp/caloguessr-app.tar; then
            # Überprüfe Dateigröße (mindestens 10 MB erwartet)
            SIZE=$(stat -c %s /tmp/caloguessr-app.tar 2>/dev/null || stat -f %z /tmp/caloguessr-app.tar)
            if [ "$SIZE" -gt 10000000 ]; then
              echo "Download erfolgreich (Größe: $SIZE bytes)" >> /var/log/join-cluster.log
              break
            else
              echo "Heruntergeladene Datei zu klein ($SIZE bytes), versuche erneut" >> /var/log/join-cluster.log
              rm -f /tmp/caloguessr-app.tar
            fi
          else
            echo "Download-Versuch $i fehlgeschlagen" >> /var/log/join-cluster.log
          fi
          
          # Exponentielles Backoff für Wiederholungsversuche
          sleep $((5 * i))
        done
        
        if [ -f /tmp/caloguessr-app.tar ] && [ -s /tmp/caloguessr-app.tar ]; then
          echo "Loading Docker image..." >> /var/log/join-cluster.log
          
          # Erst in Docker laden
          if docker load -i /tmp/caloguessr-app.tar; then
            echo "Docker image loaded successfully" >> /var/log/join-cluster.log
            
            # Dann in K3s containerd importieren (mehrere Versuche)
            for i in {1..3}; do
              echo "Import-Versuch $i in k3s containerd..." >> /var/log/join-cluster.log
              if docker save caloguessr-app:latest | /usr/local/bin/k3s ctr images import -; then
                echo "Docker image successfully imported to K3s (Versuch $i)" >> /var/log/join-cluster.log
                break
              else
                echo "Failed to import image to K3s (Versuch $i)" >> /var/log/join-cluster.log
                sleep 10
              fi
            done
            
            # Verifizieren, dass das Image tatsächlich importiert wurde
            if /usr/local/bin/k3s ctr images list | grep -q caloguessr-app; then
              echo "Image erfolgreich in k3s containerd verifiziert" >> /var/log/join-cluster.log
            else
              echo "WARNUNG: Image scheint nicht in k3s containerd vorhanden zu sein!" >> /var/log/join-cluster.log
            fi
          else
            echo "Failed to load Docker image" >> /var/log/join-cluster.log
          fi
          
          # Backup-Kopie für Fehlerbehebung aufbewahren
          mv /tmp/caloguessr-app.tar /var/lib/caloguessr-app.tar.backup
        else
          echo "Downloaded image file is empty or missing" >> /var/log/join-cluster.log
        fi
      else
        echo "Timeout waiting for Docker image (waited 30 minutes)" >> /var/log/join-cluster.log
      fi
      
      echo "Worker setup completed at $(date)" >> /var/log/join-cluster.log
    permissions: '0755'

runcmd:
  # Docker Setup
  - systemctl start docker
  - systemctl enable docker
  - usermod -aG docker ubuntu
  
  # Wait for master to be ready
  - /root/wait-for-master.sh
  
  # Get join token (creates /tmp/k3s-token)
  - /root/get-token.sh
  
  # Join cluster (uses existing token or downloads if needed)
  - /root/join-cluster.sh
  
  # Final verification
  - sleep 30
  - systemctl status k3s-agent || echo "K3s agent status check failed"
  - echo "Worker setup completed"