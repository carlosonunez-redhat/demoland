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

# resource "aws_route53_record" "api-ext" {}
# resource "aws_route53_record" "api-int" {}
# resource "aws_route53_record" "bootstrap" {} # same as bastion.private.network
# resource "aws_route53_record" "control-plane" {} # count = len(ocp_cp_bare_metal_vms)
# resource "aws_route53_record" "worker" {} # count  = len(ocp_worker_bare_metal_vms)
