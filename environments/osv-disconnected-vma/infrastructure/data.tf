locals {
  config = yamldecode(file("/secrets/config.yaml"))
  options = local.config.deploy
}
