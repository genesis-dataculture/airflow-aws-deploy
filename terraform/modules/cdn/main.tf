resource "aws_cloudfront_distribution" "airflow" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Airflow UI via CloudFront"
  price_class     = var.price_class

  origin {
    domain_name = var.origin_domain_name
    origin_id   = "airflow-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"     # CloudFront -> ALB via HTTP
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "airflow-alb-origin"
    viewer_protocol_policy = "redirect-to-https"  # força HTTPS no edge

    # Airflow UI é dinâmica: permitir todos os métodos e desabilitar cache
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    compress = true

    forwarded_values {
      query_string = true
      headers      = ["*"]  # encaminha todos headers
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # *.cloudfront.net TLS gerenciado
  }
}
