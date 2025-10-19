# Guia de Uso dos Packages dbt

Este documento explica como usar os packages `dbt_utils` e `dbt_expectations` instalados no projeto.

## Packages Instalados

### 1. dbt_utils v1.1.1
Funções utilitárias essenciais para transformações de dados.

### 2. dbt_expectations v0.10.1
Testes avançados de qualidade de dados inspirados no Great Expectations.

---

## dbt_utils - Exemplos Práticos

### 1. Gerar Chaves Sintéticas (Surrogate Keys)
```sql
-- Criar uma chave única baseada em múltiplas colunas
{{ dbt_utils.generate_surrogate_key(['customer_id', 'order_date', 'product_id']) }}

-- Exemplo no projeto:
-- models/staging/stg_example.sql
{{ dbt_utils.generate_surrogate_key(['id', 'created_at']) }} as example_key
```

### 2. Timestamp Atual (Cross-database)
```sql
-- Funciona em Athena, Snowflake, BigQuery, etc.
{{ dbt_utils.current_timestamp() }} as loaded_at
```

### 3. Selecionar Todas as Colunas Exceto Algumas
```sql
-- Útil para excluir colunas sensíveis
select
    {{ dbt_utils.star(from=ref('stg_users'), except=["password", "ssn", "credit_card"]) }}
from {{ ref('stg_users') }}
```

### 4. União de Múltiplas Tabelas com Mesma Estrutura
```sql
-- Combinar tabelas de múltiplas regiões
{{ dbt_utils.union_relations(
    relations=[
        ref('sales_us'),
        ref('sales_eu'),
        ref('sales_asia')
    ]
) }}
```

### 5. Pivotar Dados
```sql
-- Transformar linhas em colunas
{{ dbt_utils.pivot(
    column='product_category',
    values=dbt_utils.get_column_values(ref('sales'), 'product_category'),
    agg='sum',
    then_value='revenue'
) }}
```

### 6. Datas Spine (Série de Datas)
```sql
-- Gerar todas as datas entre dois pontos
{{ dbt_utils.date_spine(
    datepart="day",
    start_date="cast('2024-01-01' as date)",
    end_date="current_date"
) }}
```

### 7. Obter Valores Únicos de uma Coluna
```sql
-- Útil para gerar listas dinamicamente
{% set payment_methods = dbt_utils.get_column_values(
    table=ref('payments'),
    column='payment_method'
) %}

-- Usar em condicionais
{% for method in payment_methods %}
    sum(case when payment_method = '{{ method }}' then amount else 0 end) as {{ method }}_total
    {% if not loop.last %},{% endif %}
{% endfor %}
```

---

## dbt_expectations - Testes Avançados

### 1. Valores Dentro de um Range
```yaml
# schema.yml
- name: age
  tests:
    - dbt_expectations.expect_column_values_to_be_between:
        min_value: 0
        max_value: 120
        severity: error

- name: temperature
  tests:
    - dbt_expectations.expect_column_values_to_be_between:
        min_value: -50
        max_value: 60
        row_condition: "country = 'Brazil'"
        severity: warn
```

### 2. Valores em um Conjunto (Whitelist)
```yaml
- name: status
  tests:
    - dbt_expectations.expect_column_values_to_be_in_set:
        value_set: ['pending', 'processing', 'completed', 'cancelled']
        severity: error

- name: priority
  tests:
    - dbt_expectations.expect_column_values_to_be_in_set:
        value_set: [1, 2, 3, 4, 5]
```

### 3. Valores NÃO em um Conjunto (Blacklist)
```yaml
- name: email_domain
  tests:
    - dbt_expectations.expect_column_values_to_not_be_in_set:
        value_set: ['spam.com', 'fake.com', 'test.com']
        severity: warn
```

### 4. Validação com Regex
```yaml
- name: email
  tests:
    - dbt_expectations.expect_column_values_to_match_regex:
        regex: "^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\\.[a-zA-Z0-9-.]+$"
        severity: error

- name: phone
  tests:
    - dbt_expectations.expect_column_values_to_match_regex:
        regex: "^\\+?[1-9]\\d{1,14}$"  # E.164 format

- name: cep
  tests:
    - dbt_expectations.expect_column_values_to_match_regex:
        regex: "^\\d{5}-\\d{3}$"  # CEP brasileiro
```

### 5. Média de Coluna Dentro de um Range
```yaml
- name: order_value
  tests:
    - dbt_expectations.expect_column_mean_to_be_between:
        min_value: 50
        max_value: 500
        severity: warn
```

