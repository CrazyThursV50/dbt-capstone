select sum(lifetime_value)
from {{ ref('dim_customers') }}