#!/bin/bash
echo "🧹 Use the new version manager instead:"
echo "./version-manager.sh cleanup"
echo ""
echo "Or for direct cleanup:"
source openrc.sh
terraform destroy -auto-approve