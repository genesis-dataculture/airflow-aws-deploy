# Relatório de Status - Projeto Airflow + dbt no ECS/Fargate

**Data:** 21 de Outubro de 2025  
**Projeto:** Integração Airflow + dbt + Athena no AWS ECS/Fargate  
**Status:** Em desenvolvimento - Bloqueio na configuração dbt-athena

---

## Entregas Concluídas

### 1. Infraestrutura AWS
- Cluster Airflow deployado no ECS/Fargate
- Serviços Scheduler e Webserver operacionais
- RDS PostgreSQL configurado (metastore Airflow)
- S3 bucket configurado para logs e staging de dados
- ECR repository com imagem customizada publicada

### 2. Imagem Docker Customizada
- Base: Apache Airflow 2.8.1-python3.10
- dbt-core 1.7.17 instalado
- dbt-athena-community 1.7.2 configurado
- Packages dbt pré-instalados:
  - dbt_utils 1.1.1
  - dbt_expectations 0.10.1
  - dbt_date (latest)
- Git e gosu adicionados para runtime package installation

### 3. Estrutura do Projeto dbt
- Projeto `airflow_athena_project` estruturado
- Models criados:
  - Staging: `stg_example.sql`
  - Marts: `fct_example_summary.sql`
- Sources configurados apontando para Glue Database `raw_data`
- Dados de exemplo carregados:
  - Tabela `raw_data.users` (5 registros)
  - Tabela `raw_data.orders` (5 registros)
- Testes dbt configurados com dbt_expectations

### 4. Permissões e Segurança
- IAM Role `airflow-task-execution-role` com `AdministratorAccess`
- Permissões Lake Formation concedidas:
  - Database `analytics_dev`: DESCRIBE, CREATE_TABLE, ALTER, DROP
  - Database `raw_data`: DESCRIBE, SELECT
  - S3 Bucket: DATA_LOCATION_ACCESS
- Policy customizada `AirflowDbtAthenaPolicy` criada

---

## Desafio Atual - Bloqueio em Produção

### Descrição do Problema

Ao executar a DAG de teste `dbt_athena_example`, ocorre erro persistente na execução do comando `dbt run`:

```
botocore.errorfactory.InvalidRequestException: 
An error occurred (InvalidRequestException) when calling the StartQueryExecution operation: 
Catalog 'analytics_dev' does not exist
```

### Análise Técnica

**Comportamento observado:**
- `dbt debug` executa com sucesso (conexão validada)
- `dbt run` falha ao tentar executar queries no Athena
- O Athena está interpretando o parâmetro `database: analytics_dev` como se fosse um `catalog`

**Configuração atual do `dbt/profiles.yml`:**

```yaml
default:
  target: dev
  outputs:
    dev:
      type: athena
      s3_staging_dir: s3://ons-dev-dg-00-stage/athena-results/dev/
      region_name: us-east-1
      catalog_name: AwsDataCatalog
      database: analytics_dev
      schema: dbt_dev
      work_group: primary
      threads: 4
      aws_profile_name: null
```

**Evidência do problema:**

O log do `dbt debug` mostra:

```log
Connection:
  s3_staging_dir: s3://ons-dev-dg-00-stage/athena-results/dev/
  work_group: primary
  region_name: us-east-1
  database: analytics_dev
  schema: dbt_dev
  poll_interval: 1.0
  # NOTA: catalog_name NÃO aparece nos logs
```

### Tentativas de Correção Realizadas

1. **Adição do parâmetro `catalog_name`**
   - Adicionado `catalog_name: AwsDataCatalog` ao `dbt/profiles.yml`
   - Resultado: Parâmetro não aparece nos logs do `dbt debug`

2. **Validação da infraestrutura**
   - Confirmado que database `analytics_dev` existe no Glue Catalog
   - Confirmado que database `raw_data` existe com tabelas populadas
   - Verificado que CatalogId é `730335315247` (correto)

3. **Rebuild completo da imagem Docker**
   - Executado `docker build --no-cache` múltiplas vezes
   - Upload do `profiles.yml` para S3 antes do build
   - Limpeza de cache do Docker com `docker builder prune -af`

4. **Redeploy dos serviços ECS**
   - Force new deployment no `airflow-scheduler-service`
   - Force new deployment no `airflow-webserver-service`
   - Verificado que containers estão usando nova imagem (digest confirmado)

5. **Teste de permissões Lake Formation**
   - Concedido DESCRIBE, CREATE_TABLE, ALTER, DROP em `analytics_dev`
   - Concedido DESCRIBE, SELECT em `raw_data`
   - Concedido DATA_LOCATION_ACCESS no bucket S3
   - Confirmado via `aws lakeformation list-permissions`

6. **Sincronização S3**
   - Upload manual do `profiles.yml` para S3
   - Verificado que entrypoint.sh sincroniza arquivo a cada 30 segundos
   - Confirmado download no container via CloudWatch logs

### Hipóteses Investigadas

**Hipótese 1: Cache do Docker**
- Status: Descartada após múltiplos rebuilds com `--no-cache`

**Hipótese 2: Ordem de precedência dos parâmetros**
- Status: Em investigação - dbt-athena pode ter precedência interna

