terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

provider "openstack" {
  # Suppress loadbalancer warnings for this project
}

# Read SSH public key
data "local_file" "ssh_public_key" {
  filename = pathexpand("~/.ssh/${var.key_pair}.pub")
}

# Random ID for unique resource naming (always created)
resource "random_id" "deployment" {
  byte_length = 4
  
  # Ensure this is unique for each deployment
  keepers = {
    timestamp = timestamp()
  }
}

# Local values for unique naming
locals {
  # Always use random ID for deployment ID (workspace-independent)
  deployment_id = random_id.deployment.hex
  
  # Ensure unique naming across environments
  name_prefix = "k8s-${local.deployment_id}"
}

# Security Group für K8s Cluster
resource "openstack_networking_secgroup_v2" "k8s_cluster" {
  name        = "${local.name_prefix}-cluster"
  description = "Security group for Kubernetes cluster (${local.deployment_id})"
}

resource "openstack_networking_secgroup_rule_v2" "k8s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_cluster.id
}

resource "openstack_networking_secgroup_rule_v2" "nodeport" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_cluster.id
}

resource "openstack_networking_secgroup_rule_v2" "cluster_internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_group_id   = openstack_networking_secgroup_v2.k8s_cluster.id
  security_group_id = openstack_networking_secgroup_v2.k8s_cluster.id
}

# Security Groups für Monitoring
resource "openstack_networking_secgroup_rule_v2" "grafana" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30300
  port_range_max    = 30300
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_cluster.id
}

resource "openstack_networking_secgroup_rule_v2" "prometheus" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30090
  port_range_max    = 30090
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_cluster.id
}

# Security Group für Traefik Ingress Controller
resource "openstack_networking_secgroup_rule_v2" "ingress_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_cluster.id
}

resource "openstack_networking_secgroup_rule_v2" "ingress_https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_cluster.id
}

# K8s Master Node
resource "openstack_compute_instance_v2" "k8s_master" {
  name            = "${local.name_prefix}-master"
  image_id        = var.image_id
  flavor_name     = var.flavor_name
  key_pair        = var.key_pair
  security_groups = ["default", openstack_networking_secgroup_v2.k8s_cluster.name]
  network {
    name = var.network_name
  }
  user_data = templatefile("cloud-init-master.tpl", {
    caloguessr_py     = base64encode(file("app/caloguessr.py"))
    dockerfile        = base64encode(file("app/Dockerfile"))
    requirements_txt  = base64encode(file("app/requirements.txt"))
    k8s_deployment    = base64encode(file("app/k8s-deployment.yaml"))
    ssh_public_key    = trimspace(data.local_file.ssh_public_key.content)
  })
}

# K8s Worker Nodes
resource "openstack_compute_instance_v2" "k8s_workers" {
  count           = var.worker_count
  name            = "${local.name_prefix}-worker-${count.index + 1}"
  image_id        = var.image_id
  flavor_name     = var.flavor_name
  key_pair        = var.key_pair
  security_groups = ["default", openstack_networking_secgroup_v2.k8s_cluster.name]
  network {
    name = var.network_name
  }
  user_data = templatefile("cloud-init-worker.tpl", {
    master_ip      = openstack_compute_instance_v2.k8s_master.access_ip_v4
    ssh_public_key = trimspace(data.local_file.ssh_public_key.content)
  })
  depends_on = [openstack_compute_instance_v2.k8s_master]
}

# Outputs
output "deployment_id" {
  description = "Unique deployment identifier"
  value       = local.deployment_id
}

output "master_ip" {
  description = "IP address of the K8s master node"
  value       = openstack_compute_instance_v2.k8s_master.access_ip_v4
}

output "worker_ips" {
  description = "IP addresses of the K8s worker nodes"
  value       = openstack_compute_instance_v2.k8s_workers[*].access_ip_v4
}

output "app_url" {
  description = "URL to access the Caloguessr application"
  value       = "http://${openstack_compute_instance_v2.k8s_master.access_ip_v4}:30001"
}

output "app_ingress_url" {
  description = "Ingress URL to access the Caloguessr application"
  value       = "http://${openstack_compute_instance_v2.k8s_master.access_ip_v4}"
}

output "ssh_master" {
  description = "SSH command to connect to master"
  value       = "ssh -i ~/.ssh/${var.key_pair} ubuntu@${openstack_compute_instance_v2.k8s_master.access_ip_v4}"
}

output "cluster_info" {
  description = "Cluster information"
  value = {
    master_ip   = openstack_compute_instance_v2.k8s_master.access_ip_v4
    worker_ips  = openstack_compute_instance_v2.k8s_workers[*].access_ip_v4
    app_url     = "http://${openstack_compute_instance_v2.k8s_master.access_ip_v4}:30001"
    ssh_key     = var.key_pair
  }
}

output "monitoring_urls" {
  description = "Monitoring service URLs"
  value = {
    grafana    = "http://${openstack_compute_instance_v2.k8s_master.access_ip_v4}:30300"
    prometheus = "http://${openstack_compute_instance_v2.k8s_master.access_ip_v4}:30090"
  }
}