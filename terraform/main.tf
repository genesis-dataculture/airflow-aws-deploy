# module "networking" {
#   source = "./modules/networking"
# }
# module "networking" {
#   source = "./modules/networking"
# }

# module "s3" {
#   source              = "./modules/s3"
#   airflow_bucket_name = var.airflow_bucket_name
# }

module "rds" {
  source      = "./modules/rds"
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_id
  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password
  sg_id       = [var.sg_id]

}

module "ecs" {
  source = "./modules/ecs"
  vpc_id = var.vpc_id
  # public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids   = var.subnet_id
  iam_role_ecs         = var.iam_role_ecs
  aws_ecr_repository   = var.aws_ecr_repository
  s3_bucket_name       = var.airflow_bucket_name
  db_connection_string = "postgresql://${var.db_username}:${var.db_password}@${module.rds.db_instance_endpoint}/${var.db_name}"
  sg_id                = [var.sg_id]
}