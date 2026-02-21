locals {
  config = yamldecode(file("/secrets/config.yaml"))
  options = local.config.deploy
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
