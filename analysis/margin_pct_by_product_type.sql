-- Insight #3: How do margin profiles differ between jaffles and beverages?
-- jaffle vs beverage have very different cost structures (food prep vs drinks);
-- comparing margin % and unit-level gross margin guides product mix decisions.
-- avg_margin_pct = avg(gross_margin_per_unit) / avg(revenue_per_unit) per type.

with sales as (
    select * from {{ ref('fct_sales_line') }}
)

select
    product_type,
    count(*) as units_sold,
    count(distinct product_id) as distinct_skus,
    round(avg(revenue_per_unit), 2) as avg_price,
    round(avg(cost_per_unit), 2) as avg_cost,
    round(avg(gross_margin_per_unit), 2) as avg_margin,
    round(sum(gross_margin_per_unit), 2) as total_profit,
    round(avg(gross_margin_per_unit) / nullif(avg(revenue_per_unit), 0) * 100, 2) as avg_margin_pct
from sales
group by 1
order by total_profit desc
