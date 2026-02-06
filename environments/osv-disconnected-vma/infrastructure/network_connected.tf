module "connected_network" {
  source = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = "connected-network"
  cidr = local.options.cloud_config.aws.networking.connected.cidr
  azs = local.options.cloud_config.aws.networking.common.availability_zones
  public_subnets = local.options.cloud_config.aws.networking.connected.subnets.public
  private_subnets = local.options.cloud_config.aws.networking.connected.subnets.private
  enable_nat_gateway = true
}

module "connected-sg-bastion" {
  source = "terraform-aws-modules/security-group/aws"
  name = "bastion-nodes-sg-connected"
  description = "OCP control plane and workers"
  vpc_id = module.connected-network.vpc_id
  ingress_with_self = [ for kv in local.allowed_ports.bastion_host : {
    from_port = 22
    to_port = 22
    protocol = tcp
    description = "SSH to bastion from '${var.ssh_ip}'"
    cidr_blocks = "${var.ssh_ip}/22"
  }]
}
