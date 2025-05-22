# Provider configuration for OpenStack
terraform {
    required_providers {
        local = {
        source  = "hashicorp/local"
        }
        openstack = {
            source  = "terraform-provider-openstack/openstack"
        }
    }
}

provider "openstack" {
    # Authentication details
    auth_url    = ""
    user_name   = ""
    password    = ""
    tenant_name = ""
}

# Define variables
variable "instance_name" {
  description = "Name of the instance"
  default     = "python-app-server"
}

variable "image_id" {
  description = "ID of the image to use for the instance"
  default = "c57c2aef-f74a-4418-94ca-d3fb169162bf"
  # You'll need to specify the appropriate image ID from your OpenStack environment
}

variable "flavor_name" {
  description = "Instance type/flavor to use"
  default     = "cb1.mdeium"  # Adjust based on available flavors in your OpenStack
}

variable "key_pair" {
  description = "SSH key pair name"
  # You'll need to specify your key pair name
}

variable "network_name" {
  description = "Name of the network to use"
  # Specify your OpenStack network name
}

variable "security_groups" {
  description = "List of security groups to apply"
  type        = list(string)
  default     = ["default"]
}

variable "app_version" {
  description = "Version tag for the application"
  default     = "v1.0.0"
}

# Create instance
resource "openstack_compute_instance_v2" "app_server" {
  name            = "${var.instance_name}-${var.app_version}"
  image_id        = var.image_id
  flavor_name     = var.flavor_name
  key_pair        = var.key_pair
  security_groups = var.security_groups

  network {
    name = var.network_name
  }

  # User data script to set up the instance
  user_data = templatefile("${path.module}/scripts/setup.sh", {
    app_version = var.app_version
  })

  # Metadata to track application version
  metadata = {
    app_version = var.app_version
  }
}

# Output the instance IP address
output "instance_ip" {
  value = openstack_compute_instance_v2.app_server.access_ip_v4
}