select
    store_id,
    store_name,
    tax_rate,
    opened_date,
    date_diff(current_date(), opened_date, year) as store_age_years

from {{ ref('stg_jaffle_shop__stores') }}