### 6. Desvio Padrão Dentro de um Range
```yaml
- name: response_time_ms
  tests:
    - dbt_expectations.expect_column_stdev_to_be_between:
        min_value: 0
        max_value: 1000
        severity: warn
```

### 7. Comparação Entre Duas Colunas
```yaml
# A > B
- name: end_date
  tests:
    - dbt_expectations.expect_column_pair_values_A_to_be_greater_than_B:
        column_A: end_date
        column_B: start_date
        or_equal: true
        severity: error

# Exemplo no projeto: total_records >= unique_ids
- dbt_expectations.expect_column_pair_values_A_to_be_greater_than_B:
    column_A: total_records
    column_B: unique_ids
    or_equal: true
```

### 8. Percentual de Valores Não Nulos
```yaml
- name: optional_field
  tests:
    - dbt_expectations.expect_column_proportion_of_unique_values_to_be_between:
        min_value: 0.95
        max_value: 1.0
        severity: warn
```

### 9. Row Count (Nível de Tabela)
```yaml
# No nível do modelo
models:
  - name: fct_sales
    tests:
      # Tabela não pode estar vazia
      - dbt_expectations.expect_table_row_count_to_be_between:
          min_value: 1
          severity: error
      
      # Tabela deve ter no mínimo 1000 registros
      - dbt_expectations.expect_table_row_count_to_be_between:
          min_value: 1000
          max_value: 10000000
          severity: warn
```

### 10. Valores Únicos Compostos
```yaml
# Combinação única de colunas
models:
  - name: fct_orders
    tests:
      - dbt_expectations.expect_compound_columns_to_be_unique:
          column_list: ["customer_id", "order_date", "product_id"]
          severity: error
```

---

## Exemplos Reais do Projeto

### Staging Layer (stg_example.sql)
```sql
with source_data as (
    select * from {{ source('raw_data', 'example') }}
),

cleaned as (
    select
        -- Usando dbt_utils para surrogate key
        {{ dbt_utils.generate_surrogate_key(['id', 'created_at']) }} as example_key,
        
        id,
        value,
        created_at,
        year(created_at) as year,
        month(created_at) as month,
        
        -- Usando dbt_utils para timestamp
        {{ dbt_utils.current_timestamp() }} as loaded_at
        
    from source_data
    where created_at is not null
)

select * from cleaned
```

### Staging Tests (schema.yml)
```yaml
models:
  - name: stg_example
    columns:
      - name: example_key
        tests:
          - unique
          - not_null
      
      - name: id
        tests:
          # Teste básico
          - unique
          - not_null
          # Teste avançado com dbt_expectations
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 1
              max_value: 999999999
              severity: error
      
      - name: month
        tests:
          # Validar mês (1-12)
          - dbt_expectations.expect_column_values_to_be_in_set:
              value_set: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
              severity: error
```

### Marts Layer Tests (schema.yml)
```yaml
models:
  - name: fct_example_summary
    columns:
      - name: unique_ids
        tests:
          # unique_ids não pode ser maior que total_records
          - dbt_expectations.expect_column_pair_values_A_to_be_greater_than_B:
              column_A: total_records
              column_B: unique_ids
              or_equal: true
              severity: error
    
    # Teste no nível da tabela
    tests:
      - dbt_expectations.expect_table_row_count_to_be_between:
          min_value: 1
          max_value: 100000
          severity: error
```

---

## Severidade dos Testes

Configure a severidade conforme a criticidade:

```yaml
severity: error   # Falha o build se o teste falhar
severity: warn    # Aviso, mas não falha o build
```

---

## Executar Testes

```bash
# Todos os testes
dbt test --profiles-dir . --target dev

# Apenas testes de um modelo
dbt test --profiles-dir . --target dev --select stg_example

# Apenas testes de severidade 'error'
dbt test --profiles-dir . --target dev --select test_type:generic,severity:error

# Ver resultados detalhados
dbt test --profiles-dir . --target dev --store-failures
```

---

## Referências

- [dbt_utils Documentation](https://github.com/dbt-labs/dbt-utils)
- [dbt_expectations Documentation](https://github.com/calogica/dbt-expectations)
- [Great Expectations (inspiração)](https://greatexpectations.io/)

---

## Dicas

1. **Use surrogate keys** para todas as tabelas de fatos e dimensões
2. **Adicione testes de range** para valores numéricos e datas
3. **Valide formatos** com regex para emails, telefones, CPF, etc.
4. **Teste relações** entre colunas (datas, quantidades, valores)
5. **Monitore estatísticas** (média, desvio padrão) para detectar anomalias
6. **Use severity=warn** para testes exploratórios e severity=error para críticos
