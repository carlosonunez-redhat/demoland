module "connected_network" {
  source = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = "connected-network"
  cidr = local.options.cloud_config.aws.networking.connected.cidr
  azs = local.options.cloud_config.aws.networking.common.availability_zones
  public_subnets = local.options.cloud_config.aws.networking.connected.subnets.public
  private_subnets = local.options.cloud_config.aws.networking.connected.subnets.private
}

resource "aws_vpc_block_public_access_exclusion" "connected_network" {
  vpc_id = module.connected_network.vpc_id
  internet_gateway_exclusion_mode = "allow-bidirectional"
}

module "connected-sg-bastion" {
  source = "terraform-aws-modules/security-group/aws"
  name = "bastion-nodes-sg-connected"
  description = "SSH access into connected bastion network"
  vpc_id = module.connected_network.vpc_id
  ingress_with_cidr_blocks = [{
    from_port = 22
    to_port = 22
    protocol = "tcp"
    description = "SSH to bastion from [${var.ssh_ip}]"
    cidr_blocks = "${var.ssh_ip}/32"
  }]
  egress_with_cidr_blocks = [{
    from_port = 0
    to_port = 0
    protocol = -1
    description = "Allow all outbound"
    cidr_blocks = "0.0.0.0/0"
  }]
}
