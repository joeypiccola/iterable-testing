locals {
  name                   = "one.joeypiccola-aws.com"
  iterable_origin_domain = "links.iterable.com"
  route53_zone           = "joeypiccola-aws.com"
  sub_domains            = ["itr-links", "itr-links.dev", "itr-images", "itr-images.dev"]
  fqdns                  = [for k in local.sub_domains : format("%s.${local.route53_zone}", k)]
  tags                   = { app = "iterable" }
}

# get the route53 zone used for CNAME validation and cloud front
data "aws_route53_zone" "route53_zone" {
  name         = local.route53_zone
  private_zone = false
}

# create the cert, use first fqdn in fqdns list as CN and remaining fqdns as SANs
resource "aws_acm_certificate" "acm_certificate" {
  domain_name               = element(local.fqdns, 0)                    # <-- CN
  subject_alternative_names = slice(local.fqdns, 1, length(local.fqdns)) # <-- SANs
  validation_method         = "DNS"
  tags                      = local.tags
}

# loop over each cert domain validation option (dvo) and create the appropriate route53 record
resource "aws_route53_record" "route53_record_validation_cname" {
  for_each = {
    for dvo in aws_acm_certificate.acm_certificate.domain_validation_options : dvo.domain_name => {
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
  zone_id         = data.aws_route53_zone.route53_zone.zone_id
}

# use this fancy resource to watch and wait for the validation proccess to complete
resource "aws_acm_certificate_validation" "certificate_validation" {
  certificate_arn         = aws_acm_certificate.acm_certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.route53_record_validation_cname : record.fqdn]
}

# create a cache policy that disables caching
resource "aws_cloudfront_cache_policy" "cache_policy" {
  name        = "iterable-cache-policy"
  comment     = "Iterable cache policy with caching disabled."
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

# create a origin request policy that forwards everything
resource "aws_cloudfront_origin_request_policy" "origin_request_policy" {
  name    = "iterable-origin-request-policy"
  comment = "Iterable origin request policy that sends cookies, headers, and query strings to the origin."

  cookies_config {
    cookie_behavior = "all"
  }
  headers_config {
    header_behavior = "allViewer"
  }
  query_strings_config {
    query_string_behavior = "all"
  }
}

# create a cloudfront distribution
resource "aws_cloudfront_distribution" "cfd" {
  aliases         = local.fqdns
  enabled         = true
  is_ipv6_enabled = true
  tags            = local.tags

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.acm_certificate.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  origin {
    domain_name = "links.iterable.com"
    origin_id   = "iterable-origin" # this is has no significant, just has to match target_origin_id in default_cache_behavior
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cache_policy_id          = aws_cloudfront_cache_policy.cache_policy.id
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         =  "iterable-origin"
    origin_request_policy_id = aws_cloudfront_origin_request_policy.origin_request_policy.id
    viewer_protocol_policy   = "allow-all"
  }
}

# create CNAME records for cloudfront distribution
resource "aws_route53_record" "route53_record_cfd_cname" {
  for_each = toset(local.fqdns)

  zone_id = data.aws_route53_zone.route53_zone.zone_id
  name    = each.key
  type    = "CNAME"
  ttl     = "300"
  records = [aws_cloudfront_distribution.cfd.domain_name]
}
