-- Modelo de exemplo da camada marts (final)
-- Este arquivo demonstra como criar uma tabela analítica final

{{
    config(
        materialized='table',
        schema='marts',
        file_format='parquet',
        location_root='s3://ons-dev-dg-00-stage/dbt-data/marts',
        table_type='hive',
        write_compression='snappy'
    )
}}

-- Exemplo de agregação para camada marts
-- Substitua pela sua lógica de negócio real

with staging_data as (
    select * from {{ ref('stg_example') }}
),

aggregated as (
    select
        year,
        month,
        count(*) as total_records,
        count(distinct id) as unique_ids,
        min(created_at) as first_record_date,
        max(created_at) as last_record_date,
        current_timestamp as aggregated_at
    from staging_data
    group by year, month
)

select * from aggregated
