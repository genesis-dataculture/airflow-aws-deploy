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

### 🔐 Permissões Necessárias (Resumo)

Este projeto requer as seguintes permissões AWS configuradas:

**1. IAM Role: `airflow-task-execution-role`**
- ✅ **AmazonECSTaskExecutionRolePolicy** (managed policy)
  - ECR: Pull de imagens Docker
  - CloudWatch: Escrita de logs
  
- ✅ **AirflowDbtAthenaPolicy** (custom policy - `iam-dbt-policy.json`)
  - **Athena**: StartQueryExecution, GetQueryResults, etc (11 permissões)
  - **Glue Catalog**: CreateTable, UpdateTable, GetDatabase, etc (15 permissões)
  - **S3**: GetObject, PutObject, ListBucket no bucket `ons-dev-dg-00-stage`
  - **CloudWatch Logs**: CreateLogGroup, PutLogEvents

**2. AWS Lake Formation**
- ✅ **Database**: `ALL` permissions no `analytics_dev`
- ✅ **Tables**: `ALL` permissions (TableWildcard) em todas as tabelas
- 📝 Configurado via script: `grant-lakeformation-permissions.ps1`

**3. Terraform (para provisionamento de infraestrutura)**
- ✅ EC2, ECS, RDS, S3, VPC, IAM, ECR, Application Load Balancer
- 📝 Recomendado: AdministratorAccess ou políticas específicas por serviço

**Arquivos de Configuração de Permissões:**
- 📄 `iam-dbt-policy.json` - Política IAM customizada (Athena + Glue + S3)
- 📄 `grant-lakeformation-permissions.ps1` - Script de Lake Formation
- 📄 `terraform/main.tf` - Infraestrutura como código

## Pré-requisitos

- AWS CLI configurada
- Terraform instalado (v1.0.0+)
- Docker instalado
- Permissões na AWS para criar e gerenciar os recursos necessários

## 📁 Estrutura do Repositório

```
airflow-docker-i/
├── dags/                              # Airflow DAGs
│   ├── dbt_athena_example.py         # DAG exemplo com dbt + Athena
│   ├── etl_sample_with_groups.py     # DAG exemplo com TaskGroups
│   └── example_dag.py                # DAG exemplo básico
│
├── dbt/                               # Projeto dbt
│   ├── dbt_project.yml               # Configuração do projeto dbt
│   ├── profiles.yml                  # Conexão Athena (dev/prod)
│   ├── packages.yml                  # dbt_utils + dbt_expectations
│   ├── models/                       # Modelos de transformação
│   │   ├── staging/                  # Camada staging (views)
│   │   └── marts/                    # Camada marts (tables)
│   ├── tests/                        # Testes customizados
│   ├── macros/                       # Macros reutilizáveis
│   ├── seeds/                        # Dados estáticos (CSV)
│   ├── README.md                     # Documentação do projeto dbt
│   ├── PACKAGES_GUIDE.md             # Guia de uso dos packages
│   └── DEPLOY.md                     # Pipeline de deploy dbt
│
├── docker/                            # Configuração Docker
│   ├── Dockerfile                    # Imagem Airflow customizada
│   ├── entrypoint.sh                 # Script de inicialização
│   ├── requirements.txt              # Dependências Python
│   ├── build-and-deploy.ps1          # Script automatizado de build/deploy
│   └── test-image-locally.ps1        # Validação local da imagem
│
├── terraform/                         # Infraestrutura como código
│   ├── main.tf                       # Recursos principais
│   ├── variables.tf                  # Variáveis do Terraform
│   ├── outputs.tf                    # Outputs (URLs, ARNs, etc)
│   ├── providers.tf                  # Configuração AWS provider
│   ├── terraform.tfvars              # Valores das variáveis
│   └── modules/                      # Módulos customizados
│       ├── ecs/                      # ECS Fargate cluster
│       ├── networking/               # VPC, subnets, ALB
│       ├── rds/                      # PostgreSQL database
│       └── s3/                       # S3 buckets
│
├── iam-dbt-policy.json               # Política IAM para dbt + Athena
├── grant-lakeformation-permissions.ps1 # Script de permissões Lake Formation
├── README.md                         # Este arquivo
├── IMPLEMENTATION_COMPLETE.md        # Resumo técnico da implementação
└── IMPLEMENTATION_SUMMARY.md         # Documentação do processo
```

## Configuração e Deploy


### 2. Construir a imagem Docker do Airflow

**IMPORTANTE**: O build deve ser executado da **raiz do projeto** para que o Docker consiga copiar o projeto dbt para a imagem.

