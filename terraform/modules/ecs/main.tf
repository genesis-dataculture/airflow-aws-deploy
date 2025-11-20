############################################
# ACM certificate (self-signed files in this folder)
############################################
resource "aws_acm_certificate" "airflow" {
  private_key      = file("${path.module}/airflow-private-key.pem")
  certificate_body = file("${path.module}/airflow-certificate.pem")

  tags = {
    Name        = "airflow-self-signed-certificate"
    Environment = "development"
  }

  lifecycle {
    create_before_destroy = true
  }
}

############################################
# Security Groups
############################################
resource "aws_security_group" "airflow_lb" {
  name        = "airflow-lb-sg"
  description = "Security group for Airflow load balancer"
  vpc_id      = var.vpc_id

  # HTTP for redirect to HTTPS
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS public access
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "airflow-lb-sg"
  }
}

resource "aws_security_group" "airflow_ecs" {
  name        = "airflow-ecs-sg"
  description = "Security group for Airflow ECS tasks"
  vpc_id      = var.vpc_id

  # Allow only from ALB SG on 8080
  ingress {
    description     = "From ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.airflow_lb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "airflow-ecs-sg"
  }
}

# Optional: ensure RDS SG allows 5432 from new ECS SG (uses first ID from provided list)
resource "aws_security_group_rule" "rds_allow_from_airflow_ecs" {
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  security_group_id        = element(var.sg_id, 0)
  source_security_group_id = aws_security_group.airflow_ecs.id
  description              = "Allow Postgres from Airflow ECS tasks"
}

resource "aws_lb" "airflow" {
  # Use a short prefix (max 6 chars) to avoid name collisions if an ALB with the exact name already exists
  name_prefix        = "airfl-"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.airflow_lb.id]
  subnets            = var.private_subnet_ids

  tags = {
    Name = "airflow-alb"
  }
}

resource "aws_lb_target_group" "airflow" {
  # Use a short prefix (max 6 chars) to avoid name collisions for target group names (unique per VPC)
  name_prefix = "airfl-"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    matcher             = "200-299"
  }
}

resource "aws_lb_listener" "airflow" {
  load_balancer_arn = aws_lb.airflow.arn
  port              = 80
  protocol          = "HTTP"

  # Redirect HTTP -> HTTPS
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener (TLS 1.3/1.2) forwarding to target group
resource "aws_lb_listener" "airflow_https" {
  load_balancer_arn = aws_lb.airflow.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.airflow.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.airflow.arn
  }
}

resource "aws_ecs_cluster" "airflow" {
  name = "airflow-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "airflow-ecs-cluster"
  }
}

