#!/bin/bash

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Kubernetes Scaling Demonstration${NC}"
echo "===================================="

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

# Funktionen definieren
check_cluster_status() {
    echo -e "${BLUE}📊 Cluster Status Check...${NC}"
    ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
        "kubectl get nodes && echo && kubectl get pods -o wide && echo && kubectl top pods --containers 2>/dev/null || echo 'Metrics not available yet'"
}

generate_load() {
    local duration=$1
    local concurrent=$2
    
    echo -e "${YELLOW}⚡ Generiere Load für ${duration}s mit ${concurrent} parallelen Requests...${NC}"
    
    # Load Generator auf Master starten
    ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
        "nohup bash -c '
        for i in \$(seq 1 $concurrent); do
            (
                end_time=\$((SECONDS + $duration))
                while [ \$SECONDS -lt \$end_time ]; do
                    curl -s http://localhost:30001 > /dev/null 2>&1 || true
                    sleep 0.1
                done
            ) &
        done
        wait
        echo \"Load generation completed\"
        ' > /tmp/load-test.log 2>&1 &"
}

monitor_scaling() {
    echo -e "${BLUE}👀 Monitoring HPA Scaling (drücke Ctrl+C zum Beenden)...${NC}"
    
    while true; do
        ssh -i ~/.ssh/$SSH_KEY -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
            "echo '=== $(date '+%Y-%m-%d %H:%M:%S') ===' && kubectl get hpa && echo && kubectl get pods | grep caloguessr && echo '---'"
        sleep 10
    done
}

# Hauptdemonstration
echo -e "${BLUE}1️⃣  Initial Cluster Status${NC}"
check_cluster_status

echo
echo -e "${BLUE}2️⃣  Load Test konfigurieren${NC}"
read -p "Load Test Dauer in Sekunden (default: 300): " DURATION
read -p "Anzahl parallele Requests (default: 50): " CONCURRENT

DURATION=${DURATION:-300}
CONCURRENT=${CONCURRENT:-50}

echo
echo -e "${BLUE}4️⃣  Starte Load Generation${NC}"
generate_load $DURATION $CONCURRENT

echo
echo -e "${BLUE}5️⃣  Monitoring der Skalierung${NC}"
echo -e "${YELLOW}   App URL: http://$MASTER_IP:30001${NC}"
echo -e "${YELLOW}   Grafana: http://$MASTER_IP:3000${NC}"
echo

# Monitoring starten
monitor_scaling