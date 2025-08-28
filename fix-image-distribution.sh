#!/bin/bash

master_ip=$(terraform output -raw master_ip 2>/dev/null)

# Get SSH key name from terraform.tfvars
if [ -f terraform.tfvars ]; then
    ssh_key=$(grep "key_pair" terraform.tfvars | cut -d'"' -f2)
else
    echo "terraform.tfvars not found"
    exit 1
fi

if [ -z "$ssh_key" ]; then
    echo "Could not find key_pair in terraform.tfvars"
    exit 1
fi

echo "Using SSH key: $ssh_key"
echo "Connecting to: $master_ip"
echo "Fixing image distribution across all nodes..."

ssh -i ~/.ssh/$ssh_key -o StrictHostKeyChecking=no ubuntu@$master_ip "
    # First, save the image to a shared location
    docker save sensor-anomaly-processor:1.0.0 > /tmp/kafka-streams-image.tar
    
    # Create a pod that runs on each node to load the image
    kubectl delete job image-distributor -n kafka --ignore-not-found=true
    
    kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: image-distributor
  namespace: kafka
spec:
  parallelism: 3
  completions: 3
  template:
    spec:
      containers:
      - name: image-loader
        image: ubuntu:20.04
        command:
        - /bin/bash
        - -c
        - |
          apt-get update && apt-get install -y docker.io
          service docker start
          # Copy and load the image
          cp /shared/kafka-streams-image.tar /tmp/
          docker load -i /tmp/kafka-streams-image.tar
          echo 'Image loaded on node:' \$(hostname)
        volumeMounts:
        - name: docker-sock
          mountPath: /var/run/docker.sock
        - name: shared-storage
          mountPath: /shared
      volumes:
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
      - name: shared-storage
        hostPath:
          path: /tmp
      restartPolicy: Never
      nodeSelector:
        kubernetes.io/os: linux
EOF

    echo 'Waiting for image distribution...'
    kubectl wait --for=condition=complete job/image-distributor -n kafka --timeout=300s
    
    echo 'Image distribution completed. Cleaning up...'
    kubectl delete job image-distributor -n kafka
    rm /tmp/kafka-streams-image.tar
"