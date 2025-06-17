terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
  }
}

provider "openstack" {}

# Security Group für K8s Cluster
resource "openstack_networking_secgroup_v2" "k8s_cluster" {
  name        = "k8s-cluster"
  description = "Security group for Kubernetes cluster"
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

# K8s Master Node
resource "openstack_compute_instance_v2" "k8s_master" {
  name            = "k8s-master"
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
  })
}

# K8s Worker Nodes
resource "openstack_compute_instance_v2" "k8s_workers" {
  count           = var.worker_count
  name            = "k8s-worker-${count.index + 1}"
  image_id        = var.image_id
  flavor_name     = var.flavor_name
  key_pair        = var.key_pair
  security_groups = ["default", openstack_networking_secgroup_v2.k8s_cluster.name]
  network {
    name = var.network_name
  }
  user_data = templatefile("cloud-init-worker.tpl", {
    master_ip = openstack_compute_instance_v2.k8s_master.access_ip_v4
  })
  depends_on = [openstack_compute_instance_v2.k8s_master]
}

# Outputs
output "master_ip" {
  value = openstack_compute_instance_v2.k8s_master.access_ip_v4
}

output "worker_ips" {
  value = openstack_compute_instance_v2.k8s_workers[*].access_ip_v4
}

output "ssh_master" {
  value = "ssh -i ~/.ssh/${var.key_pair} ubuntu@${openstack_compute_instance_v2.k8s_master.access_ip_v4}"
}

output "app_url" {
  value = "http://${openstack_compute_instance_v2.k8s_master.access_ip_v4}:30001"
}

output "cluster_info" {
  value = {
    master_ip = openstack_compute_instance_v2.k8s_master.access_ip_v4
    workers   = openstack_compute_instance_v2.k8s_workers[*].access_ip_v4
    app_url   = "http://${openstack_compute_instance_v2.k8s_master.access_ip_v4}:30001"
  }
}