with source as (

    select * from {{ source('raw', 'raw_practice_areas') }}

)

select
    try_cast(practice_area_id as varchar) as practice_area_id,
    try_cast(practice_group as varchar) as practice_group,
    try_cast(practice_area as varchar) as practice_area,
    try_cast(sub_practice_area as varchar) as sub_practice_area,
    try_cast(country as varchar) as practice_area_country,
    try_cast(is_active as boolean) as is_active

from source