resource "aws_ecs_task_definition" "airflow_webserver" {
  family                   = "airflow-webserver"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = var.iam_role_ecs
  task_role_arn            = var.iam_role_ecs

  container_definitions = jsonencode([
    {
      name      = "airflow-webserver"
      image     = var.aws_ecr_repository
      essential = true
      command   = ["webserver"]

      environment = [
        { name = "AIRFLOW__CORE__EXECUTOR", value = "LocalExecutor" },
        { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = var.db_connection_string },
        { name = "AIRFLOW__CORE__FERNET_KEY", value = "46BKJoQYlPPOexq0OhDZnIlNepKFf87WFwLbfzqDDho=" },
        { name = "AIRFLOW__CORE__LOAD_EXAMPLES", value = "false" },
        { name = "AIRFLOW__CORE__DAGS_FOLDER", value = "/opt/airflow/dags" },
        { name = "AIRFLOW_CONN_AWS_DEFAULT", value = "aws://" },
        { name = "AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION", value = "false" },
        { name = "AIRFLOW_S3_BUCKET", value = var.s3_bucket_name },
        { name = "AIRFLOW_S3_DAGS_PATH", value = "dags" },
        { name = "AIRFLOW__WEBSERVER__EXPOSE_CONFIG", value = "true" },
        { name = "AIRFLOW__WEBSERVER__RBAC", value = "true" },
        # --- Remote logging S3 (novos) ---
        { name = "AIRFLOW_S3_LOGS_PATH", value = "airflow/logs" },
        { name = "AIRFLOW__LOGGING__REMOTE_LOGGING", value = "true" },
        { name = "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER", value = "s3://${var.s3_bucket_name}/airflow/logs" },
        { name = "AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID", value = "aws_default" },
        { name = "AWS_DEFAULT_REGION", value = "us-east-1" },
        # --- dbt + Athena integration ---
        { name = "DBT_PROFILES_DIR", value = "/opt/airflow/dbt" },
        { name = "DBT_PROJECT_DIR", value = "/opt/airflow/dbt" },
        { name = "DBT_ATHENA_S3_STAGING", value = var.s3_bucket_name },
        { name = "AIRFLOW_S3_DBT_PATH", value = "dbt" },
        # --- HTTPS hardening ---
        { name = "AIRFLOW__WEBSERVER__COOKIE_SECURE", value = "true" },
        { name = "AIRFLOW__WEBSERVER__X_FRAME_ENABLED", value = "true" }
      ],

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ],

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      },

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/airflow"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "webserver"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "airflow_scheduler" {
  family                   = "airflow-scheduler"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "4096"
  execution_role_arn       = var.iam_role_ecs
  task_role_arn            = var.iam_role_ecs

  container_definitions = jsonencode([
    {
      name      = "airflow-scheduler"
      image     = var.aws_ecr_repository
      essential = true
      command   = ["scheduler"]

      environment = [
        { name = "AIRFLOW__CORE__EXECUTOR", value = "LocalExecutor" },
        { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = var.db_connection_string },
        { name = "AIRFLOW__CORE__FERNET_KEY", value = "46BKJoQYlPPOexq0OhDZnIlNepKFf87WFwLbfzqDDho=" },
        { name = "AIRFLOW__CORE__LOAD_EXAMPLES", value = "false" },
        { name = "AIRFLOW__CORE__DAGS_FOLDER", value = "/opt/airflow/dags" },
        { name = "AIRFLOW_CONN_AWS_DEFAULT", value = "aws://" },
        { name = "AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION", value = "false" },
        { name = "AIRFLOW_S3_BUCKET", value = var.s3_bucket_name },
        { name = "AIRFLOW_S3_DAGS_PATH", value = "dags" },
        # --- Remote logging S3 (novos) ---
        { name = "AIRFLOW_S3_LOGS_PATH", value = "airflow/logs" },
        { name = "AIRFLOW__LOGGING__REMOTE_LOGGING", value = "true" },
        { name = "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER", value = "s3://${var.s3_bucket_name}/airflow/logs" },
        { name = "AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID", value = "aws_default" },
        { name = "AWS_DEFAULT_REGION", value = "us-east-1" },
        # --- dbt + Athena integration ---
        { name = "DBT_PROFILES_DIR", value = "/opt/airflow/dbt" },
        { name = "DBT_PROJECT_DIR", value = "/opt/airflow/dbt" },
        { name = "DBT_ATHENA_S3_STAGING", value = var.s3_bucket_name },
        { name = "AIRFLOW_S3_DBT_PATH", value = "dbt" }
      ],

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/airflow"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "scheduler"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "airflow_webserver" {
  name            = "airflow-webserver-service"
  cluster         = aws_ecs_cluster.airflow.id
  task_definition = aws_ecs_task_definition.airflow_webserver.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.airflow_ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.airflow.arn
    container_name   = "airflow-webserver"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.airflow, aws_lb_listener.airflow_https]
}

resource "aws_ecs_service" "airflow_scheduler" {
  name            = "airflow-scheduler-service"
  cluster         = aws_ecs_cluster.airflow.id
  task_definition = aws_ecs_task_definition.airflow_scheduler.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.airflow_ecs.id]
    assign_public_ip = false
  }
}