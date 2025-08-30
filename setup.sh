#!/bin/bash

echo "🔧 Kubernetes Cluster Setup Script"
echo "=================================="
echo ""

# Check if running in correct directory
if [ ! -f "main.tf" ]; then
    echo "❌ Error: main.tf not found"
    echo "Please run this script from the cloud-project directory"
    exit 1
fi

echo "📋 Setting up configuration files..."

# Setup openrc.sh
if [ ! -f "openrc.sh" ]; then
    if [ -f "openrc.sh.template" ]; then
        cp openrc.sh.template openrc.sh
        echo "✅ Created openrc.sh from template"
        echo "📝 Please edit openrc.sh with your OpenStack credentials"
        echo "   You can get these from your OpenStack dashboard > API Access"
    else
        echo "❌ openrc.sh.template not found"
        exit 1
    fi
else
    echo "✅ openrc.sh already exists"
fi

# Setup terraform.tfvars
if [ ! -f "terraform.tfvars" ]; then
    if [ -f "terraform.tfvars.template" ]; then
        cp terraform.tfvars.template terraform.tfvars
        echo "✅ Created terraform.tfvars from template"
        echo "📝 Please edit terraform.tfvars with your OpenStack settings"
    else
        echo "❌ terraform.tfvars.template not found"
        exit 1
    fi
else
    echo "✅ terraform.tfvars already exists"
fi

# Make scripts executable
echo "🔧 Making scripts executable..."
chmod +x *.sh
echo "✅ Scripts are now executable"

# Initialize git if needed
if [ ! -d ".git" ]; then
    echo "📦 Initializing git repository..."
    git init
    git add .
    git commit -m "Initial commit: Multi-node Kubernetes cluster setup"
    git tag v1.0
    echo "✅ Git repository initialized with v1.0"
else
    echo "✅ Git repository already initialized"
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Edit openrc.sh with your OpenStack credentials:"
echo "   - Get these from OpenStack Dashboard > API Access"
echo "   - Download the RC file or copy the values manually"
echo ""
echo "2. Edit terraform.tfvars with your OpenStack settings:"
echo "   - Image ID: Compute > Images (find Ubuntu 24.04)"
echo "   - Flavor: Admin > Flavors (choose cb1.medium or similar)"
echo "   - Network: Network > Networks (your project network)"
echo "   - Key Pair: Compute > Key Pairs (your SSH key name)"
echo ""
echo "3. Source your credentials and deploy:"
echo "   source openrc.sh"
echo "   ./version-manager.sh deploy v1.0"
echo ""
echo "🔍 Need help finding your OpenStack settings?"
echo "   Run: ./help.sh"