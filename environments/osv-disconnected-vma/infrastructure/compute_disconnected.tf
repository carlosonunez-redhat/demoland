module "disconnected-bastion-vm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "bastion"
  instance_type = "m8g.large"
  ami = data.aws_ami.fedora_arm.id
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.connected_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-bastion-bridge.security_group_id ]
}

module "disconnected-artifactory-vm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "artifactory"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.vm
  ami = data.aws_ami.fedora_arm.id
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.disconnected_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
}

module "disconnected-ocp-cp-nodes-bm" {
  count = fileexists(var.bare_metal_creation_sentinel_file) ? 3 : 0
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-cp"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.bare_metal
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.disconnected_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
}

module "disconnected-ocp-worker-nodes-bm" {
  count = fileexists(var.bare_metal_creation_sentinel_file) ? 3 : 0
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-cp"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.bare_metal
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.disconnected_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
}

module "disconnected-esx-host-bm" {
  count = fileexists(var.bare_metal_creation_sentinel_file) ? 3 : 0
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-cp"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.bare_metal
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.disconnected_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
}
