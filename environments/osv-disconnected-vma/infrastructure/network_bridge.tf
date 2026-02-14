locals {
  bastion_bridge_ip = cidrhost(module.disconnected_network.private_subnets_cidr_blocks[0], 252)
}

module "disconnected-sg-bastion-bridge" {
  source = "terraform-aws-modules/security-group/aws"
  name = "bastion-sg-disconnected"
  description = "Security group for disconnected bastion host from the connected bastion"
  vpc_id = module.disconnected_network.vpc_id
  ingress_with_cidr_blocks = [
    {
      from_port = 22
      to_port = 22
      protocol = "tcp"
      cidr_blocks = "${local.bastion_bridge_ip}/32"
    }
  ]
}

resource "aws_network_interface" "bastion-bridge" {
  subnet_id = module.disconnected_network.private_subnets[0]
  private_ips = [ local.bastion_bridge_ip ]
  attachment {
    instance = module.connected-bastion-vm.id
    device_index = 1
  }
}
