module "public_network" {
  source = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = "connected-network"
  cidr = local.options.cloud_config.aws.networking.connected.cidr
  azs = local.options.cloud_config.aws.networking.common.availability_zones
  public_subnets = local.options.cloud_config.aws.networking.connected.subnets.public
  private_subnets = local.options.cloud_config.aws.networking.connected.subnets.private
  enable_nat_gateway = true
}

module "disconnected-network" {
  source = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = "disconnected-network"
  cidr = local.options.cloud_config.aws.networking.disconnected.cidr
  azs = local.options.cloud_config.aws.networking.common.availability_zones
  public_subnets = local.options.cloud_config.aws.networking.disconnected.subnets.public
  private_subnets = local.options.cloud_config.aws.networking.disconnected.subnets.private
  enable_nat_gateway = false
  vpc_block_public_access_options = {
    internet_gateway_block_mode = "block-bidirectional"
  }
}
