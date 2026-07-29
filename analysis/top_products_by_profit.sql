-- Insight #1: Which SKUs drive the most total profit?
-- Group fct_sales_line by product, sum gross_margin_per_unit across all units sold.
-- Returns top 10 products by total profit contribution + their share of overall profit.

with sales as (
    select * from {{ ref('fct_sales_line') }}
),

per_product as (
    select
        product_id,
        product_type,
        count(*) as units_sold,
        sum(revenue_per_unit) as total_revenue,
        sum(gross_margin_per_unit) as total_profit
    from sales
    group by 1, 2
),

total as (
    select sum(total_profit) as grand_total_profit from per_product
)

select
    per_product.product_id,
    per_product.product_type,
    per_product.units_sold,
    round(per_product.total_revenue, 2) as total_revenue,
    round(per_product.total_profit, 2) as total_profit,
    round(per_product.total_profit * 100 / total.grand_total_profit, 2) as pct_of_total_profit
from per_product
cross join total
order by total_profit desc
limit 10
