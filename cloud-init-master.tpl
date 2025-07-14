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
  - path: /root/monitoring/setup-monitoring.sh
    content: |
      #!/bin/bash
      
      echo "Setting up monitoring stack..." > /var/log/monitoring-setup.log
      
      # Wait for K3s to be ready
      while ! kubectl get nodes > /dev/null 2>&1; do
        echo "Waiting for K3s..." >> /var/log/monitoring-setup.log
        sleep 10
      done
      
      # Create monitoring namespace
      kubectl create namespace monitoring || true
      
      # Create RBAC for Prometheus
      kubectl apply -f - <<EOF
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRole
      metadata:
        name: prometheus
      rules:
      - apiGroups: [""]
        resources:
        - nodes
        - nodes/proxy
        - nodes/metrics
        - services
        - endpoints
        - pods
        - ingresses
        verbs: ["get", "list", "watch"]
      - apiGroups: ["extensions"]
        resources:
        - ingresses
        verbs: ["get", "list", "watch"]
      - apiGroups: ["apps"]
        resources:
        - deployments
        - replicasets
        - daemonsets
        - statefulsets
        verbs: ["get", "list", "watch"]
      - apiGroups: ["autoscaling"]
        resources:
        - horizontalpodautoscalers
        verbs: ["get", "list", "watch"]
      - nonResourceURLs: ["/metrics"]
        verbs: ["get"]
      ---
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: prometheus
        namespace: monitoring
      ---
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      metadata:
        name: prometheus
      roleRef:
        apiGroup: rbac.authorization.k8s.io
        kind: ClusterRole
        name: prometheus
      subjects:
      - kind: ServiceAccount
        name: prometheus
        namespace: monitoring
      EOF
      
      # Deploy Prometheus with fixed configuration
      kubectl apply -f - <<EOF
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: prometheus-config
        namespace: monitoring
      data:
        prometheus.yml: |
          global:
            scrape_interval: 15s
            evaluation_interval: 15s
          scrape_configs:
          - job_name: 'kubernetes-apiservers'
            kubernetes_sd_configs:
            - role: endpoints
              namespaces:
                names:
                - default
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            relabel_configs:
            - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
              action: keep
              regex: default;kubernetes;https
          
          - job_name: 'kubernetes-nodes'
            kubernetes_sd_configs:
            - role: node
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              insecure_skip_verify: true
            bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            relabel_configs:
            - action: labelmap
              regex: __meta_kubernetes_node_label_(.+)
            - target_label: __address__
              replacement: kubernetes.default.svc:443
            - source_labels: [__meta_kubernetes_node_name]
              regex: (.+)
              target_label: __metrics_path__
              replacement: /api/v1/nodes/\$1/proxy/metrics
          
          - job_name: 'kubernetes-cadvisor'
            kubernetes_sd_configs:
            - role: node
            scheme: https
            tls_config:
              ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              insecure_skip_verify: true
            bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
            relabel_configs:
            - action: labelmap
              regex: __meta_kubernetes_node_label_(.+)
            - target_label: __address__
              replacement: kubernetes.default.svc:443
            - source_labels: [__meta_kubernetes_node_name]
              regex: (.+)
              target_label: __metrics_path__
              replacement: /api/v1/nodes/\$1/proxy/metrics/cadvisor
          
          - job_name: 'kube-state-metrics'
            static_configs:
            - targets: ['kube-state-metrics:8080']
          
          - job_name: 'kubernetes-pods'
            kubernetes_sd_configs:
            - role: pod
            relabel_configs:
            - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
              action: keep
              regex: true
            - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
              action: replace
              target_label: __metrics_path__
              regex: (.+)
            - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
              action: replace
              regex: ([^:]+)(?::\d+)?;(\d+)
              replacement: \$1:\$2
              target_label: __address__
            - action: labelmap
              regex: __meta_kubernetes_pod_label_(.+)
            - source_labels: [__meta_kubernetes_namespace]
              action: replace
              target_label: kubernetes_namespace
            - source_labels: [__meta_kubernetes_pod_name]
              action: replace
              target_label: kubernetes_pod_name
      ---
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: prometheus
        namespace: monitoring
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: prometheus
        template:
          metadata:
            labels:
              app: prometheus
          spec:
            serviceAccountName: prometheus
            containers:
            - name: prometheus
              image: prom/prometheus:latest
              ports:
              - containerPort: 9090
              volumeMounts:
              - name: config
                mountPath: /etc/prometheus
              - name: storage
                mountPath: /prometheus
              args:
                - '--config.file=/etc/prometheus/prometheus.yml'
                - '--storage.tsdb.path=/prometheus'
                - '--web.console.libraries=/etc/prometheus/console_libraries'
                - '--web.console.templates=/etc/prometheus/consoles'
                - '--web.enable-lifecycle'
                - '--web.enable-admin-api'
            volumes:
            - name: config
              configMap:
                name: prometheus-config
            - name: storage
              emptyDir: {}
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: prometheus
        namespace: monitoring
      spec:
        selector:
          app: prometheus
        ports:
        - port: 9090
          targetPort: 9090
          nodePort: 30090
        type: NodePort
      EOF
      
      # Deploy kube-state-metrics FIRST (wichtig für Metriken)
      kubectl apply -f - <<EOF
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: kube-state-metrics
        namespace: monitoring
      ---
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRole
      metadata:
        name: kube-state-metrics
      rules:
      - apiGroups: [""]
        resources: ["configmaps", "secrets", "nodes", "pods", "services", "resourcequotas", "replicationcontrollers", "limitranges", "persistentvolumeclaims", "persistentvolumes", "namespaces", "endpoints"]
        verbs: ["list", "watch"]
      - apiGroups: ["apps"]
        resources: ["statefulsets", "daemonsets", "deployments", "replicasets"]
        verbs: ["list", "watch"]
      - apiGroups: ["batch"]
        resources: ["cronjobs", "jobs"]
        verbs: ["list", "watch"]
      - apiGroups: ["autoscaling"]
        resources: ["horizontalpodautoscalers"]
        verbs: ["list", "watch"]
      - apiGroups: ["authentication.k8s.io"]
        resources: ["tokenreviews"]
        verbs: ["create"]
      - apiGroups: ["authorization.k8s.io"]
        resources: ["subjectaccessreviews"]
        verbs: ["create"]
      - apiGroups: ["policy"]
        resources: ["poddisruptionbudgets"]
        verbs: ["list", "watch"]
      - apiGroups: ["certificates.k8s.io"]
        resources: ["certificatesigningrequests"]
        verbs: ["list", "watch"]
      - apiGroups: ["storage.k8s.io"]
        resources: ["storageclasses", "volumeattachments"]
        verbs: ["list", "watch"]
      - apiGroups: ["admissionregistration.k8s.io"]
        resources: ["mutatingwebhookconfigurations", "validatingwebhookconfigurations"]
        verbs: ["list", "watch"]
      - apiGroups: ["networking.k8s.io"]
        resources: ["networkpolicies", "ingresses"]
        verbs: ["list", "watch"]
      - apiGroups: ["coordination.k8s.io"]
        resources: ["leases"]
        verbs: ["list", "watch"]
      ---
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      metadata:
        name: kube-state-metrics
      roleRef:
        apiGroup: rbac.authorization.k8s.io
        kind: ClusterRole
        name: kube-state-metrics
      subjects:
      - kind: ServiceAccount
        name: kube-state-metrics
        namespace: monitoring
      ---
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: kube-state-metrics
        namespace: monitoring
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: kube-state-metrics
        template:
          metadata:
            labels:
              app: kube-state-metrics
          spec:
            serviceAccountName: kube-state-metrics
            containers:
            - name: kube-state-metrics
              image: k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.8.0
              ports:
              - containerPort: 8080
                name: http-metrics
              - containerPort: 8081
                name: telemetry
              livenessProbe:
                httpGet:
                  path: /healthz
                  port: 8080
                initialDelaySeconds: 5
                timeoutSeconds: 5
              readinessProbe:
                httpGet:
                  path: /
                  port: 8081
                initialDelaySeconds: 5
                timeoutSeconds: 5
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: kube-state-metrics
        namespace: monitoring
        labels:
          app: kube-state-metrics
      spec:
        selector:
          app: kube-state-metrics
        ports:
        - name: http-metrics
          port: 8080
          targetPort: http-metrics
        - name: telemetry
          port: 8081
          targetPort: telemetry
      EOF
      
      # Deploy Grafana
      kubectl apply -f - <<EOF
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: grafana
        namespace: monitoring
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: grafana
        template:
          metadata:
            labels:
              app: grafana
          spec:
            containers:
            - name: grafana
              image: grafana/grafana:latest
              ports:
              - containerPort: 3000
              env:
              - name: GF_SECURITY_ADMIN_PASSWORD
                value: "admin"
              - name: GF_SECURITY_ADMIN_USER
                value: "admin"
              volumeMounts:
              - name: grafana-storage
                mountPath: /var/lib/grafana
            volumes:
            - name: grafana-storage
              emptyDir: {}
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: grafana
        namespace: monitoring
      spec:
        selector:
          app: grafana
        ports:
        - port: 3000
          targetPort: 3000
          nodePort: 30300
        type: NodePort
      EOF
      
      # Wait for all pods to be ready
      echo "Waiting for monitoring pods to be ready..." >> /var/log/monitoring-setup.log
      kubectl wait --for=condition=ready pod -l app=kube-state-metrics -n monitoring --timeout=300s
      kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
      kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s
      
      # Configure Grafana data source
      sleep 30
      kubectl exec -n monitoring deployment/grafana -- /bin/bash -c "
        curl -X POST http://admin:admin@localhost:3000/api/datasources \
        -H 'Content-Type: application/json' \
        -d '{
          \"name\": \"Prometheus\",
          \"type\": \"prometheus\",
          \"url\": \"http://prometheus:9090\",
          \"access\": \"proxy\",
          \"isDefault\": true
        }'
      " 2>/dev/null || echo "Data source configuration completed"
      
      echo "Monitoring stack setup completed" >> /var/log/monitoring-setup.log
    permissions: '0755'
  - path: /root/deploy-app.sh
    content: |
      #!/bin/bash
      # Deploy app in background and exit quickly
      (
        sleep 30
        cd /root/app
        
        # Signal that build process has started
        echo "building" > /tmp/web/image-status
        echo "Docker build started at $(date)" > /tmp/app-deploy.log
        
        docker build -t caloguessr-app:latest . 2>/dev/null
        
        if [ $? -eq 0 ]; then
          echo "Docker build completed, saving image..." >> /tmp/app-deploy.log
          
          # Save image to tar file for distribution
          docker save caloguessr-app:latest -o /tmp/web/caloguessr-app.tar
          
          # Warten bis k3s vollständig initialisiert ist
          echo "Warte auf vollständige k3s Initialisierung vor dem Import..." >> /tmp/app-deploy.log
          sleep 30
          
          # Import to local K3s containerd (WICHTIG: Für Master-Node Scheduling)
          # Mit verbessertem Import und Fehlerbehandlung
          echo "Importiere Image in k3s containerd..." >> /tmp/app-deploy.log
          if docker save caloguessr-app:latest | /usr/local/bin/k3s ctr images import -; then
            echo "Image erfolgreich in k3s containerd importiert" >> /tmp/app-deploy.log
          else
            echo "Fehler beim Import des Images in k3s containerd, versuche es erneut..." >> /tmp/app-deploy.log
            # Zweiter Versuch nach kurzer Wartezeit
            sleep 15
            docker save caloguessr-app:latest | /usr/local/bin/k3s ctr images import -
          fi
          
          # Prüfen, ob das Image wirklich importiert wurde
          if /usr/local/bin/k3s ctr images list | grep -q caloguessr-app; then
            echo "Image erfolgreich in k3s containerd verifiziert" >> /tmp/app-deploy.log
          else
            echo "WARNUNG: Image scheint nicht in k3s containerd vorhanden zu sein!" >> /tmp/app-deploy.log
          fi
          
          # Zusätzlich: Image auch für Docker verfügbar halten (falls Master als Worker verwendet wird)
          echo "Image imported to K3s containerd on master" >> /tmp/app-deploy.log
          
          # Warten bis K3s bereit ist für Deployments
          while ! kubectl get nodes > /dev/null 2>&1; do
            echo "Waiting for K3s to be ready for deployments..." >> /tmp/app-deploy.log
            sleep 5
          done
          
          # Deploy app
          kubectl apply -f k8s-deployment.yaml 2>/dev/null
          
          # Signal that image is ready for download
          echo "ready" > /tmp/web/image-status
          echo "App deployment completed at $(date)" >> /tmp/app-deploy.log
        else
          echo "failed" > /tmp/web/image-status
          echo "Docker build failed at $(date)" >> /tmp/app-deploy.log
        fi
      ) &
    permissions: '0755'
  - path: /root/share-token.sh
    content: |
      #!/bin/bash
      # Enhanced token and image sharing setup
      while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
        sleep 5
      done
      mkdir -p /tmp/web
      cp /var/lib/rancher/k3s/server/node-token /tmp/web/token
      echo "K3s Master Ready" > /tmp/web/ready
      
      # Initialize image status as pending
      echo "pending" > /tmp/web/image-status
      
      # Start web server for token and image distribution
      cd /tmp/web
      python3 -m http.server 8080 >/dev/null 2>&1 &
      
      # Log the sharing service
      echo "Token and image sharing service started on port 8080" > /var/log/sharing-service.log
    permissions: '0755'
  - path: /root/auto-assign-worker-roles.sh
    content: |
      #!/bin/bash
      # Auto-assign worker roles for new nodes
      
      echo "Starting auto role assignment service..." > /var/log/role-assignment.log
      
      # Wait for K3s to be ready
      while ! kubectl get nodes > /dev/null 2>&1; do
        sleep 10
      done
      
      # Continuous monitoring for new nodes
      while true; do
        # Get all nodes that don't have the master role and aren't labeled as workers yet
        NODES=$(kubectl get nodes --no-headers | grep -v "control-plane\|master" | awk '{print $1}')
        
        for NODE in $NODES; do
          # Check if node already has worker role
          if ! kubectl get node $NODE -o jsonpath='{.metadata.labels}' | grep -q "node-role.kubernetes.io/worker"; then
            echo "$(date): Assigning worker role to $NODE" >> /var/log/role-assignment.log
            kubectl label node $NODE node-role.kubernetes.io/worker= --overwrite
            
            if [ $? -eq 0 ]; then
              echo "$(date): Successfully assigned worker role to $NODE" >> /var/log/role-assignment.log
            else
              echo "$(date): Failed to assign worker role to $NODE" >> /var/log/role-assignment.log
            fi
          fi
        done
        
        # Check every 15 seconds
        sleep 15
      done
    permissions: '0755'

