variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "iam_role_ecs" {
  description = "IAM role for ECS task execution"
  type        = string
}

variable "aws_ecr_repository" {
  description = "ECR repository URL"
  type        = string
}

variable "airflow_bucket_name" {
  description = "S3 bucket name for Airflow DAGs"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "subnet_id" {
  description = "ID da subnet"
  type        = list(string)
}

variable "sg_id" {
  description = "ID do Security Group"
  type        = string
}