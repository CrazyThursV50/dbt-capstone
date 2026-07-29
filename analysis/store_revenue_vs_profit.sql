-- Insight #2: Store landscape & revenue concentration.
-- The 16-day data window captures Philadelphia's first two weeks of operation
-- when it was the only open store. The other 5 stores in the catalog opened
-- months/years later. This query shows the resulting 100% revenue concentration
-- and lists planned-but-not-yet-operational stores for strategic context.

with stores as (
    select * from {{ ref('dim_stores') }}
),

sales as (
    select * from {{ ref('fct_sales_line') }}
),

per_store as (
    select
        st.store_id,
        st.store_name,
        st.opened_date,
        count(s.order_item_id) as units_sold,
        round(coalesce(sum(s.revenue_per_unit), 0), 2) as total_revenue,
        round(coalesce(sum(s.gross_margin_per_unit), 0), 2) as total_profit
    from stores st
    left join sales s on st.store_id = s.store_id
    group by 1, 2, 3
)

select
    store_name,
    opened_date,
    units_sold,
    total_revenue,
    total_profit,
    case when total_revenue > 0
         then round(total_revenue * 100 / sum(total_revenue) over (), 2)
         else 0 end as pct_of_total_revenue,
    case when units_sold = 0 then 'Not yet operational in data window' else 'Active' end as status
from per_store
order by opened_date
