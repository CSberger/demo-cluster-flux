
data "aws_route53_zone" "selected" {
  name         = "dev-sandbox.name"
}

resource "aws_route53_record" "grafana" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "grafana"
  type    = "CNAME"
  ttl     = 5

  records        = ["${local.istio_elb_hostname}"]
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "*.${data.aws_route53_zone.selected.name}"
  validation_method = "DNS"

  tags = {
    Environment = "dev"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# resource "aws_route53_record" "cert-validation" {
#   for_each = {
#     for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
#       name   = dvo.resource_record_name
#       record = dvo.resource_record_value
#       type   = dvo.resource_record_type
#     }
#   }

#   allow_overwrite = true
#   name            = each.value.name
#   records         = [each.value.record]
#   ttl             = 60
#   type            = each.value.type
#   zone_id         = data.aws_route53_zone.selected.zone_id
# }

