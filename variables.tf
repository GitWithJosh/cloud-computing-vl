variable "image_id" {
  description = "OpenStack image ID for Ubuntu"
  type        = string
}

variable "flavor_name" {
  description = "OpenStack flavor for instances"
  type        = string
}

variable "network_name" {
  description = "OpenStack network name"
  type        = string
}

variable "key_pair" {
  description = "OpenStack key pair name"
  type        = string
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}