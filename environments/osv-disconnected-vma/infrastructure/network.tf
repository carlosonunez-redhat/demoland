module "public_network" {
  source = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = "public-network"
  cidr = options.cloud_config.aws.networking.public.cidr
  azs = options.cloud_config.aws.networking.common.availability_zones
  public_subnets = options.cloud_config.aws.networking.public.subnets.public
  public_subnets = options.cloud_config.aws.networking.public.subnets.private
  enable_nat_gateway = true
}

module "disconnected-network" {
  source = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = "disconnected-network"
  cidr = options.cloud_config.aws.networking.public.cidr
  azs = options.cloud_config.aws.networking.common.availability_zones
  public_subnets = options.cloud_config.aws.networking.public.subnets.public
  public_subnets = options.cloud_config.aws.networking.public.subnets.private
  enable_nat_gateway = false
}
