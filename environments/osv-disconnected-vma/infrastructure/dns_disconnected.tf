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

resource "aws_route53_record" "disconnected-artifactory-vm" {
  zone_id = aws_route53_zone.disconnected.id
  name = "registry"
  type = "A"
  ttl = 1
  records = [
    module.disconnected-artifactory-vm.private_ip
  ]
}

resource "aws_route53_record" "lb_cert" {
  zone_id = aws_route53_zone.disconnected.id
  for_each = {
    for dvo in aws_acm_certificate.lb_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
}
