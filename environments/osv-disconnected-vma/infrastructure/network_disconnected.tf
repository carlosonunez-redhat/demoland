locals {
  allowed_ports = {
    bastion_host = [
      "22"
    ]
    openshift_nodes = [
      "67:dnsmasq",
      "68:dnsmasq",
      "69:TFTP",
      "80:web services",
      "123:NTP",
      "5050:hardware fact gathering",
      "5051:hardware fact gathering",
      "6180:BMC worker node access",
      "6183:BMC worker node access",
      "6385:Ironic API",
      "6388:Ironic API",
      "8080:Web services",
      "8083:BMC",
      "9999:Python agent"
    ]
    artifactory_nodes = [
      "80",
      "443",
      "8080",
      "8443"
    ]
    vsphere_api_access = [
      "80",
      "443",
      "8080",
      "8443"
    ]
}

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

module "disconnected-sg-bastion" {
  source = "terraform-aws-modules/security-group/aws"
  name = "bastion-nodes-sg-connected"
  description = "OCP control plane and workers"
  vpc_id = module.connected-network.vpc_id
  ingress_with_self = [{
    from_port = 0
    to_port = 0
    protocol = -1
    self = true
    cidr_blocks = "${var.ssh_ip}/22"
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
  ingress_with_source_security_group_id = [
    {
      from_port = 22
      to_port = 22
      protocol = tcp
      source_security_group_id = module.disconnected-bastion-sg.this_security_group_id
    }
  ]
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
  ingress_with_source_security_group_id = [
    {
      from_port = 22
      to_port = 22
      protocol = tcp
      source_security_group_id = module.disconnected-bastion-sg.this_security_group_id
    }
  ]
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
  ingress_with_source_security_group_id = [
    {
      from_port = 22
      to_port = 22
      protocol = tcp
      source_security_group_id = module.disconnected-bastion-sg.this_security_group_id
    }
  ]
}

module "disconnected-sg-ocp-to-artifactory" {
  source = "terraform-aws-modules/security-group/aws"
  name = "artifactory-nodes-sg-disconnected"
  description = "Artifactory host"
  vpc_id = module.disconnected_network.vpc_id
  ingress_with_source_security_group_id = flatten(
    [ for kv in local.allowed_ports.artifactory_nodes : {
      from_port = element(split(kv, ":"), 0)
      to_port = element(split(kv, ":"), 0)
      protocol = len(split(kv, ":")) == 3 ? element(split(kv, ":"), 2) : "tcp"
      description = len(split(kv, ":")) == 2 ? element(split(kv, ":"), 1) : format("allow port '%d'", element(split(kv, ":"), 0))
      source_security_group_id = module.disconnected-sg-openshift.this_security_group_id
    }],
    [{
      from_port = 22
      to_port = 22
      protocol = tcp
      source_security_group_id = module.disconnected-bastion-sg.this_security_group_id
    }
  ])
}

module "disconnected-sg-ocp-to-vsphere" {
  source = "terraform-aws-modules/security-group/aws"
  name = "artifactory-nodes-sg-disconnected"
  description = "Artifactory host"
  vpc_id = module.disconnected_network.vpc_id
  ingress_with_source_security_group_id = flatten(
    [ for kv in local.allowed_ports.vsphere_api_access : {
      from_port = element(split(kv, ":"), 0)
      to_port = element(split(kv, ":"), 0)
      protocol = len(split(kv, ":")) == 3 ? element(split(kv, ":"), 2) : "tcp"
      description = len(split(kv, ":")) == 2 ? element(split(kv, ":"), 1) : format("allow port '%d'", element(split(kv, ":"), 0))
      source_security_group_id = module.disconnected-sg-openshift.this_security_group_id
    }],
    [{
      from_port = 22
      to_port = 22
      protocol = tcp
      source_security_group_id = module.disconnected-bastion-sg.this_security_group_id
    }
  ])
}
