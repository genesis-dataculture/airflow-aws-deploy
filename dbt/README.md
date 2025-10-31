# Projeto dbt + Athena para Airflow

Este projeto contém as transformações de dados usando dbt (Data Build Tool) integrado com AWS Athena e orquestrado pelo Apache Airflow.

## 📁 Estrutura do Projeto

```
dbt/
├── models/
│   ├── staging/      # Camada de limpeza e padronização inicial dos dados brutos
│   ├── intermediate/ # Transformações intermediárias (materializadas como ephemeral)
│   └── marts/        # Modelos finais prontos para consumo (analytics, BI)
├── macros/           # Funções SQL reutilizáveis (similar a functions)
├── tests/            # Testes customizados além dos built-in
├── seeds/            # Dados estáticos pequenos (CSVs) para lookup tables
├── snapshots/        # Tabelas SCD Type 2 (slowly changing dimensions)
├── analyses/         # Queries ad-hoc para análise (não materializadas)
├── dbt_project.yml   # Configuração principal do projeto
└── profiles.yml      # Configuração de conexão com Athena
```

## 🚀 Comandos dbt Úteis

### Comandos Básicos

```bash
# Instalar dependências (se tiver packages.yml)
dbt deps

# Compilar modelos sem executar
dbt compile

# Executar todos os modelos
dbt run

# Executar modelos específicos
dbt run --select staging.*
dbt run --select marts.fct_orders

# Executar testes de qualidade
dbt test

# Gerar e visualizar documentação
dbt docs generate
dbt docs serve
```

### Comandos Avançados

```bash
# Executar apenas modelos modificados
dbt run --select state:modified+

# Executar modelo e seus dependentes downstream
dbt run --select stg_orders+

# Executar modelo e suas dependências upstream
dbt run --select +fct_orders

# Debug de conexão
dbt debug

# Limpar arquivos compilados
dbt clean
```

## 🔧 Configuração

### Variáveis de Ambiente Necessárias

- `DBT_ATHENA_S3_STAGING`: Bucket S3 para resultados intermediários do Athena
  - Exemplo: `ons-dg-00-dev-stage`
- `AWS_DEFAULT_REGION`: Região AWS (padrão: `us-east-1`)

### Pré-requisitos AWS

1. **AWS Glue Catalog**: Databases e tabelas devem estar catalogadas
2. **S3 Buckets**:
   - Bucket para dados brutos (raw data)
   - Bucket para resultados do Athena
   - Bucket para modelos dbt materializados
3. **IAM Permissions**:
   - `athena:*` - Permissões de execução de queries
   - `glue:*` - Permissões no Glue Catalog
   - `s3:*` - Permissões nos buckets necessários

## 📊 Fluxo de Dados

```
Raw Data (S3)
    ↓
Glue Catalog (Sources)
    ↓
dbt Staging Models (Views)
    ↓
dbt Intermediate Models (Ephemeral)
    ↓
dbt Marts Models (Tables)
    ↓
Analytics / BI Tools
```

## 🧪 Testes de Qualidade

O dbt oferece testes nativos:
- `unique`: Valores únicos em uma coluna
- `not_null`: Sem valores nulos
- `accepted_values`: Valores permitidos
- `relationships`: Integridade referencial

Exemplo em `sources.yml`:
```yaml
columns:
  - name: order_id
    tests:
      - unique
      - not_null
```

## 📈 Materializações

### View
- Executa a query toda vez que é consultada
- Ideal para: Staging, transformações leves

### Table
- Cria tabela física no S3
- Ideal para: Marts, agregações complexas

### Incremental
- Adiciona apenas novos dados
- Ideal para: Grandes volumes, logs, eventos

### Ephemeral
- Não cria objeto no banco (CTE)
- Ideal para: Transformações intermediárias

## 🔗 Integração com Airflow

Os modelos dbt são executados via DAGs do Airflow localizadas em `/dags`.

Exemplo de execução:
```python
dbt_run = BashOperator(
    task_id='dbt_run',
    bash_command='cd /opt/airflow/dbt && dbt run --profiles-dir . --target prod'
)
```

## 📚 Documentação Adicional

- [dbt Documentation](https://docs.getdbt.com)
- [dbt-athena Adapter](https://github.com/dbt-athena/dbt-athena-adapter)
- [AWS Athena Documentation](https://docs.aws.amazon.com/athena/)

## 🤝 Contribuindo

1. Crie modelos seguindo a estrutura de camadas (staging → intermediate → marts)
2. Adicione testes de qualidade para colunas críticas
3. Documente modelos e colunas no arquivo schema.yml
4. Teste localmente antes de fazer commit: `dbt run && dbt test`
