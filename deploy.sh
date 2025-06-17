#!/bin/bash
echo "🚀 Use the new version manager instead:"
echo "./version-manager.sh deploy v1.0"
echo ""
echo "Or for quick deployment:"
source openrc.sh
terraform init
terraform apply -auto-approve
echo ""
echo "✅ Deployment complete!"
echo "Master IP: $(terraform output -raw master_ip)"
echo "App URL: $(terraform output -raw app_url)"