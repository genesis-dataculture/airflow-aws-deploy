# Guia de Deploy - Projeto dbt + Athena

Este documento descreve como fazer o deploy do projeto dbt para o ambiente AWS.

## Estrutura no S3

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

## Deploy Inicial

### 1. Upload do Projeto dbt para S3

Execute os seguintes comandos no PowerShell para fazer upload do projeto:

```powershell
# Navegar para o diretório do projeto

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

## Configuracao AWS Necessaria

### 1. AWS Glue Catalog

Antes de executar o dbt, você precisa criar databases no Glue Catalog:

**Metodo 1: Script Automatizado (RECOMENDADO)**

Execute o script PowerShell incluído no projeto:

```powershell
# Executar script de setup
.\setup-glue-databases.ps1
```

O script cria automaticamente os três databases necessários e limpa os arquivos temporários.

**Metodo 2: Comandos Manuais com Arquivos JSON (PowerShell - MAIS CONFIAVEL)**

Devido a limitações do PowerShell com caracteres especiais em JSON inline, o método mais confiável é usar arquivos JSON:

```powershell
# Criar arquivos JSON
@"
{
    "DatabaseInput": {
        "Name": "analytics_dev",
        "Description": "Database para ambiente de desenvolvimento - transformacoes dbt"
    }
}
"@ | Out-File -FilePath analytics_dev.json -Encoding UTF8

@"
{
    "DatabaseInput": {
        "Name": "analytics_prod",
        "Description": "Database para ambiente de producao - transformacoes dbt"
    }
}
"@ | Out-File -FilePath analytics_prod.json -Encoding UTF8

@"
{
    "DatabaseInput": {
        "Name": "raw_data",
        "Description": "Database para dados brutos (raw/landing)"
    }
}
"@ | Out-File -FilePath raw_data.json -Encoding UTF8

# Criar databases usando os arquivos
aws glue create-database --cli-input-json file://analytics_dev.json
aws glue create-database --cli-input-json file://analytics_prod.json
aws glue create-database --cli-input-json file://raw_data.json

# Limpar arquivos temporarios
Remove-Item analytics_dev.json, analytics_prod.json, raw_data.json

# Verificar databases criados
aws glue get-databases --output json | ConvertFrom-Json | Select-Object -ExpandProperty DatabaseList | Where-Object {$_.Name -like 'analytics*' -or $_.Name -eq 'raw_data'} | Format-Table Name, Description
```

**Metodo 3: Bash/Linux/Mac**

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

**Verificar se databases foram criados:**

```powershell
# Metodo visual com PowerShell
aws glue get-databases --output json | ConvertFrom-Json | Select-Object -ExpandProperty DatabaseList | Where-Object {$_.Name -like 'analytics*' -or $_.Name -eq 'raw_data'} | Format-Table Name, Description, CreateTime
```

### 2. AWS Athena Workgroup

O workgroup 'primary' já existe por padrão no Athena, mas precisa ser configurado com o OutputLocation correto.

**Verificar configuração atual:**

```powershell
# Listar workgroups
aws athena list-work-groups

# Verificar configuração do workgroup 'primary'
aws athena get-work-group --work-group primary --output json | ConvertFrom-Json | Select-Object -ExpandProperty WorkGroup | Select-Object Name, State, @{Name='OutputLocation';Expression={$_.Configuration.ResultConfiguration.OutputLocation}}
```

**Atualizar workgroup 'primary' (PowerShell - RECOMENDADO):**

```powershell
# Atualizar OutputLocation do workgroup primary
aws athena update-work-group --work-group primary --configuration-updates "ResultConfigurationUpdates={OutputLocation=s3://ons-dev-dg-00-stage/athena-results/}"

# Verificar atualização
aws athena get-work-group --work-group primary --output json | ConvertFrom-Json | Select-Object -ExpandProperty WorkGroup | Select-Object Name, State, @{Name='OutputLocation';Expression={$_.Configuration.ResultConfiguration.OutputLocation}}
```

**Alternativa Bash/Linux/Mac:**

```bash
# Atualizar workgroup
aws athena update-work-group \
    --work-group primary \
    --configuration-updates "ResultConfigurationUpdates={OutputLocation=s3://ons-dev-dg-00-stage/athena-results/}"

# Verificar
aws athena get-work-group --work-group primary
```

**NOTA:** O workgroup 'primary' já existe por padrão e NÃO pode ser criado novamente. Se precisar criar um workgroup customizado, use um nome diferente.

### 3. Estrutura de Buckets S3

**PowerShell:**

```powershell
# Criar estrutura de pastas no S3 para dbt
aws s3api put-object --bucket ons-dev-dg-00-stage --key dbt-data/staging/
aws s3api put-object --bucket ons-dev-dg-00-stage --key dbt-data/marts/
aws s3api put-object --bucket ons-dev-dg-00-stage --key dbt-data/seeds/

# Criar estrutura para resultados do Athena
aws s3api put-object --bucket ons-dev-dg-00-stage --key athena-results/dev/
aws s3api put-object --bucket ons-dev-dg-00-stage --key athena-results/prod/

# Criar estrutura para dados brutos
aws s3api put-object --bucket ons-dev-dg-00-stage --key raw-data/example/

# Verificar estrutura criada
aws s3 ls s3://ons-dev-dg-00-stage/ --recursive | Select-String -Pattern "dbt-data|athena-results|raw-data"
```

**Bash/Linux/Mac:**

```bash
# Criar estrutura de pastas no S3
aws s3api put-object --bucket ons-dev-dg-00-stage --key dbt-data/staging/
aws s3api put-object --bucket ons-dev-dg-00-stage --key dbt-data/marts/
aws s3api put-object --bucket ons-dev-dg-00-stage --key dbt-data/seeds/
aws s3api put-object --bucket ons-dev-dg-00-stage --key athena-results/dev/
aws s3api put-object --bucket ons-dev-dg-00-stage --key athena-results/prod/
aws s3api put-object --bucket ons-dev-dg-00-stage --key raw-data/example/

# Verificar
aws s3 ls s3://ons-dev-dg-00-stage/ --recursive
```

## Permissoes IAM Necessarias

A IAM Role do ECS Task precisa das seguintes permissoes:

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

## Rebuild do Container Docker

Apos atualizar o requirements.txt, voce precisa rebuildar a imagem Docker:

```powershell
# Navegar para o diretório docker
cd .\docker

# Build da imagem
docker build -t airflow-dbt-athena:latest .

# Tag para ECR (substitua pelo seu repositório)
docker tag airflow-dbt-athena:latest <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/airflow:dbt-athena

# Login no ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Push para ECR
docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/airflow:dbt-athena
```

## Variaveis de Ambiente no Terraform

Adicione as seguintes variaveis ao `terraform/modules/ecs/main.tf`:

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

## Checklist de Deploy

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

## Teste do Deploy

Apos o deploy, teste a integracao:

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

## Updates Futuros

Para atualizar o projeto dbt apos mudancas:

```powershell
# Upload apenas dos arquivos modificados
aws s3 sync ./dbt/ s3://ons-dev-dg-00-stage/dbt/ --exclude "target/*" --exclude "dbt_packages/*"

# O entrypoint.sh ira sincronizar automaticamente no container
# Ou force a re-execucao da DAG
```

## Troubleshooting

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

