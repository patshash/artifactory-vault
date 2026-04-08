resource "aws_security_group" "services_alb" {
  name        = "${local.name_prefix}-services-alb"
  description = "Security group for the shared Vault and Artifactory HTTPS ALB."
  vpc_id      = aws_vpc.sandpit.id

  tags = {
    Name = "${local.name_prefix}-services-alb-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "services_alb_all" {
  security_group_id = aws_security_group.services_alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound traffic."
}

resource "aws_vpc_security_group_ingress_rule" "services_alb_https" {
  security_group_id = aws_security_group.services_alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS access from the internet."
}

resource "aws_acm_certificate" "services" {
  domain_name               = local.vault_fqdn
  subject_alternative_names = [local.artifactory_fqdn]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-services"
  }
}

resource "aws_route53_record" "services_certificate_validation" {
  for_each = {
    for dvo in aws_acm_certificate.services.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.selected.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "services" {
  certificate_arn         = aws_acm_certificate.services.arn
  validation_record_fqdns = [for record in aws_route53_record.services_certificate_validation : record.fqdn]
}

resource "aws_lb" "services" {
  name               = "${local.name_prefix}-services"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.services_alb.id]
  subnets            = [for key in sort(keys(aws_subnet.public)) : aws_subnet.public[key].id]

  tags = {
    Name = "${local.name_prefix}-services-alb"
  }
}

resource "aws_lb_target_group" "vault" {
  name        = "${local.name_prefix}-vault"
  port        = 8200
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.sandpit.id

  health_check {
    enabled  = true
    matcher  = "200"
    path     = "/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200&drsecondarycode=200&performancestandbyok=true"
    port     = "traffic-port"
    protocol = "HTTP"
  }

  tags = {
    Name    = "${local.name_prefix}-vault-tg"
    Service = "vault"
  }
}

resource "aws_lb_target_group_attachment" "vault" {
  target_group_arn = aws_lb_target_group.vault.arn
  target_id        = aws_instance.vault.id
  port             = 8200
}

resource "aws_lb_target_group" "artifactory" {
  name        = "${local.name_prefix}-artifactory"
  port        = 8082
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.sandpit.id

  health_check {
    enabled  = true
    matcher  = "200-399"
    path     = "/"
    port     = "traffic-port"
    protocol = "HTTP"
  }

  tags = {
    Name    = "${local.name_prefix}-artifactory-tg"
    Service = "artifactory"
  }
}

resource "aws_lb_target_group_attachment" "artifactory" {
  target_group_arn = aws_lb_target_group.artifactory.arn
  target_id        = aws_instance.artifactory.id
  port             = 8082
}

resource "aws_lb_listener" "services_https" {
  load_balancer_arn = aws_lb.services.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.services.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "unknown host"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "vault" {
  listener_arn = aws_lb_listener.services_https.arn
  priority     = 10

  condition {
    host_header {
      values = [local.vault_fqdn]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }
}

resource "aws_lb_listener_rule" "artifactory" {
  listener_arn = aws_lb_listener.services_https.arn
  priority     = 20

  condition {
    host_header {
      values = [local.artifactory_fqdn]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.artifactory.arn
  }
}

resource "aws_vpc_security_group_ingress_rule" "vault_api" {
  security_group_id            = aws_security_group.vault.id
  referenced_security_group_id = aws_security_group.services_alb.id
  from_port                    = 8200
  to_port                      = 8200
  ip_protocol                  = "tcp"
  description                  = "Vault API and UI from the shared services ALB."
}

resource "aws_vpc_security_group_ingress_rule" "artifactory_port_8082" {
  security_group_id            = aws_security_group.artifactory.id
  referenced_security_group_id = aws_security_group.services_alb.id
  from_port                    = 8082
  to_port                      = 8082
  ip_protocol                  = "tcp"
  description                  = "Artifactory UI/API port from the shared services ALB."
}

resource "aws_route53_record" "vault" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = local.vault_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.services.dns_name
    zone_id                = aws_lb.services.zone_id
    evaluate_target_health = false
  }

  allow_overwrite = true
}

resource "aws_route53_record" "artifactory" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = local.artifactory_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.services.dns_name
    zone_id                = aws_lb.services.zone_id
    evaluate_target_health = false
  }

  allow_overwrite = true
}
