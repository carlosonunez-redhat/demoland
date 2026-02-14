locals {
  config = yamldecode(file("/secrets/config.yaml"))
  options = local.config.deploy
}

data "tls_public_key" "ec2_key" {
  private_key_openssh = file("/secrets/ssh-key")
}

data "aws_region" "current" {}
