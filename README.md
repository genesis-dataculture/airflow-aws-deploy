# Airflow no Amazon ECS com Terraform

Este repositório contém a infraestrutura como código (IaC) para implantar o **Apache Airflow** em contêineres gerenciados pela **Amazon ECS (Fargate)**, com armazenamento de DAGs no **Amazon S3** e integração completa com **dbt + Athena**, permitindo execução automatizada de pipelines de dados.

Toda a configuração é realizada via **Terraform**, e o repositório é autossuficiente — incluindo políticas IAM e scripts de permissões do Lake Formation diretamente neste documento.

---

## Arquitetura

A arquitetura deste projeto inclui:

- **Amazon ECS (Fargate)** — Containers para Airflow Webserver e Scheduler  
- **Amazon RDS (PostgreSQL)** — Banco de dados para metadados do Airflow  
- **Amazon S3** — Armazenamento de DAGs e projeto dbt  
- **Amazon VPC** — Sub-redes públicas e privadas  
- **Amazon ECR** — Armazenamento da imagem Docker personalizada  
- **Application Load Balancer (ALB)** — Exposição do Webserver (porta 8080)  

---

### 🔧 Componentes Principais

- **Webserver:** Interface web do Airflow (`http://load-balancer-dns`)
- **Scheduler:** Agendador e executor das DAGs
- **Sincronização S3:** Atualiza DAGs e projeto dbt a cada 30 segundos
- **Integração dbt:** Com `dbt-core 1.7.17` e `dbt-athena-community 1.7.2`
  - Packages: `dbt_utils`, `dbt_expectations`
  - Execução orquestrada por DAGs
  - Materializações no **AWS Athena + Glue Catalog**

---

## 🔐 Permissões AWS Necessárias

### 1. IAM Role `airflow-task-execution-role`

#### Política IAM customizada (`AirflowDbtAthenaPolicy`)
Abaixo está o conteúdo **integral** da política IAM utilizada:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AthenaQueryAccess",
      "Effect": "Allow",
      "Action": [
        "athena:StartQueryExecution",
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "athena:StopQueryExecution",
        "athena:GetWorkGroup",
        "athena:ListWorkGroups",
        "athena:GetDataCatalog",
        "athena:GetDatabase",
        "athena:GetTableMetadata",
        "athena:ListDatabases",
        "athena:ListTableMetadata"
      ],
      "Resource": "*"
    },
    {
      "Sid": "GlueCatalogAccess",
      "Effect": "Allow",
      "Action": [
        "glue:GetDatabase",
        "glue:GetDatabases",
        "glue:GetTable",
        "glue:GetTables",
        "glue:GetPartition",
        "glue:GetPartitions",
        "glue:CreateTable",
        "glue:UpdateTable",
        "glue:DeleteTable",
        "glue:BatchCreatePartition",
        "glue:CreatePartition",
        "glue:UpdatePartition",
        "glue:DeletePartition",
        "glue:BatchDeletePartition",
        "glue:GetTableVersions"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3FullAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning",
        "s3:ListBucketMultipartUploads",
        "s3:AbortMultipartUpload"
      ],
      "Resource": [
        "arn:aws:s3:::ons-dg-00-dev-stage",
        "arn:aws:s3:::ons-dg-00-dev-stage/*"
      ]
    },
    {
      "Sid": "CloudWatchLogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:*:*:log-group:/ecs/airflow*",
        "arn:aws:logs:*:*:log-group:/aws/ecs/airflow*"
      ]
    }
  ]
}
```

---

### 2. AWS Lake Formation

#### Script PowerShell completo (`grant-lakeformation-permissions.ps1`)

O script abaixo concede permissões `ALL` à IAM Role `airflow-task-execution-role` para o database `analytics_dev` e todas as tabelas do Glue Catalog:

```powershell
# ===========================
# Script: grant-lakeformation-permissions.ps1
# ===========================

$roleArn = "arn:aws:iam::730335315247:role/airflow-task-execution-role"
$databaseName = "analytics_dev"

# 1. Conceder permissões ALL no database
aws lakeformation grant-permissions `
  --principal DataLakePrincipalIdentifier=$roleArn `
  --permissions "ALL" `
  --resource "{""Database"":{""Name"":""$databaseName""}}"

# 2. Conceder permissões ALL em todas as tabelas (TableWildcard)
aws lakeformation grant-permissions `
  --principal DataLakePrincipalIdentifier=$roleArn `
  --permissions "ALL" `
  --resource "{""Table"":{""DatabaseName"":""$databaseName"",""TableWildcard"":{}}}"

# 3. Confirmar concessões aplicadas
Write-Host "Permissões concedidas para $roleArn em $databaseName (Database + TableWildcard)"
```

---

## ⚙️ Configuração e Deploy do Airflow

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 730335315247.dkr.ecr.us-east-1.amazonaws.com

aws ecr create-repository --repository-name airflow-on-ecs-fargate --region us-east-1

docker build --no-cache -f docker/Dockerfile -t airflow-dbt-athena:latest .

docker tag airflow-dbt-athena:latest 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest

docker push 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest
```

Terraform `terraform.tfvars`:

```hcl
db_name = "airflow"
aws_region = "us-east-1"
db_username = "airflow"
db_password = "airflow12345"
iam_role_ecs = "arn:aws:iam::730335315247:role/airflow-task-execution-role"
aws_ecr_repository = "730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest"
airflow_bucket_name = "ons-dg-00-dev-stage"
```

Execução:

```bash
cd terraform
terraform init
terraform apply -var-file="terraform.tfvars"
```

---

## 🚀 Deploy Completo do Projeto dbt + Athena

```bash
aws s3 sync ./dbt/ s3://ons-dg-00-dev-stage/dbt/ --exclude "target/*" --exclude "dbt_packages/*" --exclude "logs/*"
aws s3 cp ./dags/dbt_athena_example.py s3://ons-dg-00-dev-stage/dags/
```

Glue Catalog e Workgroup:

```bash
aws glue create-database --database-input '{"Name":"analytics_dev"}'
aws athena update-work-group --work-group primary --configuration-updates "ResultConfigurationUpdates={OutputLocation=s3://ons-dg-00-dev-stage/athena-results/}"
```

Estrutura S3:

```bash
aws s3api put-object --bucket ons-dg-00-dev-stage --key dbt-data/staging/
aws s3api put-object --bucket ons-dg-00-dev-stage --key dbt-data/marts/
aws s3api put-object --bucket ons-dg-00-dev-stage --key dbt-data/seeds/
aws s3api put-object --bucket ons-dg-00-dev-stage --key athena-results/dev/
aws s3api put-object --bucket ons-dg-00-dev-stage --key athena-results/prod/
```

---

**Autor:** Fabio William Amorim Franco  
**Última atualização:** Outubro de 2025
