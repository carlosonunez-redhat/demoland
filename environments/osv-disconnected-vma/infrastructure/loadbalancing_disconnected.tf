resource "aws_acm_certificate" "lb_cert" {
  domain_name       = local.options.cloud_config.aws.networking.dns.domain_name
  validation_method = "DNS"

  tags = {
    Environment = "test"
  }

  lifecycle {
    create_before_destroy = true
  }
}

module "api-alb" {
  source = "terraform-aws-modules/alb/aws"
  name = "api-public"
  vpc_id = module.disconnected_network.vpc_id
  subnets = module.disconnected_network.private_subnets
  listeners = {
    ex-http-https-redirect = {
      port     = 6443
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    ex-https = {
      port            = 6443
      protocol        = "HTTPS"
      certificate_arn = resource.aws_acm_certificate.lb_cert.arn
      forward = {
        target_group_key = "control-plane-nodes"
      }
    }
  }

  target_groups = {
    control-plane-nodes = {
      name_prefix = "ocp-cp-"
      protocol = "HTTPS"
      port = 6443
      target_type = "instance"
      health_check = {
        enabled = true
        healthy_threshold = 5
        unhealthy_threshold = 10
        timeout = 5
        interval = 30
        path = "/readyz"
        matcher = "200"
        port = "traffic-port"
      }
    }
  }
  route53_records = {
    A = {
      name = "api"
      type = "A"
      zone_id = aws_route53_zone.disconnected.id
    }
  }
}

# same as api since everything in disco is in private subnets.
module "api-int-alb" {
  source = "terraform-aws-modules/alb/aws"
  name = "api-public"
  vpc_id = module.disconnected_network.vpc_id
  subnets = module.disconnected_network.private_subnets
  listeners = {
    ex-http-https-redirect = {
      port     = 6443
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    ex-https = {
      port            = 6443
      protocol        = "HTTPS"
      certificate_arn = resource.aws_acm_certificate.lb_cert.arn
      forward = {
        target_group_key = "control-plane-nodes"
      }
    }
  }

  target_groups = {
    control-plane-nodes = {
      name_prefix = "ocp-cp-"
      protocol = "HTTPS"
      port = 6443
      target_type = "instance"
      health_check = {
        enabled = true
        healthy_threshold = 5
        unhealthy_threshold = 10
        timeout = 5
        interval = 30
        path = "/readyz"
        matcher = "200"
        port = "traffic-port"
      }
    }
  }
  route53_records = {
    A = {
      name = "api-int"
      type = "A"
      zone_id = aws_route53_zone.disconnected.id
    }
  }
}

module "machine-config" {
  source = "terraform-aws-modules/alb/aws"
  name = "machine-config"
  vpc_id = module.disconnected_network.vpc_id
  subnets = module.disconnected_network.private_subnets
  listeners = {
    ex-http = {
      port            = 22623
      protocol        = "HTTP"
      certificate_arn = resource.aws_acm_certificate.lb_cert.arn
      forward = {
        target_group_key = "control-plane-nodes"
      }
    }
  }

  target_groups = {
    control-plane-nodes = {
      name_prefix = "ocp-cp-"
      protocol = "HTTP"
      port = 22623
      target_type = "instance"
    }
  }
}

module "app" {
  source = "terraform-aws-modules/alb/aws"
  name = "apps"
  vpc_id = module.disconnected_network.vpc_id
  subnets = module.disconnected_network.private_subnets
  listeners = {
    ex-http = {
      port            = 80
      protocol        = "HTTP"
      forward = {
        target_group_key = "worker-nodes-insecure"
      }
    }
    ex-https-redirect = {
      port            = 443
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    ex-https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = resource.aws_acm_certificate.lb_cert.arn
      forward = {
        target_group_key = "worker-nodes-secure"
      }
    }
  }
  target_groups = {
    worker-nodes-insecure = {
      name_prefix = "ocp-compute-"
      protocol = "HTTP"
      port = 80
      target_type = "instance"
    }
    worker-nodes-secure = {
      name_prefix = "ocp-compute-"
      protocol = "HTTP"
      port = 443
      target_type = "instance"
    }
  }
  route53_records = {
    A = {
      name = "*.apps"
      type = "A"
      zone_id = aws_route53_zone.disconnected.id
    }
  }
}
