with source as (

    select * from {{ source('raw', 'raw_submissions') }}

),

cleaned as (

    select
        try_cast(submission_id as varchar) as submission_id,
        try_cast(firm_ref as varchar) as firm_ref,
        try_cast(practice_area_id as varchar) as practice_area_id,
        try_cast(edition_year as integer) as edition_year,
        try_cast(submission_type as varchar) as submission_type,
        lower(trim(try_cast(submitted_by_email as varchar))) as submitted_by_email,
        try_cast(submitted_at as timestamp_ntz) as submitted_at,
        try_cast(num_referees as integer) as num_referees,
        try_cast(status as varchar) as status,
        try_cast(created_ts as timestamp_ntz) as created_ts

    from source

),

deduplicated as (

    select *,
        row_number() over (
            partition by submission_id
            order by created_ts desc
        ) as rn
    from cleaned

)

select
    submission_id,
    firm_ref,
    practice_area_id,
    edition_year,
    submission_type,
    submitted_by_email,
    submitted_at,
    num_referees,
    status,
    created_ts

from deduplicated

where rn = 1

    -- Invalid firm_ref: null, or not present in the firms master table.
    and firm_ref is not null
    and firm_ref in (select firm_ref from {{ source('raw', 'raw_firms') }})