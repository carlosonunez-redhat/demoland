resource "aws_route53_zone" "disconnected" {
  name = local.options.cloud_config.aws.networking.disconnected.dns.domain_name
  vpc {
    vpc_id = module.disconnected_network.vpc_id
  }
  vpc {
    vpc_id = module.connected_network.vpc_id
  }
}

resource "aws_route53_record" "bootstrap" {
  zone_id = aws_route53_zone.disconnected.id
  name = "bootstrap"
  type = "A"
  ttl = 1
  records = [
    module.disconnected-bastion-vm.private_ip
  ]
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

resource "aws_route53_record" "control_plane_nodes" {
  for_each = { for k, v in module.disconnected-ocp-cp-nodes-bm : k => v }
  zone_id = aws_route53_zone.disconnected.id
  name = "control-plane${index(module.disconnected-ocp-cp-nodes-bm, each.value)}"
  type = "A"
  ttl = 1
  records = [ each.value.private_ip ]
}

resource "aws_route53_record" "worker_nodes" {
  for_each = { for k, v in module.disconnected-ocp-worker-nodes-bm : k => v }
  zone_id = aws_route53_zone.disconnected.id
  name = "compute${index(module.disconnected-ocp-worker-nodes-bm, each.value)}"
  type = "A"
  ttl = 1
  records = [ each.value.private_ip ]
}
