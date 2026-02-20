resource "aws_route53_zone" "disconnected" {
  name = local.options.cloud_config.aws.networking.disconnected.dns.domain_name
  vpc {
    vpc_id = module.disconnected_network.vpc_id
  }
  vpc {
    vpc_id = module.connected_network.vpc_id
  }
}

resource "aws_route53_record" "disconnected-bastion-vm" {
  zone_id = aws_route53_zone.disconnected.id
  name = "bastion"
  type = "A"
  ttl = 1
  records = [
    module.disconnected-bastion-vm.private_ip
  ]
}
