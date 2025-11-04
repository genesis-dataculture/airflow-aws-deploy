output "airflow_ui_url" {
  description = "URL para acessar a interface do Airflow"
  value       = "https://${module.ecs.airflow_alb_dns}"
}

# output "s3_bucket_name" {
#   description = "Nome do bucket S3 para armazenar as DAGs do Airflow"
#   value       = module.s3.bucket_name
# }

output "rds_endpoint" {
  description = "Endpoint do banco de dados RDS"
  value       = module.rds.db_instance_endpoint
}