**Hipótese 3: Versão do dbt-athena-community**
- Versão atual: 1.7.2
- Documentação oficial não especifica obrigatoriedade de `catalog_name`

**Hipótese 4: Problema na camada COPY do Dockerfile**
- Linha 26-28: `COPY dbt /opt/airflow/dbt`
- Possível cache de layer preservando versão antiga
- Status: Provável causa raiz

---

## Próximos Passos Propostos

### Curto Prazo (Imediato)

1. **Validação do arquivo no container**
   ```bash
   # Extrair profiles.yml diretamente do container em execução
   aws ecs execute-command --cluster airflow-cluster \
     --task <task-arn> \
     --container airflow-scheduler \
     --command "cat /opt/airflow/dbt/profiles.yml"
   ```

2. **Teste com configuração alternativa**
   - Remover `catalog_name` completamente
   - Testar se dbt-athena usa AwsDataCatalog implicitamente

3. **Análise de logs verbose**
   ```bash
   dbt run --profiles-dir . --target dev --debug
   ```

### Médio Prazo (Alternativas)

1. **Modificar Dockerfile para download em runtime**
   ```dockerfile
   # Em vez de COPY, fazer download do S3 no entrypoint
   RUN aws s3 cp s3://ons-dev-dg-00-stage/dbt/profiles.yml /opt/airflow/dbt/
   ```

2. **Usar variáveis de ambiente**
   ```yaml
   # profiles.yml com env vars
   catalog_name: "{{ env_var('DBT_ATHENA_CATALOG') }}"
   ```

3. **Hard-code no dbt_project.yml**
   ```yaml
   # dbt_project.yml
   vars:
     athena_catalog: AwsDataCatalog
   ```

---

## Solicitação de Suporte

Se alguém da equipe já trabalhou com **dbt-athena-community + AWS Glue Catalog**, agradeço insights sobre:

1. **Configuração obrigatória:**
   - O parâmetro `catalog_name` é obrigatório na versão 1.7.2?
   - Existe conflito entre `database` e `catalog_name`?

2. **Troubleshooting:**
   - Como validar que o `profiles.yml` está sendo carregado corretamente?
   - Existe log verbose do dbt-athena mostrando parâmetros parseados?

3. **Alternativas:**
   - Alguma configuração alternativa que force o uso do AwsDataCatalog?
   - Possibilidade de override via `dbt_project.yml` ou variáveis de ambiente?

---

## Resumo Executivo

**Status:** 90% completo - Infraestrutura funcional, dbt instalado, problema isolado na configuração do adaptador dbt-athena.

**Bloqueio:** Parâmetro `catalog_name` não está sendo reconhecido pelo dbt-athena-community, causando erro de interpretação do database como catalog.

**Impacto:** DAG de teste bloqueada, impedindo validação end-to-end da solução.

**Próxima ação:** Investigação detalhada do arquivo `profiles.yml` dentro do container em execução + consulta à documentação oficial do dbt-athena-community.

---

## Anexos Técnicos

### Estrutura do Projeto

```
airflow-docker-i/
├── dbt/
│   ├── profiles.yml              ← Arquivo de configuração com catalog_name
│   ├── dbt_project.yml
│   ├── packages.yml              ← dbt_utils, dbt_expectations, dbt_date
│   └── models/
│       ├── sources.yml           ← Source: raw_data.users, raw_data.orders
│       ├── staging/
│       │   └── stg_example.sql
│       └── marts/
│           └── fct_example_summary.sql
├── docker/
│   ├── Dockerfile                ← COPY dbt /opt/airflow/dbt (linha 26)
│   ├── entrypoint.sh             ← S3 sync a cada 30s
│   └── requirements.txt
└── dags/
    └── dbt_athena_example.py     ← DAG de teste
```

### Comandos Executados

```bash
# 1. Build da imagem
docker build --no-cache -f docker/Dockerfile -t airflow-dbt-athena:latest .

# 2. Tag e push para ECR
docker tag airflow-dbt-athena:latest 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest
docker push 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest

# 3. Force deployment
aws ecs update-service --cluster airflow-cluster --service airflow-scheduler-service --force-new-deployment
aws ecs update-service --cluster airflow-cluster --service airflow-webserver-service --force-new-deployment

# 4. Verificação de logs
aws logs tail /ecs/airflow --since 5m --format short | grep -i "catalog\|database"
```

### Logs Relevantes

```log
[2025-10-21, 16:46:03 UTC] Connection:
[2025-10-21, 16:46:03 UTC]   s3_staging_dir: s3://ons-dev-dg-00-stage/athena-results/dev/
[2025-10-21, 16:46:03 UTC]   region_name: us-east-1
[2025-10-21, 16:46:03 UTC]   database: analytics_dev
[2025-10-21, 16:46:03 UTC]   schema: dbt_dev
[2025-10-21, 16:46:06 UTC]   Connection test: [OK connection ok]

[2025-10-21, 16:46:21 UTC] Failed to execute query.
[2025-10-21, 16:46:21 UTC] botocore.errorfactory.InvalidRequestException: 
  An error occurred (InvalidRequestException) when calling the StartQueryExecution operation: 
  Catalog 'analytics_dev' does not exist
```

---

**Contato:** [Seu Nome/Email]  
**Última atualização:** 21/10/2025 14:00 UTC