```bash
# Da raiz do projeto (não da pasta docker/)
docker build --no-cache -f docker/Dockerfile -t airflow-dbt-athena:latest .
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

**Permissões incluídas na política AirflowDbtAthenaPolicy (`iam-dbt-policy.json`):**

**Athena (AthenaQueryAccess):**
- ✅ `athena:StartQueryExecution` - Iniciar execução de queries
- ✅ `athena:GetQueryExecution` - Obter status de execução
- ✅ `athena:GetQueryResults` - Recuperar resultados de queries
- ✅ `athena:StopQueryExecution` - Cancelar queries em execução
- ✅ `athena:GetWorkGroup` - Acessar configurações do workgroup
- ✅ `athena:ListWorkGroups` - Listar workgroups disponíveis
- ✅ `athena:GetDataCatalog` - Acessar catálogo de dados
- ✅ `athena:GetDatabase` - Obter metadados do database
- ✅ `athena:GetTableMetadata` - Obter metadados de tabelas
- ✅ `athena:ListDatabases` - Listar databases
- ✅ `athena:ListTableMetadata` - Listar metadados de tabelas

**Glue Catalog (GlueCatalogAccess):**
- ✅ `glue:GetDatabase` / `glue:GetDatabases` - Ler databases
- ✅ `glue:GetTable` / `glue:GetTables` - Ler tabelas
- ✅ `glue:CreateTable` - Criar novas tabelas (dbt materializations)
- ✅ `glue:UpdateTable` - Atualizar schema de tabelas
- ✅ `glue:DeleteTable` - Deletar tabelas (drop models)
- ✅ `glue:GetPartition` / `glue:GetPartitions` - Ler partições
- ✅ `glue:CreatePartition` / `glue:BatchCreatePartition` - Criar partições
- ✅ `glue:UpdatePartition` - Atualizar partições
- ✅ `glue:DeletePartition` / `glue:BatchDeletePartition` - Deletar partições
- ✅ `glue:GetTableVersions` - Histórico de versões

**S3 (S3FullAccess no bucket `ons-dev-dg-00-stage`):**
- ✅ `s3:GetObject` - Ler arquivos (DAGs, dbt code, seeds)
- ✅ `s3:PutObject` - Escrever arquivos (resultados Athena, logs)
- ✅ `s3:DeleteObject` - Deletar arquivos
- ✅ `s3:ListBucket` - Listar conteúdo do bucket
- ✅ `s3:GetBucketLocation` - Obter região do bucket
- ✅ `s3:GetBucketVersioning` - Verificar versionamento
- ✅ `s3:ListBucketMultipartUploads` - Gerenciar uploads grandes
- ✅ `s3:AbortMultipartUpload` - Cancelar uploads em progresso

**CloudWatch Logs (CloudWatchLogsAccess):**
- ✅ `logs:CreateLogGroup` - Criar grupos de log
- ✅ `logs:CreateLogStream` - Criar streams de log
- ✅ `logs:PutLogEvents` - Escrever eventos de log
- ✅ `logs:DescribeLogStreams` - Listar streams disponíveis
- 📂 Resource: `/ecs/airflow*` e `/aws/ecs/airflow*`

**Managed Policy (anexada automaticamente):**
- ✅ `AmazonECSTaskExecutionRolePolicy` - Permite ECS:
  - Pull de imagens do ECR
  - Escrita de logs no CloudWatch
  - Acesso a secrets do Secrets Manager (se configurado)

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

### 10. Configurar permissões AWS Lake Formation (IMPORTANTE)

Se os databases/tables do Glue estiverem protegidos por AWS Lake Formation, é necessário conceder permissões explícitas à role `airflow-task-execution-role`:

```powershell
# Execute o script de configuração do Lake Formation
.\grant-lakeformation-permissions.ps1
```

**O que o script faz:**
1. **Database Permissions**: Concede `ALL` no database `analytics_dev`:
   ```json
   {
     "Principal": "arn:aws:iam::730335315247:role/airflow-task-execution-role",
     "Permissions": ["ALL"],
     "Resource": {
       "Database": {
         "Name": "analytics_dev"
       }
     }
   }
   ```

2. **Table Permissions**: Concede `ALL` em todas as tabelas (TableWildcard):
   ```json
   {
     "Principal": "arn:aws:iam::730335315247:role/airflow-task-execution-role",
     "Permissions": ["ALL"],
     "Resource": {
       "Table": {
         "DatabaseName": "analytics_dev",
         "TableWildcard": {}
       }
     }
   }
   ```

**Permissões Lake Formation incluídas em ALL:**
- ✅ `ALTER` - Modificar schema de tabelas
- ✅ `DELETE` - Deletar dados
- ✅ `DESCRIBE` - Ler metadados
- ✅ `DROP` - Deletar tabelas/databases
- ✅ `INSERT` - Inserir dados (dbt materializations)
- ✅ `SELECT` - Consultar dados (queries Athena)
- ✅ `CREATE_TABLE` - Criar novas tabelas (dbt models)

**Alternativa manual (via AWS Console):**
1. Acesse AWS Lake Formation → Databases
2. Selecione `analytics_dev`
3. Actions → Grant
4. Selecione IAM Role: `airflow-task-execution-role`
5. Permissions: `ALL`
6. Repita para Tables com TableWildcard

**Como verificar se Lake Formation está ativo:**
```powershell
# Se retornar erro "AccessDeniedException: Insufficient Lake Formation permission(s)"
aws glue get-database --name analytics_dev

