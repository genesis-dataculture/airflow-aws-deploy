# Airflow no Amazon ECS com Terraform

Este repositório contém a infraestrutura como código (IaC) para implantar o Apache Airflow em contêineres gerenciados pela Amazon ECS (Elastic Container Service) usando Fargate, com o armazenamento de DAGs em um bucket S3 e todas as configurações definidas usando Terraform.

## Arquitetura

A arquitetura deste projeto inclui:

- **Amazon ECS (Fargate)**: Para executar o Airflow em contêineres sem a necessidade de gerenciar servidores
  - **Webserver**: Interface web do Airflow (porta 8080)
  - **Scheduler**: Agendador de tarefas do Airflow
- **Amazon RDS (PostgreSQL)**: Para o banco de dados do Airflow
- **Amazon S3**: Para armazenar as DAGs do Airflow
- **Amazon VPC**: Com sub-redes públicas e privadas
- **Amazon ECR**: Para armazenar a imagem personalizada do Airflow
- **Application Load Balancer**: Para distribuir tráfego para o webserver

### 🔧 Componentes Principais

- **Webserver**: Responsável pela interface web (http://load-balancer-dns)
- **Scheduler**: Responsável pelo agendamento e execução de tarefas
- **Sincronização S3**: Sincronização automática de DAGs a cada 30 segundos

## Pré-requisitos

- AWS CLI configurada
- Terraform instalado (v1.0.0+)
- Docker instalado
- Permissões na AWS para criar e gerenciar os recursos necessários

## Configuração e Deploy

### 2. Construir a imagem Docker do Airflow

```bash
cd docker
docker build --no-cache -t airflow-on-ecs-fargate .
```

### 3. Autenticar no Amazon ECR

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 730335315247.dkr.ecr.us-east-1.amazonaws.com
```

### 4. Criar um repositório no ECR (se ainda não existir)

```bash
aws ecr create-repository --repository-name airflow-on-ecs-fargate --region us-east-1
```

### 5. Taguear e enviar a imagem para o ECR

```bash
docker tag airflow-on-ecs-fargate:latest 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest
docker push 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest
```

### 6. Criar o IAM Role para execução das tarefas do ECS (se ainda não existir)

```bash
# Criar a política que permite acesso ao S3
cat > airflow-s3-access-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::airflow-dev-test-install",
        "arn:aws:s3:::airflow-dev-test-install/*"
      ]
    }
  ]
}
EOF

aws iam create-policy --policy-name AirflowS3AccessPolicy --policy-document file://airflow-s3-access-policy.json

# Criar a role
aws iam create-role --role-name airflow-task-execution-role --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

# Anexar políticas à role
aws iam attach-role-policy --role-name airflow-task-execution-role --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam attach-role-policy --role-name airflow-task-execution-role --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
aws iam attach-role-policy --role-name airflow-task-execution-role --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query 'Account' --output text):policy/AirflowS3AccessPolicy
```

### 7. Implantar a infraestrutura com Terraform

Crie um arquivo `terraform.tfvars` com as variáveis necessárias:

```hcl
db_name = "airflow"
aws_region = "us-east-1"
db_username = "airflow"
db_password = "airflow12345"
iam_role_ecs = "arn:aws:iam::730335315247:role/airflow-task-execution-role"
aws_ecr_repository = "730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest"
airflow_bucket_name = "airflow-dev-test-install"
```

Em seguida, execute:

```bash
cd ../terraform
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

### 8. Acessar a interface do Airflow

Após a implantação bem-sucedida, a URL da interface do Airflow estará disponível nos outputs do Terraform. Acesse a URL em um navegador para usar o Airflow. O endereço será exibido como `airflow_ui_url` nos outputs.

```bash
terraform output airflow_ui_url
```

### 9. Fazer upload das DAGs para o S3

```bash
# Copiar as DAGs para o bucket S3
aws s3 sync ./dags/ s3://airflow-dev-test-install/dags/
```

## Atualização das DAGs

Este sistema está configurado para sincronizar automaticamente as DAGs do bucket S3 com o diretório local do Airflow a cada 30 segundos. Sempre que você adicionar ou modificar uma DAG:

1. Faça o upload da DAG para o bucket S3:

   ```bash
   aws s3 cp minha_dag.py s3://airflow-dev-test-install/dags/
   ```
2. A DAG será sincronizada automaticamente com o container do Airflow em até 30 segundos.

## Como funciona a sincronização das DAGs

O sistema de sincronização automática funciona da seguinte maneira:

1. Quando o container do Airflow é iniciado, o script `entrypoint.sh` executa uma primeira sincronização com o comando `aws s3 sync`.
2. Em seguida, um processo em background é iniciado para verificar e sincronizar as DAGs a cada 30 segundos.
3. O comando `aws s3 sync` com a flag `--delete` garante que:

   - Novas DAGs sejam adicionadas
   - DAGs modificadas sejam atualizadas
   - DAGs removidas do S3 também sejam removidas do ambiente local
4. O Airflow verifica periodicamente o diretório de DAGs para identificar alterações.

## Limpeza

Para destruir toda a infraestrutura quando não for mais necessária:

```bash
cd terraform
terraform destroy -var-file="terraform.tfvars"
```
