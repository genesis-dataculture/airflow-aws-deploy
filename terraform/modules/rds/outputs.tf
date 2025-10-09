output "db_instance_endpoint" {
  description = "Endpoint de conexão da instância de banco de dados"
  value       = aws_db_instance.airflow.endpoint
}

output "db_instance_name" {
  description = "Nome da instância de banco de dados"
  value       = aws_db_instance.airflow.db_name
}

# output "db_security_group_id" {
#   description = "ID do grupo de segurança da base de dados"
#   value       = aws_security_group.airflow_db.id
# }