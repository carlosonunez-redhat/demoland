module "disconnected_network" {
  source = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = "disconnected_network"
  cidr = local.options.cloud_config.aws.networking.disconnected.cidr
  azs = local.options.cloud_config.aws.networking.common.availability_zones
  public_subnets = []
  private_subnets = local.options.cloud_config.aws.networking.disconnected.subnets.private
  enable_nat_gateway = false
  vpc_block_public_access_options = {
    internet_gateway_block_mode = "block-bidirectional"
  }
}

// This enables the OCP nodes to access the S3 bucket containing their ignition files.
module "vpc_endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  vpc_id = module.disconnected_network.vpc_id
  create_security_group = true
  security_group_name_prefix = "vpce-sg-"
  security_group_description = "Security group for disconnected VPC endpoints"
  security_group_rules = {
    ingress_https = {
      description = "API access"
      cidr_blocks = [ module.disconnected_network.vpc_cidr_block ]
    }
  }
  endpoints = {
    s3 = {
      service = "s3"
      subnets = module.disconnected_network.private_subnets
      private_dns_enabled = true
      dns_options = {
        private_dns_only_for_inbound_resolver_argument = true
        private_dns_preference = "SPECIFIED_DOMAINS_ONLY"
        private_dns_specified_domains = [ local.options.cloud_config.aws.networking.disconnected.dns.domain_name ]
      }
    }
  }
}

module "disconnected-sg-bastion" {
  source = "terraform-aws-modules/security-group/aws"
  name = "bastion-nodes-sg-disconnected"
  description = "SSH access into bastion inside disconnected network"
  vpc_id = module.disconnected_network.vpc_id
  ingress_with_self = [
    {
      self = true
      from_port = 0
      to_port = 0
      protocol = "-1"
    }
  ]
  ingress_with_cidr_blocks = [{
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = "${local.bastion_bridge_ip}/32"
  }]
  egress_with_cidr_blocks = [{
    from_port = 0
    to_port = 0
    protocol = -1
    description = "Allow all outbound"
    cidr_blocks = local.options.cloud_config.aws.networking.disconnected.cidr
  }]
}

module "disconnected-sg-mgmt-net" {
  source = "terraform-aws-modules/security-group/aws"
  name = "ocp-nodes-sg-disconnected"
  description = "OCP control plane and workers"
  vpc_id = module.disconnected_network.vpc_id
  ingress_with_self = [
    {
      self = true
      from_port = 0
      to_port = 0
      protocol = "-1"
    }
  ]
  egress_with_cidr_blocks = [{
    from_port = 0
    to_port = 0
    protocol = -1
    description = "Allow all outbound"
    cidr_blocks = local.options.cloud_config.aws.networking.disconnected.cidr
  }]
}

module "disconnected-sg-ocp" {
  source = "terraform-aws-modules/security-group/aws"
  name = "ocp-nodes-sg-disconnected"
  description = "OCP control plane and workers"
  vpc_id = module.disconnected_network.vpc_id
  ingress_with_self = [
    {
      self = true
      from_port = 0
      to_port = 0
      protocol = "-1"
    }
  ]
  ingress_with_source_security_group_id = [ for p in [22,443,6443]: {
    from_port = p
    to_port = p
    protocol = "tcp"
    source_security_group_id = module.disconnected-sg-bastion.security_group_id
  } ]
  egress_with_cidr_blocks = [{
    from_port = 0
    to_port = 0
    protocol = -1
    description = "Allow all outbound"
    cidr_blocks = local.options.cloud_config.aws.networking.disconnected.cidr
  }]
}

module "disconnected-sg-vsphere" {
  source = "terraform-aws-modules/security-group/aws"
  name = "vsphere-nodes-sg-disconnected"
  description = "ESX and vSphere nodes"
  vpc_id = module.disconnected_network.vpc_id
  ingress_with_self = [
    {
      self = true
      from_port = 0
      to_port = 0
      protocol = "-1"
    }
  ]
  ingress_with_source_security_group_id = [ for p in [22,80,443,8080,8443]: {
    from_port = p
    to_port = p
    protocol = "tcp"
    source_security_group_id = module.disconnected-sg-bastion.security_group_id
  } ]
  egress_with_cidr_blocks = [{
    from_port = 0
    to_port = 0
    protocol = -1
    description = "Allow all outbound"
    cidr_blocks = local.options.cloud_config.aws.networking.disconnected.cidr
  }]
}

module "disconnected-sg-artifactory" {
  source = "terraform-aws-modules/security-group/aws"
  name = "artifactory-nodes-sg-disconnected"
  description = "Artifactory nodes"
  vpc_id = module.disconnected_network.vpc_id
  ingress_with_self = [
    {
      self = true
      from_port = 0
      to_port = 0
      protocol = "-1"
    }
  ]
  ingress_with_source_security_group_id = [ for p in [22,8081,8082]: {
    from_port = p
    to_port = p
    protocol = "tcp"
    source_security_group_id = module.disconnected-sg-bastion.security_group_id
  } ]
  egress_with_cidr_blocks = [{
    from_port = 0
    to_port = 0
    protocol = -1
    description = "Allow all outbound"
    cidr_blocks = local.options.cloud_config.aws.networking.disconnected.cidr
  }]
}

module "disconnected-sg-ocp-to-artifactory" {
  source = "terraform-aws-modules/security-group/aws"
  name = "artifactory-nodes-sg-disconnected"
  description = "Artifactory host"
  vpc_id = module.disconnected_network.vpc_id
  ingress_with_source_security_group_id = flatten([
    [ for kv in local.allowed_ports.artifactory_nodes : {
      from_port = tonumber(element(split(":", kv), 0))
      to_port = tonumber(element(split(":", kv), 0))
      protocol = length(split(":", kv)) == 3 ? element(split(":", kv), 2) : "tcp"
      description = length(split(":", kv)) == 2 ? element(split(":", kv), 1) : format("allow port [%s]", element(split(":", kv), 0))
      source_security_group_id = module.disconnected-sg-ocp.security_group_id
    }],
    [{
      from_port = 22
      to_port = 22
      protocol = "tcp"
      source_security_group_id = module.disconnected-sg-bastion.security_group_id
    }]
  ])
  egress_with_cidr_blocks = [{
    from_port = 0
    to_port = 0
    protocol = -1
    description = "Allow all outbound"
    cidr_blocks = local.options.cloud_config.aws.networking.disconnected.cidr
  }]
}

module "disconnected-sg-ocp-to-vsphere" {
  source = "terraform-aws-modules/security-group/aws"
  name = "artifactory-nodes-sg-disconnected"
  description = "Artifactory host"
  vpc_id = module.disconnected_network.vpc_id
  ingress_with_source_security_group_id = flatten([
    [ for kv in local.allowed_ports.vsphere_api_access : {
      from_port = tonumber(element(split(":", kv), 0))
      to_port = tonumber(element(split(":", kv), 0))
      protocol = length(split(":", kv)) == 3 ? element(split(":", kv), 2) : "tcp"
      description = length(split(":", kv)) == 2 ? element(split(":", kv), 1) : format("allow port [%s]", element(split(":", kv), 0))
      source_security_group_id = module.disconnected-sg-ocp.security_group_id
    }],
    [{
      from_port = 22
      to_port = 22
      protocol = "tcp"
      source_security_group_id = module.disconnected-sg-bastion.security_group_id
    }]
  ])
  egress_with_cidr_blocks = [{
    from_port = 0
    to_port = 0
    protocol = -1
    description = "Allow all outbound"
    cidr_blocks = local.options.cloud_config.aws.networking.disconnected.cidr
  }]
}
