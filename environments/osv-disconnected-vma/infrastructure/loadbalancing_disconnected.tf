resource "tls_private_key" "cert" {
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "cert" {
  private_key_pem  = tls_private_key.cert.private_key_pem
  dns_names = [
    local.options.cloud_config.aws.networking.disconnected.dns.domain_name,
    "*.${local.options.cloud_config.aws.networking.disconnected.dns.domain_name}"
  ]
  subject {
    common_name = local.options.cloud_config.aws.networking.disconnected.dns.domain_name
  }
  validity_period_hours = 8760
  allowed_uses = [ "key_encipherment", "digital_signature", "server_auth" ]
}

resource "aws_acm_certificate" "cert" {
  private_key = tls_private_key.cert.private_key_pem
  certificate_body = tls_self_signed_cert.cert.cert_pem
}

resource "aws_lb_target_group_attachment" "api" {
  for_each = { for k, v in module.disconnected-ocp-cp-nodes-bm : k => v }
  target_group_arn = module.api-alb.target_groups["target-group"].arn
  target_id = each.value.id
  port = 6443
}

module "api-alb" {
  source = "terraform-aws-modules/alb/aws"
  name = "api-public"
  internal = true
  enable_deletion_protection = false
  vpc_id = module.disconnected_network.vpc_id
  subnets = module.disconnected_network.private_subnets
  listeners = {
    ex-https = {
      port            = 6443
      protocol        = "HTTPS"
      certificate_arn = aws_acm_certificate.cert.arn
      forward = {
        target_group_key = "target-group"
      }
    }
  }

  target_groups = {
    target-group = {
      create_attachment = false
    }
  }
  route53_records = {
    A = {
      name = "api.${local.options.cluster_config.cluster_name}"
      type = "A"
      zone_id = aws_route53_zone.disconnected.id
    }
  }
}
resource "aws_lb_target_group_attachment" "api-int" {
  for_each = { for k, v in module.disconnected-ocp-cp-nodes-bm : k => v }
  target_group_arn = module.api-int-alb.target_groups["target-group"].arn
  target_id = each.value.id
  port = 6443
}

# same as api since everything in disco is in private subnets.
module "api-int-alb" {
  source = "terraform-aws-modules/alb/aws"
  name = "api-int-public"
  internal = true
  enable_deletion_protection = false
  vpc_id = module.disconnected_network.vpc_id
  subnets = module.disconnected_network.private_subnets
  listeners = {
    ex-https = {
      port            = 6443
      protocol        = "HTTPS"
      certificate_arn = aws_acm_certificate.cert.arn
      forward = {
        target_group_key = "target-group"
      }
    }
  }

  target_groups = {
    target-group = {
      create_attachment = false
    }
  }
  route53_records = {
    A = {
      name = "api-int.${local.options.cluster_config.cluster_name}"
      type = "A"
      zone_id = aws_route53_zone.disconnected.id
    }
  }
}


resource "aws_lb_target_group_attachment" "machine-config" {
  for_each = { for k, v in module.disconnected-ocp-cp-nodes-bm : k => v }
  target_group_arn = module.machine-config-alb.target_groups["target-group"].arn
  target_id = each.value.id
  port = 22623
}
module "machine-config-alb" {
  source = "terraform-aws-modules/alb/aws"
  name = "machine-config"
  internal = true
  enable_deletion_protection = false
  vpc_id = module.disconnected_network.vpc_id
  subnets = module.disconnected_network.private_subnets
  listeners = {
    ex-http = {
      port            = 22623
      protocol        = "HTTP"
      forward = {
        target_group_key = "target-group"
      }
    }
  }

  target_groups = {
    target-group = {
      create_attachment = false
    }
  }
}

resource "aws_lb_target_group_attachment" "apps-insecure" {
  for_each = { for k, v in module.disconnected-ocp-worker-nodes-bm : k => v }
  target_group_arn = module.apps-alb.target_groups["target-group-insecure"].arn
  target_id = each.value.id
  port = 80
}

resource "aws_lb_target_group_attachment" "apps-secure" {
  for_each = { for k, v in module.disconnected-ocp-worker-nodes-bm : k => v }
  target_group_arn = module.apps-alb.target_groups["target-group-secure"].arn
  target_id = each.value.id
  port = 443
}

module "apps-alb" {
  source = "terraform-aws-modules/alb/aws"
  name = "apps"
  internal = true
  enable_deletion_protection = false
  vpc_id = module.disconnected_network.vpc_id
  subnets = module.disconnected_network.private_subnets
  listeners = {
    ex-http = {
      port            = 80
      protocol        = "HTTP"
      forward = {
        target_group_key = "target-group-insecure"
      }
    }
    ex-https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = aws_acm_certificate.cert.arn
      forward = {
        target_group_key = "target-group-secure"
      }
    }
  }
  target_groups = {
    target-group-insecure = {
      create_attachment = false
    }
    target-group-secure = {
      create_attachment = false
    }
  }
  route53_records = {
    A = {
      name = "*.apps.${local.options.cluster_config.cluster_name}"
      type = "A"
      zone_id = aws_route53_zone.disconnected.id
    }
  }
}
