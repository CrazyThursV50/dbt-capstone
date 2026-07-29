select
    order_id,
    customer_id,
    store_id,
    ordered_at,
    order_date,
    subtotal,
    tax_paid,
    order_total

from {{ ref('stg_jaffle_shop__orders') }}
