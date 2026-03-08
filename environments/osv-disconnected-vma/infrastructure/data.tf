locals {
  config = yamldecode(file("/secrets/config.yaml"))
  options = local.config.deploy
  default_availability_zone = local.options.cloud_config.aws.networking.common.default_availability_zone
  default_availability_zone_index = index(local.options.cloud_config.aws.networking.common.availability_zones, local.default_availability_zone)
  provisioning_subnet_disconnected = module.disconnected_network.private_subnets[local.default_availability_zone_index]
  bootstrap_bucket_name = "ignition-bootstrap-${random_string.bootstrap_bucket.result}"
  bastion_bridge_ip = cidrhost(module.disconnected_network.private_subnets_cidr_blocks[local.default_availability_zone_index], 252)
  openshift_version = local.options.cluster_config.cluster_version
  openshift_channel = "release-${join(".", slice(split(".", local.openshift_version),0,2))}"
  allowed_ports = {
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
      "6443:Kubernetes API",
      "8080:Web services",
      "8083:BMC",
      "9999:Python agent"
    ]
    artifactory_nodes = [
      "80",
      "443",
      "8080",
      "8082",
      "8443"
    ]
    vsphere_api_access = [
      "80",
      "443",
      "8080",
      "8443"
    ]
  }
}

data "tls_public_key" "ec2_key" {
  private_key_openssh = file("/secrets/ssh-key")
}

data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_route53_zone" "public" {
  name = "${local.options.cloud_config.aws.networking.connected.dns.domain_name}."
}

data "aws_vpc_endpoint_service" "s3" {
  service = "s3"
  service_type = "Gateway"
}

data "http" "rhcos" {
  url = "https://raw.githubusercontent.com/openshift/installer/${local.openshift_channel}/data/data/coreos/rhcos.json"
}

data "aws_ami" "ipxe" {
  most_recent = true
  filter {
    name = "name"
    values = [ "iPXE*" ]
  }
  filter {
    name = "architecture"
    values = [ "x86_64" ]
  }
  filter {
    name = "virtualization-type"
    values = [ "hvm" ]
  }
  filter {
    name = "owner-id"
    values = [ "833372943033" ] # source: https://ipxe.org/howto/ec2
  }
}

data "aws_ami" "fedora_x86" {
  most_recent = true
  filter {
    name = "name"
    values = [ "Fedora-Cloud-Base-AmazonEC2.x86_64-43-20260226.0*" ]
  }
  filter {
    name = "owner-id"
    values = [ "125523088429" ] # source: https://wiki.centos.org/Cloud(2f)AWS.html
  }
  filter {
    name = "architecture"
    values = [ "x86_64" ]
  }
  filter {
    name = "virtualization-type"
    values = [ "hvm" ]
  }
}

resource "random_string" "bootstrap_bucket" {
  numeric = false
  length = 8
  upper = false
  special = false
}

resource "random_string" "ca-suffix" {
  length           = 8
  special          = false
  numeric = false
}

