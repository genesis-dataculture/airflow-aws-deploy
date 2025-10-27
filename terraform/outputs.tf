output "airflow_ui_url" {
  description = "URL para acessar a interface do Airflow (via CloudFront HTTPS)"
  value       = "https://${module.cdn.cloudfront_domain_name}"
}

output "cloudfront_domain_name" {
  description = "Domínio do CloudFront (*.cloudfront.net)"
  value       = module.cdn.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "ID da distribuição CloudFront"
  value       = module.cdn.cloudfront_distribution_id
}

output "s3_bucket_name" {
  description = "Nome do bucket S3 para armazenar as DAGs do Airflow"
  value       = module.s3.bucket_name
}

output "rds_endpoint" {
  description = "Endpoint do banco de dados RDS"
  value       = module.rds.db_instance_endpoint
}