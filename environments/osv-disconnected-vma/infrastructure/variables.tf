variable "ssh_ip" {
  description = "An IP that can SSH into the bastion"
}

variable "bare_metal_creation_sentinel_file" {
  description = "The path to a file that, when created, provisions bare-metal AWS instances"
}

variable "control_plane_cert_bundle" {}
variable "worker_cert_bundle" {}
