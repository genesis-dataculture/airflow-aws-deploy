resource "aws_db_subnet_group" "airflow" {
  name       = "airflow-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "Airflow DB Subnet Group"
  }
}

# resource "aws_security_group" "airflow_db" {
#   name        = "airflow-db-sg"
#   description = "Security group for Airflow RDS instance"
#   vpc_id      = var.vpc_id

#   ingress {
#     description = "PostgreSQL from VPC"
#     from_port   = 5432
#     to_port     = 5432
#     protocol    = "tcp"
#     cidr_blocks = ["10.0.0.0/16"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = "airflow-db-sg"
#   }
# }

resource "aws_db_parameter_group" "airflow" {
  family = "postgres17"
  name   = "airflow-postgres17"

  tags = {
    Name = "airflow-postgres17-params"
  }
}

resource "aws_db_instance" "airflow" {
  allocated_storage      = 20
  db_name                = var.db_name
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  username               = var.db_username
  password               = var.db_password
  parameter_group_name   = aws_db_parameter_group.airflow.name
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.airflow.name
  vpc_security_group_ids = var.sg_id
  publicly_accessible    = false

  tags = {
    Name = "airflow-db"
  }
}