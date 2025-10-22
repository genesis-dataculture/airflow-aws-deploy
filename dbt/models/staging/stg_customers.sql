{{ config(materialized='view') }}

-- Staging model for customers seed
-- Ensures proper types for Athena/Glue compatibility

with src as (
    select
        cast(customer_id as integer) as customer_id,
        cast(name as varchar) as name,
        cast(signup_date as date) as signup_date
    from {{ ref('customers') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['customer_id']) }} as customer_key,
    customer_id,
    name,
    signup_date,
    extract(year from signup_date) as year,
    extract(month from signup_date) as month,
    cast(current_timestamp as timestamp) as loaded_at
from src
