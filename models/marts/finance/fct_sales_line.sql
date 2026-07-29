with items as (

    select * from {{ ref('stg_jaffle_shop__items') }}

),

orders as (

    select * from {{ ref('stg_jaffle_shop__orders') }}

),

products as (

    select * from {{ ref('dim_products') }}

),

final as (

    select
        i.order_item_id,
        i.order_id,
        i.product_id,
        o.customer_id,
        o.store_id,
        o.ordered_at,
        o.order_date,
        p.product_type,
        p.is_food_item,
        p.is_drink_item,
        p.has_perishable_supply,
        p.product_price as revenue_per_unit,
        p.unit_cost as cost_per_unit,
        p.gross_margin as gross_margin_per_unit

    from items i
    left join orders o on i.order_id = o.order_id
    left join products p on i.product_id = p.product_id

)

select * from final
