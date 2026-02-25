module "disconnected-bastion-vm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "bastion-disconnected"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.vm
  availability_zone = local.options.cloud_config.aws.storage.oc_mirror.availability_zone
  associate_public_ip_address = false
  ami = data.aws_ami.fedora_x86.id
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.disconnected_network.private_subnets[local.oc_mirror_az_index]
  vpc_security_group_ids = [ module.disconnected-sg-bastion.security_group_id ]
  create_security_group = false
  root_block_device = {
    type       = "gp3"
    size       = 100
  }
}

module "disconnected-artifactory-vm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "artifactory-disconnected"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.vm
  ami = data.aws_ami.fedora_x86.id
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.disconnected_network.private_subnets[0]
  vpc_security_group_ids = [
    module.disconnected-sg-artifactory.security_group_id,
    module.disconnected-sg-ocp-to-artifactory.security_group_id
  ]
  create_security_group = false
  root_block_device = {
    type       = "gp3"
    size       = 100
  }
}

module "disconnected-ocp-cp-nodes-bm" {
  count = fileexists(var.bare_metal_creation_sentinel_file) ? 3 : 0
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-cp"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.bare_metal
  ami = data.aws_ami.ipxe.id
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.disconnected_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
  create_security_group = false
  root_block_device = {
    type       = "gp3"
    size       = 100
  }
}

module "disconnected-ocp-worker-nodes-bm" {
  count = fileexists(var.bare_metal_creation_sentinel_file) ? 3 : 0
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-cp"
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.bare_metal
  ami = data.aws_ami.ipxe.id
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.disconnected_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
  create_security_group = false
  root_block_device = {
    type       = "gp3"
    size       = 100
  }
}

module "disconnected-esx-host-bm" {
  count = fileexists(var.bare_metal_creation_sentinel_file) ? 3 : 0
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-cp"
  ami = data.aws_ami.ipxe.id
  instance_type = local.options.cloud_config.aws.compute.instance_sizes.bare_metal
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.disconnected_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
  create_security_group = false
  root_block_device = {
    type       = "gp3"
    size       = 100
  }
}
