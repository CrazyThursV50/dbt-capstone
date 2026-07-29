with

source as (

    select * from {{ source('jaffle_shop', 'stores') }}

),

renamed as (

    select

        ---------- ids
        id as store_id,

        ---------- text
        name as store_name,

        ---------- numerics
        tax_rate,

        ---------- timestamps
        cast(opened_at as date) as opened_date

    from source

)

select * from renamed
