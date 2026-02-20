resource "aws_route53_record" "connected-bastion-vm" {
  zone_id = data.aws_route53_zone.public.id
  name = "bastion"
  type = "A"
  ttl = 1
  records = [
    module.connected-bastion-vm.public_ip
  ]
}
