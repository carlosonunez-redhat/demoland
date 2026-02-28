module "disconnected-sg-bastion-bridge" {
  source = "terraform-aws-modules/security-group/aws"
  name = "bastion-bridge-sg-disconnected"
  description = "Egress traffic rules for bridge NIC on connected bastion"
  vpc_id = module.disconnected_network.vpc_id
  egress_with_cidr_blocks = [{
    from_port = 22
    to_port = 22
    protocol = "tcp"
    description = "Allow SSH to disconnected bastion"
    cidr_blocks = "${module.disconnected-bastion-vm.private_ip}/32"
  }]
}

resource "aws_network_interface" "bastion-bridge" {
  subnet_id = module.disconnected_network.private_subnets[local.default_availability_zone_index]
  private_ips = [ local.bastion_bridge_ip ]
  security_groups = [ module.disconnected-sg-bastion-bridge.security_group_id ]
  attachment {
    instance = module.connected-bastion-vm.id
    device_index = 1
  }
}
