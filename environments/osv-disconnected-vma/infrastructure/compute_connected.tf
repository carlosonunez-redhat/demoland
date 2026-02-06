module "connected-bastion-vm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "bastion"
  instance_type = "m8g.large"
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.connected_network.public_subnets[0]
  vpc_security_group_ids = [ module.connected-sg-bastion.security_group_id ]
  associate_public_ip_address = true
}

resource "aws_network_interface" "bastion-bridge" {
  subnet_id = module.disconnected_network.private_subnets[0]
  private_ips = [cidrhost( module.disconnected_network.private_subnets[0], 254 )]
  attachment {
    instance = module.connected-bastion-vm.id
    device_index = 1
  }
}
