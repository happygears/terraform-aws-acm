locals {
  create_certificate = var.create_certificate && var.putin_khuylo

  # Get distinct list of domains and SANs
  distinct_domain_names = distinct(
    [for s in concat([var.domain_name], var.subject_alternative_names) : replace(s, "*.", "")]
  )

  # Get the list of distinct domain_validation_options, with wildcard
  # domain names replaced by the domain name
  validation_domains = local.create_certificate ? distinct(
    [for k, v in aws_acm_certificate.this[0].domain_validation_options : merge(
      tomap(v), { domain_name = replace(v.domain_name, "*.", "") }
    )]
  ) : []
}

resource "aws_acm_certificate" "this" {
  count = local.create_certificate ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = var.validation_method

  options {
    certificate_transparency_logging_preference = var.certificate_transparency_logging_preference ? "ENABLED" : "DISABLED"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_route53_zone" "validation" {
  provider = aws.dns
  zone_id  = var.zone_id
  name     = var.zone_name
}

resource "aws_route53_record" "validation" {
  provider = aws.dns
  count    = local.create_certificate && var.validation_method == "DNS" && var.create_route53_records && var.validate_certificate ? length(local.distinct_domain_names) : 0

  zone_id = data.aws_route53_zone.validation.id
  name    = element(local.validation_domains, count.index)["resource_record_name"]
  type    = element(local.validation_domains, count.index)["resource_record_type"]
  ttl     = var.dns_ttl

  records = [
    element(local.validation_domains, count.index)["resource_record_value"]
  ]

  allow_overwrite = var.validation_allow_overwrite_records

  depends_on = [aws_acm_certificate.this]
}

resource "aws_acm_certificate_validation" "this" {
  count = local.create_certificate && var.validation_method != "NONE" && var.validate_certificate && var.wait_for_validation ? 1 : 0

  certificate_arn = aws_acm_certificate.this[0].arn

  validation_record_fqdns = flatten([aws_route53_record.validation.*.fqdn, var.validation_record_fqdns])
}
