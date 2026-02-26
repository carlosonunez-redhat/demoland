locals {
  config = yamldecode(file("/secrets/config.yaml"))
  options = local.config.deploy
  default_availability_zone = local.options.cloud_config.aws.networking.common.default_availability_zone
  default_availability_zone_index = index(local.options.cloud_config.aws.networking.common.availability_zones, local.default_availability_zone)
  provisioning_subnet_disconnected = module.disconnected_network.private_subnets[local.default_availability_zone_index]
}

data "tls_public_key" "ec2_key" {
  private_key_openssh = file("/secrets/ssh-key")
}

data "aws_region" "current" {}

data "aws_route53_zone" "public" {
  name = "${local.options.cloud_config.aws.networking.connected.dns.domain_name}."
}

data "aws_vpc_endpoint_service" "s3" {
  service = "s3"
  service_type = "Gateway"
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
    values = [ "Fedora-Cloud-Base-AmazonEC2.x86_64-43-2*" ]
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
