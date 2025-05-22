#!/bin/bash

# Deploy Calorie Guesser to OpenStack using Pulumi
# Usage: ./deploy.sh [v1|v2] [key_pair_name]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default version
VERSION=${1:-v1}
KEY_PAIR=${2}

echo -e "${GREEN}Deploying Calorie Guesser ${VERSION} to OpenStack...${NC}"

# Validate version
if [[ "$VERSION" != "v1" && "$VERSION" != "v2" ]]; then
    echo -e "${RED}Error: Version must be 'v1' or 'v2'${NC}"
    echo "Usage: $0 [v1|v2] [key_pair_name]"
    exit 1
fi

# Check if key pair is provided
if [[ -z "$KEY_PAIR" ]]; then
    echo -e "${YELLOW}No key pair specified. Please enter your SSH key pair name:${NC}"
    read -p "Key pair name: " KEY_PAIR
    if [[ -z "$KEY_PAIR" ]]; then
        echo -e "${RED}Error: Key pair name is required${NC}"
        exit 1
    fi
fi

# Check if required files exist
SCRIPT_FILE="calo_guessr_${VERSION}.py"
if [[ ! -f "$SCRIPT_FILE" ]]; then
    echo -e "${RED}Error: $SCRIPT_FILE not found in current directory${NC}"
    echo -e "${YELLOW}Make sure you're running this script from the directory containing your Python files${NC}"
    exit 1
fi

if [[ ! -f "requirements.txt" ]]; then
    echo -e "${YELLOW}Warning: requirements.txt not found - will deploy without Python dependencies${NC}"
    echo -e "${YELLOW}This may cause runtime errors if your application has dependencies${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Show file info
echo -e "${BLUE}Files to deploy:${NC}"
echo -e "  📄 Python script: ${YELLOW}$SCRIPT_FILE${NC} ($(wc -l < "$SCRIPT_FILE" 2>/dev/null || echo "?") lines)"
if [[ -f "requirements.txt" ]]; then
    echo -e "  📦 Requirements: ${YELLOW}requirements.txt${NC} ($(wc -l < "requirements.txt") packages)"
fi

# Check if openrc.sh exists and source it
if [[ -f "openrc.sh" ]]; then
    echo -e "${YELLOW}Loading OpenStack credentials from openrc.sh...${NC}"
    source openrc.sh
    echo -e "${GREEN}OpenStack credentials loaded${NC}"
else
    echo -e "${YELLOW}Warning: openrc.sh not found. Make sure OpenStack environment variables are set.${NC}"
fi

# Install Pulumi dependencies
echo -e "${YELLOW}Installing Pulumi dependencies...${NC}"
pip install -r requirements-pulumi.txt

# Set up Pulumi stack
STACK_NAME="calo-guessr-${VERSION}"
echo -e "${YELLOW}Setting up Pulumi stack: ${STACK_NAME}${NC}"

# Initialize stack if it doesn't exist
if ! pulumi stack select $STACK_NAME 2>/dev/null; then
    echo -e "${YELLOW}Creating new stack: ${STACK_NAME}${NC}"
    pulumi stack init $STACK_NAME
fi

# Set configuration
echo -e "${YELLOW}Configuring deployment for version ${VERSION} with key pair ${KEY_PAIR}...${NC}"
pulumi config set version $VERSION
pulumi config set key_pair $KEY_PAIR

# Deploy
echo -e "${YELLOW}Starting deployment...${NC}"
pulumi up --yes

# Show outputs
echo -e "${GREEN}Deployment completed!${NC}"
echo -e "${YELLOW}Getting deployment information...${NC}"
pulumi stack output

echo ""
echo -e "${BLUE}=== STREAMLIT APPLICATION ACCESS ===${NC}"
PRIVATE_IP=$(pulumi stack output private_ip --show-secrets 2>/dev/null || echo "")
if [[ ! -z "$PRIVATE_IP" ]]; then
    echo -e "${GREEN}🌐 Streamlit Web Interface:${NC}"
    echo -e "${YELLOW}   http://${PRIVATE_IP}:8501${NC}"
fi

echo ""
echo -e "${BLUE}=== POST-DEPLOYMENT INSTRUCTIONS ===${NC}"
echo -e "${GREEN}1. SSH to your instance:${NC}"
pulumi stack output ssh_command

echo ""
echo -e "${GREEN}2. Check deployment status:${NC}"
PRIVATE_IP=$(pulumi stack output private_ip --show-secrets 2>/dev/null || echo "")
if [[ ! -z "$PRIVATE_IP" ]]; then
    echo -e "${YELLOW}   ssh -i {path-to-private-ssh-key} ubuntu@${PRIVATE_IP} 'sudo tail -f /var/log/calo-guessr-setup.log'${NC}"
fi

echo ""
echo -e "${GREEN}3. Monitor application logs:${NC}"
if [[ ! -z "$PRIVATE_IP" ]]; then
    echo -e "${YELLOW}   ssh -i {path-to-private-ssh-key} ubuntu@${PRIVATE_IP} 'sudo journalctl -u calo-guessr -f'${NC}"
fi

echo ""
echo -e "${GREEN}4. Quick status check:${NC}"
if [[ ! -z "$PRIVATE_IP" ]]; then
    echo -e "${YELLOW}   ssh -i {path-to-private-ssh-key} ubuntu@${PRIVATE_IP} '/opt/calo-guessr/check_status.sh'${NC}"
fi

echo ""
echo -e "${BLUE}=== LOG FILES ON INSTANCE ===${NC}"
echo -e "${YELLOW}   Setup log: /var/log/calo-guessr-setup.log${NC}"
echo -e "${YELLOW}   App log: /var/log/calo-guessr-app.log${NC}"
echo -e "${YELLOW}   Deployment info: /opt/calo-guessr/deployment-info.txt${NC}"

echo ""
echo -e "${GREEN}Deployment script completed successfully!${NC}"
echo -e "${BLUE}Wait a few minutes for the application to be fully ready.${NC}"