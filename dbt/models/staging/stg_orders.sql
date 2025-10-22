{{ config(materialized='view') }}

-- Staging model for orders seed
-- Cleans types and derives partition columns

with src as (
    select
        cast(order_id as integer) as order_id,
        cast(customer_id as integer) as customer_id,
        cast(order_date as date) as order_date,
        cast(amount as double) as amount,
        cast(status as varchar) as status
    from {{ ref('orders') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['order_id']) }} as order_key,
    order_id,
    customer_id,
    order_date,
    amount,
    status,
    extract(year from order_date) as year,
    extract(month from order_date) as month,
    cast(current_timestamp as timestamp) as loaded_at
from src
