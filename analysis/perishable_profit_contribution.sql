-- Insight #3: How much of each product's COST is perishable supplies?
-- Every product has at least one perishable supply (eggs, milk, etc.), so a
-- boolean flag is uninformative. Instead, compute the cost-weighted perishable
-- share per product, then aggregate by product_type. Jaffles vs beverages reveal
-- very different spoilage exposure profiles, driving inventory management priorities.

with supplies as (
    select * from {{ ref('stg_jaffle_shop__supplies') }}
),

products as (
    select * from {{ ref('dim_products') }}
),

per_product as (
    select
        product_id,
        sum(case when is_perishable_supply then supply_cost else 0 end) as perishable_cost,
        sum(supply_cost) as total_cost,
        sum(case when is_perishable_supply then supply_cost else 0 end) / nullif(sum(supply_cost), 0) as perishable_share
    from supplies
    group by 1
),

joined as (
    select
        p.product_id,
        p.product_type,
        pp.perishable_cost,
        pp.total_cost,
        pp.perishable_share
    from products p
    left join per_product pp using (product_id)
)

select
    product_type,
    count(*) as distinct_skus,
    round(avg(perishable_share) * 100, 1) as avg_perishable_cost_pct,
    round(min(perishable_share) * 100, 1) as min_perishable_pct,
    round(max(perishable_share) * 100, 1) as max_perishable_pct,
    round(sum(perishable_cost), 2) as total_perishable_cost_per_unit,
    round(sum(total_cost), 2) as total_cost_per_unit
from joined
group by 1
order by avg_perishable_cost_pct desc
