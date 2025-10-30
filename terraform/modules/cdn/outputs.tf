output "cloudfront_domain_name" {
  description = "Domínio do CloudFront (*.cloudfront.net)"
  value       = aws_cloudfront_distribution.airflow.domain_name
}

output "cloudfront_distribution_id" {
  description = "ID da distribuição CloudFront"
  value       = aws_cloudfront_distribution.airflow.id
}
