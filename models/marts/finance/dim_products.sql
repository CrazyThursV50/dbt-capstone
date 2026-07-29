with products as (

    select * from {{ ref('stg_jaffle_shop__products') }}

),

supplies as (

    select * from {{ ref('stg_jaffle_shop__supplies') }}

),

supplies_per_product as (

    select
        product_id,
        sum(supply_cost) as unit_cost,
        max(case when is_perishable_supply then 1 else 0 end) = 1 as has_perishable_supply

    from supplies

    group by 1

),

final as (

    select
        p.product_id,
        p.product_name,
        p.product_type,
        p.product_description,
        p.product_price,
        coalesce(s.unit_cost, 0) as unit_cost,
        p.product_price - coalesce(s.unit_cost, 0) as gross_margin,
        safe_divide(p.product_price - coalesce(s.unit_cost, 0), p.product_price) as margin_pct,
        p.is_food_item,
        p.is_drink_item,
        coalesce(s.has_perishable_supply, false) as has_perishable_supply

    from products p
    left join supplies_per_product s using (product_id)

)

select * from final
