-- Business rule: every product must have non-negative gross margin.
-- A SKU priced below its supply cost would be a pricing bug or a loss leader
-- requiring explicit business approval. This test fails if any such product exists.

select
    product_id,
    product_name,
    product_price,
    unit_cost,
    gross_margin
from {{ ref('dim_products') }}
where gross_margin < 0
