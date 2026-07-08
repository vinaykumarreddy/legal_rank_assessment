with source as (

    select * from {{ source('raw', 'raw_firms') }}

)

select
    try_cast(firm_ref as varchar) as firm_ref,
    try_cast(firm_name as varchar) as firm_name,
    try_cast(country as varchar) as firm_country,
    try_cast(city as varchar) as firm_city,
    try_cast(established_year as integer) as established_year,
    try_cast(is_active as boolean) as is_active,
    cast(created_at as timestamp_ntz) as created_at,
    cast(updated_at as timestamp_ntz) as updated_at

from source
