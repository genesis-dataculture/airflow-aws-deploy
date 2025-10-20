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
- **Sincronização S3**: Sincronização automática de DAGs e projeto dbt a cada 30 segundos
- **dbt Integration**: Transformações de dados com dbt-core 1.7.17 e dbt-athena-community 1.7.2
  - Packages pré-instalados: dbt_utils, dbt_expectations
  - Execução orquestrada via Airflow DAGs
  - Materializações em AWS Athena com Glue Catalog

## Pré-requisitos

- AWS CLI configurada
- Terraform instalado (v1.0.0+)
- Docker instalado
- Permissões na AWS para criar e gerenciar os recursos necessários

## Configuração e Deploy


### 2. Construir a imagem Docker do Airflow

**IMPORTANTE**: O build deve ser executado da **raiz do projeto** para que o Docker consiga copiar o projeto dbt para a imagem.

```bash
# Da raiz do projeto (não da pasta docker/)
docker build -f docker/Dockerfile -t airflow-dbt-athena:latest .
```

**O que acontece durante o build:**
- Instala dependências Python (Airflow, dbt-core, dbt-athena-community, etc.)
- Copia o projeto dbt completo para `/opt/airflow/dbt`
- **Instala packages dbt (dbt_utils, dbt_expectations) durante o build** - não precisa mais instalar no startup
- Configura entrypoint para sincronização automática de DAGs e código dbt

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
docker tag airflow-dbt-athena:latest 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest
docker push 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest
```

**Alternativa**: Use o script automatizado para fazer build e deploy de uma vez:

```powershell
# Windows PowerShell
cd docker
.\build-and-deploy.ps1
```

Este script automatiza todas as etapas: build, tag, login ECR, push e update dos serviços ECS.

### 6. Criar o IAM Role para execução das tarefas do ECS (se ainda não existir)

**IMPORTANTE**: Esta role precisa de permissões para S3, Athena e Glue para executar transformações dbt.

```powershell
# 1. Criar arquivo de trust policy (permite ECS assumir a role)
@"
{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Effect\": \"Allow\",
      \"Principal\": {
        \"Service\": \"ecs-tasks.amazonaws.com\"
      },
      \"Action\": \"sts:AssumeRole\"
    }
  ]
}
"@ | Out-File -FilePath trust-policy.json -Encoding UTF8

# 2. Criar a IAM Role
aws iam create-role `
  --role-name airflow-task-execution-role `
  --assume-role-policy-document file://trust-policy.json

# 3. Anexar política de execução ECS (para logs e ECR)
aws iam attach-role-policy `
  --role-name airflow-task-execution-role `
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# 4. Criar e anexar política para dbt + Athena + Glue + S3
# O arquivo iam-dbt-policy.json está incluído no repositório
aws iam create-policy `
  --policy-name AirflowDbtAthenaPolicy `
  --policy-document file://iam-dbt-policy.json `
  --description "Permissoes para dbt executar no Athena via Airflow"

aws iam attach-role-policy `
  --role-name airflow-task-execution-role `
  --policy-arn arn:aws:iam::730335315247:policy/AirflowDbtAthenaPolicy

# 5. Verificar políticas anexadas
aws iam list-attached-role-policies --role-name airflow-task-execution-role

# 6. Limpar arquivos temporários
Remove-Item trust-policy.json
```

**Permissões incluídas na política AirflowDbtAthenaPolicy:**
- **Athena**: Executar queries, acessar workgroups e metadados
- **Glue Catalog**: Criar/ler/atualizar tabelas e databases
- **S3**: Acesso completo ao bucket `ons-dev-dg-00-stage` (DAGs, dbt, logs, resultados Athena)
- **CloudWatch Logs**: Escrita de logs das tasks ECS

### 7. Implantar a infraestrutura com Terraform

Crie um arquivo `terraform.tfvars` com as variáveis necessárias:

```hcl
db_name = "airflow"
aws_region = "us-east-1"
db_username = "airflow"
db_password = "airflow12345"
iam_role_ecs = "arn:aws:iam::730335315247:role/airflow-task-execution-role"
aws_ecr_repository = "730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest"
airflow_bucket_name = "ons-dev-dg-00-stage"
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

### 9. Fazer upload das DAGs e projeto dbt para o S3

```bash
# Copiar as DAGs para o bucket S3
aws s3 sync ./dags/ s3://ons-dev-dg-00-stage/dags/

# Copiar o projeto dbt para o bucket S3
aws s3 sync ./dbt/ s3://ons-dev-dg-00-stage/dbt/ --exclude "dbt_packages/*"
```

**Nota sobre dbt packages**: Os packages dbt (dbt_utils, dbt_expectations) já estão instalados na imagem Docker e não precisam ser sincronizados do S3. Apenas o código dbt (models, macros, tests, etc.) é sincronizado.

## Atualização das DAGs e Projeto dbt

