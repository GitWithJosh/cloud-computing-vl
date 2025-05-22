#!/bin/bash
set -e

# Function to display usage information
usage() {
  echo "Usage: $0 [deploy|destroy|list] [version]"
  echo "  deploy  [version]  - Deploy a new version of the application"
  echo "  destroy [version]  - Destroy an existing version of the application"
  echo "  list              - List all deployed versions"
  exit 1
}

# Function to deploy a specific version
deploy() {
  VERSION=$1
  if [ -z "$VERSION" ]; then
    echo "Error: Version is required"
    usage
  fi
  
  echo "Deploying version $VERSION..."
  
  # Update terraform.tfvars with the new version
  sed -i '' "s/app_version.*=.*/app_version   = \"$VERSION\"/" terraform.tfvars
  
  # Initialize Terraform if not already done
  terraform init
  
  # Create a plan
  terraform plan -out=tfplan
  
  # Apply the plan
  terraform apply tfplan
  
  # Get the IP address from Terraform output
  INSTANCE_IP=$(terraform output -raw instance_ip)
  
  # Save the state file with version information
  mkdir -p versions
  cp terraform.tfstate versions/terraform.tfstate.$VERSION
  
  echo "Application version $VERSION deployed successfully!"
  echo "You can access the application at: http://$INSTANCE_IP:8080"
}

# Function to destroy a specific version
destroy() {
  VERSION=$1
  if [ -z "$VERSION" ]; then
    echo "Error: Version is required"
    usage
  fi
  
  echo "Destroying version $VERSION..."
  
  # Update terraform.tfvars with the version to destroy
  sed -i '' "s/app_version.*=.*/app_version   = \"$VERSION\"/" terraform.tfvars
  
  # Check if we have a state file for this version
  if [ -f "versions/terraform.tfstate.$VERSION" ]; then
    cp "versions/terraform.tfstate.$VERSION" terraform.tfstate
  else
    echo "Warning: No saved state found for version $VERSION"
  fi
  
  # Destroy the infrastructure
  terraform destroy -auto-approve
  
  echo "Application version $VERSION destroyed successfully!"
}

# Function to list all deployed versions
list() {
  echo "Deployed versions:"
  if [ -d "versions" ] && [ "$(ls -A versions 2>/dev/null)" ]; then
    find versions -name "terraform.tfstate.*" | sed 's/versions\/terraform.tfstate\./  - /'
  else
    echo "  No deployed versions found."
  fi
}

# Main script logic
COMMAND=$1
VERSION=$2

case "$COMMAND" in
  deploy)
    deploy "$VERSION"
    ;;
  destroy)
    destroy "$VERSION"
    ;;
  list)
    list
    ;;
  *)
    usage
    ;;
esac