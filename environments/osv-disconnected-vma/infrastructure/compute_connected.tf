module "connected-bastion-vm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "bastion-connected"
  ami = data.aws_ami.fedora_x86.id
  iam_instance_profile = aws_iam_instance_profile.allow_access_bootstrap_bucket.name
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.vm
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.connected_network.public_subnets[local.default_availability_zone_index]
  vpc_security_group_ids = [ module.connected-sg-bastion.security_group_id ]
  availability_zone = local.default_availability_zone
  associate_public_ip_address = true
  create_security_group = false
  root_block_device = {
    type       = "gp3"
    size       = 100
  }
}
