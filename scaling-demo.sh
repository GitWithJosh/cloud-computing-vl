#!/bin/bash

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🎯 Scaling Demo mit Grafana Dashboard${NC}"
echo "======================================"

# Terraform Outputs laden
MASTER_IP=$(terraform output -raw master_ip 2>/dev/null)
SSH_KEY=$(grep "key_pair" terraform.tfvars | cut -d'"' -f2)

if [ -z "$MASTER_IP" ]; then
    echo -e "${RED}❌ Fehler: Kann Master IP nicht ermitteln${NC}"
    exit 1
fi

echo -e "${GREEN}📍 Master IP: $MASTER_IP${NC}"
echo -e "${GREEN}🔑 SSH Key: $SSH_KEY${NC}"
echo

# Dashboard importieren falls noch nicht geschehen
echo -e "${BLUE}📊 Setting up Grafana Dashboard...${NC}"
./version-manager.sh import-dashboard

echo -e "${GREEN}📍 Grafana Dashboard: http://$MASTER_IP:30300${NC}"
echo -e "${GREEN}📊 Navigate to 'Caloguessr Scaling Demo Dashboard'${NC}"
echo

# Browser öffnen (auf macOS)
if command -v open >/dev/null 2>&1; then
    echo -e "${BLUE}🌐 Opening Grafana Dashboard...${NC}"
    open "http://$MASTER_IP:30300"
fi

read -p "Press Enter when you have the dashboard open and ready..."

# Funktionen definieren
check_monitoring_status() {
    echo -e "${BLUE}📊 Monitoring Stack Status...${NC}"
    ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
        "echo '=== Monitoring Pods ==='
        kubectl get pods -n monitoring
        echo
        echo '=== Prometheus Targets ==='
        curl -s http://localhost:30090/api/v1/targets | jq -r '.data.activeTargets[] | select(.health != \"up\") | .scrapeUrl + \" - \" + .health' 2>/dev/null || echo 'Prometheus not accessible'
        echo
        echo '=== Kube-state-metrics ==='
        kubectl get pods -n monitoring -l app=kube-state-metrics"
}

check_cluster_status() {
    echo -e "${BLUE}📊 Cluster Status Check...${NC}"
    ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
        "kubectl get nodes && echo && kubectl get pods -o wide && echo && kubectl top pods --containers 2>/dev/null || echo 'Metrics not available yet'"
}

install_metrics_server() {
    echo -e "${BLUE}📊 Checking Metrics Server...${NC}"
    ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
        "if ! kubectl get pods -n kube-system | grep -q metrics-server; then
            echo 'Installing Metrics Server...'
            kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
            kubectl patch deployment metrics-server -n kube-system --type='merge' -p='{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"metrics-server\",\"args\":[\"--cert-dir=/tmp\",\"--secure-port=4443\",\"--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname\",\"--kubelet-use-node-status-port\",\"--metric-resolution=15s\",\"--kubelet-insecure-tls\"]}]}}}}'
            echo 'Waiting for metrics server...'
            sleep 60
        fi"
}

generate_intensive_load() {
    local duration=$1
    local concurrent=$2
    
    echo -e "${YELLOW}⚡ Generiere intensive Load für ${duration}s mit ${concurrent} parallelen Requests...${NC}"
    echo -e "${YELLOW}   Dies sollte definitiv über 3 Pods skalieren!${NC}"
    echo -e "${BLUE}📊 Monitoring URLs:${NC}"
    echo -e "${GREEN}Grafana: http://$MASTER_IP:30300${NC}"
    echo -e "${GREEN}Prometheus: http://$MASTER_IP:30090${NC}"
    echo -e "${GREEN}App (Ingress): http://$MASTER_IP${NC}"
    echo -e "${GREEN}App (NodePort): http://$MASTER_IP:30001${NC}"
    echo
    
    # Intensive Load Generator auf Master starten
    ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
        "nohup bash -c '
        for i in \$(seq 1 $concurrent); do
            (
                end_time=\$((SECONDS + $duration))
                while [ \$SECONDS -lt \$end_time ]; do
                    # Mehr CPU-intensive Requests
                    curl -s -m 2 http://localhost:30001 > /dev/null 2>&1 || true
                    curl -s -m 2 http://localhost:30001 > /dev/null 2>&1 || true
                    curl -s -m 2 http://localhost:30001 > /dev/null 2>&1 || true
                    curl -s -m 2 http://localhost:30001 > /dev/null 2>&1 || true
                    curl -s -m 2 http://localhost:30001 > /dev/null 2>&1 || true
                    # Kurze Pause für CPU-Spikes
                    sleep 0.001
                done
            ) &
        done
        wait
        echo \"Intensive load generation completed\"
        ' > /tmp/intensive-load-test.log 2>&1 &"
}

monitor_scaling() {
    echo -e "${BLUE}👀 Monitoring HPA Scaling (drücke Ctrl+C zum Beenden)...${NC}"
    echo -e "${YELLOW}   Grafana Dashboard: http://$MASTER_IP:30300${NC}"
    echo -e "${YELLOW}   App (Ingress): http://$MASTER_IP${NC}"
    echo -e "${YELLOW}   App (NodePort): http://$MASTER_IP:30001${NC}"
    echo
    
    while true; do
        ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
            "echo '=== $(date '+%Y-%m-%d %H:%M:%S') ===' 
            echo 'Nodes:'
            kubectl get nodes
            echo 
            echo 'HPA Status:'
            kubectl get hpa
            echo 
            echo 'Pods:'
            kubectl get pods -o wide | grep caloguessr
            echo
            echo 'Pod Resource Usage:'
            kubectl top pods --containers 2>/dev/null | grep caloguessr || echo 'Metrics still loading...'
            echo
            echo 'Monitoring Stack:'
            kubectl get pods -n monitoring | grep -E 'prometheus|grafana|kube-state'
            echo '---'"
        sleep 15
    done
}

# Hauptdemonstration
echo -e "${BLUE}1️⃣  Monitoring Stack Status${NC}"
check_monitoring_status

echo
echo -e "${BLUE}2️⃣  Initial Cluster Status${NC}"
check_cluster_status

echo
echo -e "${BLUE}3️⃣  Installing/Checking Metrics Server${NC}"
install_metrics_server

echo
echo -e "${BLUE}4️⃣  Load Test konfigurieren${NC}"
read -p "Load Test Dauer in Sekunden (default: 600): " DURATION
read -p "Anzahl parallele Requests (default: 100): " CONCURRENT

DURATION=${DURATION:-600}
CONCURRENT=${CONCURRENT:-100}

echo
echo -e "${BLUE}5️⃣  Starte intensive Load Generation${NC}"
generate_intensive_load $DURATION $CONCURRENT

echo
echo -e "${BLUE}6️⃣  Monitoring der Skalierung${NC}"

# Monitoring starten
monitor_scaling