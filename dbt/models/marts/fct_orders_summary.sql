{{
  config(
    materialized='table',
    partitioned_by=['year','month'],
    file_format='parquet',
    table_type='hive',
    write_compression='snappy'
  )
}}

-- Fact table summarizing order metrics per year/month

with orders as (
    select * from {{ ref('stg_orders') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['cast(year as varchar)', 'cast(month as varchar)']) }} as summary_key,
    count(*) as total_orders,
    count(distinct customer_id) as unique_customers,
    sum(amount) as total_amount,
    min(order_date) as first_order_date,
    max(order_date) as last_order_date,
    cast(current_timestamp as timestamp) as aggregated_at,
    year,
    month
from orders
where status = 'paid'
group by year, month
order by year, month
