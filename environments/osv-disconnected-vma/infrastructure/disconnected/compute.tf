module "disconnected-bastion-vm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "bastion"
  instance_type = "m8g.large"
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.public_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-bastion-bridge.security_group_id ]
}

module "disconnected-artifactory-vm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "artifactory"
  instance_type = "m8a.large"
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.public_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
}

module "disconnected-ocp-cp-nodes-bm" {
  count = 3
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-cp"
  instance_type = "m7g.metal"
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.public_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
}

module "disconnected-ocp-worker-nodes-bm" {
  count = 3
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-cp"
  instance_type = "m7g.metal"
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.public_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
}

module "disconnected-esx-host-bm" {
  source = "terraform-aws-modules/ec2-instance/aws"
  name = "ocp-cp"
  instance_type = "m7g.metal"
  key_name = module.ec2_key.key_pair_name
  subnet_id = module.public_network.private_subnets[0]
  vpc_security_group_ids = [ module.disconnected-sg-ocp-to-artifactory.security_group_id ]
}
