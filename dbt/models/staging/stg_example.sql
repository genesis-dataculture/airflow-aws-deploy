-- Modelo de staging de exemplo para dbt + Athena
-- Este arquivo demonstra a estrutura básica de um modelo dbt

{{
    config(
        materialized='view',
        schema='staging',
        file_format='parquet'
    )
}}

-- Exemplo de transformação simples de dados brutos
-- Substitua pela sua lógica real quando tiver dados no S3

with source_data as (
    -- Descomente quando tiver a tabela real configurada no Glue Catalog
    -- select * from {{ source('raw', 'example_table') }}
    
    -- Dados de exemplo para teste
    select
        1 as id,
        'example_value' as value,
        cast('2024-01-01' as date) as created_at
),

cleaned as (
    select
        -- Gerar chave sintética usando dbt_utils
        {{ dbt_utils.generate_surrogate_key(['id', 'created_at']) }} as example_key,
        
        id,
        value,
        created_at,
        year(created_at) as year,
        month(created_at) as month,
        
    -- Timestamp atual sem timezone (Glue não suporta timestamp with time zone)
    CAST(current_timestamp AS timestamp) as loaded_at
        
    from source_data
    where created_at is not null
)

select * from cleaned