runcmd:
  # Docker Setup
  - systemctl start docker
  - systemctl enable docker
  
  # Install K3s master with Traefik enabled for Ingress
  - curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode=644" sh -
  
  # Quick wait for K3s
  - sleep 30
  
  # Remove master taint to allow pods to be scheduled on master (für ImagePullBackOff-Fix)
  - /usr/local/bin/kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- || true
  - /usr/local/bin/kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- || true
  
  # Setup kubectl for ubuntu user
  - mkdir -p /home/ubuntu/.kube
  - cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
  - chown ubuntu:ubuntu /home/ubuntu/.kube/config
  
  # Share token with workers
  - /root/share-token.sh
  
  # Setup monitoring stack
  - /root/monitoring/setup-monitoring.sh
  
  # Deploy app in background
  - /root/deploy-app.sh
  
  # Start auto role assignment service
  - nohup /root/auto-assign-worker-roles.sh > /dev/null 2>&1 &
  
  # Zusätzliche Image-Verifizierung - prüft und behebt das ImagePullBackOff Problem
  - |
    (
      # Warten auf initiale App-Deployment
      sleep 120
      echo "Führe Image-Verifizierung für Master-Node durch..." >> /var/log/image-verification.log
      
      # Überprüfen, ob das Image im containerd vorhanden ist
      if ! /usr/local/bin/k3s ctr images list | grep -q caloguessr-app; then
        echo "Image nicht in containerd gefunden, versuche Import..." >> /var/log/image-verification.log
        
        if [ -f /tmp/web/caloguessr-app.tar ]; then
          echo "Importiere aus lokaler tar-Datei..." >> /var/log/image-verification.log
          /usr/local/bin/k3s ctr images import /tmp/web/caloguessr-app.tar
        else
          echo "Exportiere aus Docker und importiere in containerd..." >> /var/log/image-verification.log
          docker save caloguessr-app:latest | /usr/local/bin/k3s ctr images import -
        fi
      else
        echo "Image bereits in containerd vorhanden" >> /var/log/image-verification.log
      fi
      
      # Überprüfe, ob Pods mit ImagePullBackOff vorhanden sind
      FAILING_PODS=$(/usr/local/bin/kubectl get pods -l app=caloguessr -o json | jq '.items[] | select(.status.phase != "Running" or .status.containerStatuses[0].ready != true) | .metadata.name' -r)
      
      if [ ! -z "$FAILING_PODS" ]; then
        echo "Gefundene Pods mit Problemen: $FAILING_PODS" >> /var/log/image-verification.log
        echo "Lösche problematische Pods für Neuerstellung..." >> /var/log/image-verification.log
        
        for POD in $FAILING_PODS; do
          /usr/local/bin/kubectl delete pod $POD
          echo "Pod $POD gelöscht" >> /var/log/image-verification.log
        done
      fi
    ) &
  
  # Signal completion
  - echo "Master setup completed at $(date)" > /tmp/setup-complete.log