variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "sg_id"{
  description = "ID do Security Group"
  type = list(string)
}

# variable "public_subnet_ids" {
#   description = "IDs das sub-redes públicas"
#   type        = list(string)
# }

variable "private_subnet_ids" {
  description = "IDs das sub-redes privadas"
  type        = list(string)
}

variable "iam_role_ecs" {
  description = "ARN da role IAM para execução de tarefas ECS"
  type        = string
}

variable "aws_ecr_repository" {
  description = "URL do repositório ECR da imagem do Airflow"
  type        = string
}

variable "s3_bucket_name" {
  description = "Nome do bucket S3 para DAGs"
  type        = string
}

variable "db_connection_string" {
  description = "String de conexão com o banco de dados"
  type        = string
  sensitive   = true
}