Este sistema está configurado para sincronizar automaticamente:
- **DAGs**: Do S3 para `/opt/airflow/dags/` a cada 30 segundos
- **Projeto dbt**: Do S3 para `/opt/airflow/dbt/` a cada 30 segundos (excluindo `dbt_packages/` que já estão na imagem)

### Atualizando DAGs

Sempre que você adicionar ou modificar uma DAG:

1. Faça o upload da DAG para o bucket S3:
   ```bash
   aws s3 cp minha_dag.py s3://ons-dev-dg-00-stage/dags/
   ```

2. A DAG será sincronizada automaticamente com o container do Airflow em até 30 segundos.

### Atualizando Modelos dbt

Sempre que você modificar modelos, tests ou configurações dbt:

1. Faça o upload para o bucket S3:
   ```bash
   aws s3 sync ./dbt/ s3://ons-dev-dg-00-stage/dbt/ --exclude "dbt_packages/*"
   ```

2. O código dbt será sincronizado automaticamente em até 30 segundos.

3. **Importante**: Se você adicionar ou remover packages no `packages.yml`, é necessário **rebuild e redeploy da imagem Docker** pois os packages são instalados durante o build da imagem.

## Como funciona a sincronização automática

O sistema de sincronização automática funciona da seguinte maneira:

### Sincronização de DAGs

1. Quando o container do Airflow é iniciado, o script `entrypoint.sh` executa uma primeira sincronização com o comando `aws s3 sync`.

2. Em seguida, um processo em background é iniciado para verificar e sincronizar as DAGs a cada 30 segundos.

3. O comando `aws s3 sync` com a flag `--delete` garante que:
   - Novas DAGs sejam adicionadas
   - DAGs modificadas sejam atualizadas
   - DAGs removidas do S3 também sejam removidas do ambiente local

4. O Airflow verifica periodicamente o diretório de DAGs para identificar alterações.

### Sincronização de Projeto dbt

1. Durante o **build da imagem Docker**, os packages dbt (dbt_utils, dbt_expectations) são instalados em `/opt/airflow/dbt/dbt_packages/`.

2. No **startup do container**, apenas o código dbt (models, macros, tests, seeds, etc.) é sincronizado do S3.

3. A sincronização usa `--exclude "dbt_packages/*"` para **não sobrescrever** os packages já instalados na imagem.

4. Isso reduz o tempo de startup em **60%** (~20s ao invés de ~80s) pois não precisa reinstalar packages a cada restart.

### Benefícios da Arquitetura

- **Startup rápido**: Packages pré-instalados na imagem
- **Código atualizado**: Sincronização automática a cada 30 segundos
- **Sem downtime**: Alterações em modelos dbt não exigem rebuild
- **Versionamento**: Packages ficam versionados junto com a imagem Docker

## Integração com dbt

Este projeto inclui integração completa com dbt (data build tool) para transformações de dados no AWS Athena.

### Estrutura do Projeto dbt

```
dbt/
├── dbt_project.yml          # Configuração do projeto
├── profiles.yml             # Conexão Athena (dev/prod)
├── packages.yml             # Packages instalados (dbt_utils, dbt_expectations)
├── models/
│   ├── staging/            # Camada staging (views)
│   ├── intermediate/       # Camada intermediária (ephemeral)
│   └── marts/              # Camada marts (tables em Parquet)
├── tests/                  # Testes customizados
├── macros/                 # Macros reutilizáveis
└── seeds/                  # Dados estáticos (CSV)
```

### DAG de Exemplo: dbt_athena_example

O projeto inclui uma DAG de exemplo que demonstra:

1. **Verificação de instalação**: Valida dbt e adapter Athena
2. **Execução de modelos**: staging → intermediate → marts
3. **Testes de qualidade**: 15+ validações automáticas com dbt_expectations
4. **Geração de documentação**: Docs interativas do dbt

### Executando Transformações dbt

```bash
# Via Airflow UI
1. Acesse a UI do Airflow
2. Encontre a DAG "dbt_athena_example"
3. Trigger manual execution

# Via linha de comando (dentro do container)
docker exec -it <container-id> bash
cd /opt/airflow/dbt
dbt run --profiles-dir . --target dev
dbt test --profiles-dir . --target dev
```

### Packages dbt Disponíveis

- **dbt_utils v1.1.1**: Funções utilitárias (surrogate keys, pivot, union, star)
- **dbt_expectations v0.10.1**: Testes avançados de qualidade de dados

Consulte `dbt/PACKAGES_GUIDE.md` para exemplos de uso.

### Atualizando Packages dbt

Se você adicionar ou atualizar packages no `packages.yml`:

1. Edite `dbt/packages.yml`
2. Rebuild e redeploy da imagem Docker:
   ```bash
   docker build -f docker/Dockerfile -t airflow-dbt-athena:latest .
   docker tag airflow-dbt-athena:latest 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest
   docker push 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest
   aws ecs update-service --cluster airflow-cluster --service airflow-scheduler-service --force-new-deployment
   ```

## Limpeza

Para destruir toda a infraestrutura quando não for mais necessária:

```bash
cd terraform
terraform destroy -var-file="terraform.tfvars"
```