# Então você DEVE executar o script grant-lakeformation-permissions.ps1
```

**Sintoma de permissão faltando**: A DAG `dbt_athena_example` falhará com erro:
```
AccessDeniedException: Insufficient Lake Formation permission(s) on analytics_dev
```

**Por que Lake Formation é necessário?**

Lake Formation adiciona uma camada extra de segurança sobre o Glue Catalog. Mesmo com permissões IAM corretas (`glue:*`), você ainda precisa de permissões Lake Formation explícitas se o database estiver protegido.

**Diferença entre IAM e Lake Formation:**
- ❌ **Apenas IAM**: `glue:GetDatabase` → ✅ Permite AWS API call
- ❌ **Lake Formation ativo**: Mesmo com IAM, precisa de permissão LF → ❌ AccessDeniedException
- ✅ **IAM + Lake Formation**: Ambas permissões concedidas → ✅ Acesso total



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

### ✅ Status da Integração dbt

**Infraestrutura Configurada:**
- ✅ **Packages instalados automaticamente**: dbt_utils (v1.1.1), dbt_expectations (v0.10.1), dbt_date
- ✅ **Conexão Athena**: Funcionando com sucesso
- ✅ **dbt debug**: Todos os checks passaram
- ✅ **Adapter dbt-athena-community**: v1.7.2 configurado
- ✅ **Database Glue Catalog**: `analytics_dev` acessível
- ✅ **Workgroup Athena**: `primary` configurado
- ✅ **Lake Formation**: Permissões ALL concedidas
- ✅ **S3 Staging**: `s3://ons-dev-dg-00-stage/athena-results/dev/`

**Capacidades Habilitadas:**
- 🔧 Modelos dbt prontos para execução (staging → intermediate → marts)
- 🧪 Testes de qualidade de dados com dbt_expectations
- 📊 Materializações em Athena (views, tables, incremental)
- 🔄 Sincronização automática de código dbt a cada 30s
- 📝 Geração de documentação interativa

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

## Troubleshooting

### Problema: dbt_packages não encontrados

**Sintoma**: Erro `ModuleNotFoundError: No module named 'dbt'` ou packages não listados.

**Causa**: Packages dbt são instalados no primeiro startup do container.

**Solução**: 
1. Aguarde 30-60 segundos após o primeiro deploy
2. Verifique os logs do scheduler: `[INFO] Instalando dbt packages (primeira execução)...`
3. Se falhar, force restart: `aws ecs update-service --cluster airflow-cluster --service airflow-scheduler-service --force-new-deployment`

### Problema: Testes dbt falhando com erro de sintaxe

**Sintoma**: `Compilation Error in test ... takes no keyword argument 'column_name'`

**Causa**: Testes `dbt_expectations` mal configurados no `schema.yml`.

**Solução**:
1. Verifique a documentação do dbt_expectations: https://github.com/calogica/dbt-expectations
2. Testes de comparação entre colunas (`expect_column_pair_values_A_to_be_greater_than_B`) devem estar no nível do modelo, não da coluna
3. Use `column_A` e `column_B` (não `column_name`)

### Problema: Permission denied em /opt/airflow/dbt

**Sintoma**: `[Errno 13] Permission denied: '/opt/airflow/dbt/...'`

**Causa**: Diretório dbt pertence ao root, mas Airflow roda como usuário `airflow`.

**Solução**: A correção já está implementada no `entrypoint.sh`:
```bash
chown -R airflow:root /opt/airflow/dbt
chmod -R 775 /opt/airflow/dbt
```

### Problema: Lake Formation AccessDeniedException

**Sintoma**: `Insufficient Lake Formation permission(s) on analytics_dev`

**Solução**:
```powershell
# Executar script de permissões
.\grant-lakeformation-permissions.ps1

# OU manualmente via AWS Console:
# Lake Formation → Databases → analytics_dev → Grant
# Role: airflow-task-execution-role
# Permissions: ALL (database + tables)
```

### Verificando Status do Sistema

```powershell
# 1. Verificar logs do scheduler
aws logs tail /ecs/airflow-scheduler --follow

# 2. Verificar se packages foram instalados
aws ecs execute-command --cluster airflow-cluster --task <task-id> --container airflow-scheduler --command "ls -la /opt/airflow/dbt/dbt_packages/"

# 3. Testar conexão Athena manualmente
aws ecs execute-command --cluster airflow-cluster --task <task-id> --container airflow-scheduler --command "cd /opt/airflow/dbt && dbt debug --profiles-dir . --target dev"

# 4. Ver última sincronização S3
aws logs filter-pattern "[SYNC-DBT]" --log-group-name /ecs/airflow-scheduler --start-time 1h
```

## Limpeza

Para destruir toda a infraestrutura quando não for mais necessária:

```bash
cd terraform
terraform destroy -var-file="terraform.tfvars"
```


