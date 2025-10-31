-- Modelo de exemplo da camada marts (final)
-- Este arquivo demonstra como criar uma tabela analítica final

{{
    config(
        materialized='table',
        schema='marts',
        file_format='parquet',
        location_root='s3://ons-dg-00-dev-stage/dbt-data/marts',
        table_type='hive',
        write_compression='snappy',
        partitioned_by=['year', 'month']
    )
}}

-- Exemplo de agregação para camada marts
-- Substitua pela sua lógica de negócio real

with staging_data as (
    select * from {{ ref('stg_example') }}
),

aggregated as (
    select
        -- Gerar chave sintética para o agregado usando dbt_utils
        {{ dbt_utils.generate_surrogate_key(['year', 'month']) }} as summary_key,
        
        -- Métricas de agregação
        count(*) as total_records,
        count(distinct id) as unique_ids,
        min(created_at) as first_record_date,
        max(created_at) as last_record_date,
        -- Timestamp atual sem timezone (Glue não suporta timestamp with time zone)
        CAST(current_timestamp AS timestamp) as aggregated_at,
        -- Partições DEVEM ser as últimas colunas e na ordem do partitioned_by
        year,
        month
        
    from staging_data
    group by year, month
)

select * from aggregated
