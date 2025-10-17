# Guia de Deploy - Projeto dbt + Athena

Este documento descreve como fazer o deploy do projeto dbt para o ambiente AWS.

## 📦 Estrutura no S3

O projeto dbt deve ser armazenado no S3 na seguinte estrutura:

```
s3://ons-dev-dg-00-stage/
├── dags/                    # DAGs do Airflow (já existente)
├── dbt/                     # Projeto dbt (NOVO)
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── models/
│   │   ├── sources.yml
│   │   ├── staging/
│   │   │   ├── schema.yml
│   │   │   └── stg_example.sql
│   │   ├── intermediate/
│   │   └── marts/
│   ├── macros/
│   ├── tests/
│   ├── seeds/
│   └── snapshots/
└── dbt-data/                # Dados transformados pelo dbt (criado automaticamente)
    ├── staging/
    ├── marts/
    └── seeds/
```

## 🚀 Deploy Inicial

### 1. Upload do Projeto dbt para S3

Execute os seguintes comandos no PowerShell para fazer upload do projeto:

```powershell
# Navegar para o diretório do projeto
cd C:\Users\fabio\Desktop\Genesis\airflow-docker-i

# Upload do projeto dbt para S3
aws s3 sync ./dbt/ s3://ons-dev-dg-00-stage/dbt/ --exclude "target/*" --exclude "dbt_packages/*" --exclude "logs/*"

# Verificar upload
aws s3 ls s3://ons-dev-dg-00-stage/dbt/ --recursive
```

### 2. Upload da DAG de Exemplo

```powershell
# Upload da DAG dbt_athena_example
aws s3 cp ./dags/dbt_athena_example.py s3://ons-dev-dg-00-stage/dags/dbt_athena_example.py

# Verificar upload
aws s3 ls s3://ons-dev-dg-00-stage/dags/
```

## 🔧 Configuração AWS Necessária

### 1. AWS Glue Catalog

Antes de executar o dbt, você precisa criar databases no Glue Catalog:

```bash
# Criar database para ambiente dev
aws glue create-database --database-input '{"Name":"analytics_dev","Description":"Database para dbt development"}'

# Criar database para ambiente prod
aws glue create-database --database-input '{"Name":"analytics_prod","Description":"Database para dbt production"}'

# Criar database para dados brutos (raw data)
aws glue create-database --database-input '{"Name":"raw_data","Description":"Database para dados brutos"}'

# Listar databases
aws glue get-databases
```

### 2. AWS Athena Workgroup

Verificar se o workgroup 'primary' existe:

```bash
# Listar workgroups
aws athena list-work-groups

# Criar workgroup se necessário
aws athena create-work-group \
    --name primary \
    --configuration "ResultConfigurationUpdates={OutputLocation=s3://ons-dev-dg-00-stage/athena-results/}"
```

### 3. Estrutura de Buckets S3

```bash
# Criar estrutura de pastas no S3
aws s3api put-object --bucket ons-dev-dg-00-stage --key dbt/
aws s3api put-object --bucket ons-dev-dg-00-stage --key dbt-data/staging/
aws s3api put-object --bucket ons-dev-dg-00-stage --key dbt-data/marts/
aws s3api put-object --bucket ons-dev-dg-00-stage --key dbt-data/seeds/
aws s3api put-object --bucket ons-dev-dg-00-stage --key athena-results/dev/
aws s3api put-object --bucket ons-dev-dg-00-stage --key athena-results/prod/
aws s3api put-object --bucket ons-dev-dg-00-stage --key raw-data/example/
```

## 🔐 Permissões IAM Necessárias

A IAM Role do ECS Task precisa das seguintes permissões:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "athena:StartQueryExecution",
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "athena:StopQueryExecution",
        "athena:GetWorkGroup"
      ],
      "Resource": "*"
    },
    {
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
        "glue:CreatePartition",
        "glue:UpdatePartition",
        "glue:DeletePartition"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::ons-dev-dg-00-stage",
        "arn:aws:s3:::ons-dev-dg-00-stage/*"
      ]
    }
  ]
}
```

## 🐳 Rebuild do Container Docker

Após atualizar o requirements.txt, você precisa rebuildar a imagem Docker:

```powershell
# Navegar para o diretório docker
cd C:\Users\fabio\Desktop\Genesis\airflow-docker-i\docker

# Build da imagem
docker build -t airflow-dbt-athena:latest .

# Tag para ECR (substitua pelo seu repositório)
docker tag airflow-dbt-athena:latest <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/airflow:dbt-athena

# Login no ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Push para ECR
docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/airflow:dbt-athena
```

## 📋 Variáveis de Ambiente no Terraform

Adicione as seguintes variáveis ao `terraform/modules/ecs/main.tf`:

```terraform
environment = [
  # ... variáveis existentes ...
  
  # dbt + Athena
  { name = "DBT_PROFILES_DIR", value = "/opt/airflow/dbt" },
  { name = "DBT_PROJECT_DIR", value = "/opt/airflow/dbt" },
  { name = "DBT_ATHENA_S3_STAGING", value = "ons-dev-dg-00-stage" },
  { name = "AWS_DEFAULT_REGION", value = "us-east-1" }
]
```

## ✅ Checklist de Deploy

- [ ] Projeto dbt criado localmente
- [ ] Upload do projeto dbt para S3
- [ ] Upload da DAG de exemplo para S3
- [ ] Databases criados no Glue Catalog
- [ ] Workgroup do Athena configurado
- [ ] Estrutura de pastas S3 criada
- [ ] IAM Role atualizada com permissões
- [ ] requirements.txt atualizado
- [ ] Docker image rebuilded e pushed para ECR
- [ ] Variáveis de ambiente configuradas no Terraform
- [ ] Terraform apply executado
- [ ] ECS Task reiniciado

## 🧪 Teste do Deploy

Após o deploy, teste a integração:

1. Acesse a UI do Airflow
2. Verifique se a DAG `dbt_athena_example` aparece
3. Trigger a DAG manualmente
4. Monitore a execução de cada task
5. Verifique os logs no CloudWatch
6. Confirme que as tabelas foram criadas no Glue Catalog:

```bash
# Listar tabelas criadas pelo dbt
aws glue get-tables --database-name analytics_dev

# Query de teste no Athena
aws athena start-query-execution \
    --query-string "SELECT * FROM analytics_dev.stg_example LIMIT 10" \
    --result-configuration "OutputLocation=s3://ons-dev-dg-00-stage/athena-results/test/"
```

## 🔄 Updates Futuros

Para atualizar o projeto dbt após mudanças:

```powershell
# Upload apenas dos arquivos modificados
aws s3 sync ./dbt/ s3://ons-dev-dg-00-stage/dbt/ --exclude "target/*" --exclude "dbt_packages/*"

# O entrypoint.sh irá sincronizar automaticamente no container
# Ou force a re-execução da DAG
```

## 📞 Troubleshooting

### Erro: "Database does not exist"
- Verifique se os databases foram criados no Glue Catalog
- Confirme os nomes em `profiles.yml` e no Glue

### Erro: "Access Denied S3"
- Verifique IAM Role permissions
- Confirme bucket names e paths

### Erro: "dbt command not found"
- Verifique se requirements.txt foi atualizado
- Confirme que a imagem Docker foi rebuilded
- Check logs do container no CloudWatch

### DAG não aparece no Airflow
- Verifique upload para S3
- Confirme sincronização no entrypoint.sh
- Check logs: `AIRFLOW_S3_BUCKET` e `AIRFLOW_S3_DAGS_PATH`

