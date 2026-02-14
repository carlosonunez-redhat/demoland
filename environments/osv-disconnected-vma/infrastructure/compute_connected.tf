module "connected-bastion-vm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "bastion"
  ami = data.aws_ami.fedora_arm.id
  instance_type = "m8g.large"
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.connected_network.public_subnets[0]
  vpc_security_group_ids = [ module.connected-sg-bastion.security_group_id ]
  associate_public_ip_address = true
}
