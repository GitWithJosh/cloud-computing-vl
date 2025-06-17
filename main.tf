terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
    }
  }
}

provider "openstack" {}

resource "openstack_compute_instance_v2" "k8s_instance" {
  name            = "k8s-node"
  image_id        = var.image_id
  flavor_name     = var.flavor_name
  key_pair        = var.key_pair
  security_groups = ["default"]
  network {
    name = var.network_name
  }
  user_data = templatefile("cloud-init.tpl", {
    caloguessr_py     = base64encode(file("app/caloguessr.py"))
    dockerfile        = base64encode(file("app/Dockerfile"))
    requirements_txt  = base64encode(file("app/requirements.txt"))
    k8s_deployment    = base64encode(file("app/k8s-deployment.yaml"))
  })
}

output "instance_ip" {
  value = openstack_compute_instance_v2.k8s_instance.access_ip_v4
}

output "instance_id" {
  value = openstack_compute_instance_v2.k8s_instance.id
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/${var.key_pair} ubuntu@${openstack_compute_instance_v2.k8s_instance.access_ip_v4}"
}