with source as (

    select * from {{ source('raw', 'raw_rankings') }}

),

cleaned as (

    select
        -- Identifiers
        try_cast(ranking_id as varchar) as ranking_id,
        try_cast(edition_year as integer) as edition_year,
        try_cast(edition_id as varchar) as edition_id,
        try_cast(firm_ref as varchar) as firm_ref,
        try_cast(practice_area_id as varchar) as practice_area_id,

        -- Unify the two tier columns from the schema migration.
        -- tier_rank arrived in two formats: plain digits ('0'-'5') and
        -- prefixed strings ('TIER_1'-'TIER_5'). Strip the prefix before
        -- casting. try_cast returns NULL on failure rather than erroring
        -- the whole model, so any unexpected future format degrades
        -- gracefully instead of breaking the pipeline.
        coalesce(
            try_cast(replace(tier_rank, 'TIER_', '') as integer),
            try_cast(ranking_tier as integer)
        ) as ranking_tier,

        -- ranking_type has inconsistent casing/spelling from source system
        -- typos. Normalize known variants to a single canonical value.
        case
            when lower(trim(try_cast(ranking_type as varchar))) in
                ('firm recommended', 'firm reccommended', 'firm_recommended')
                then 'firm recommended'
            when lower(trim(try_cast(ranking_type as varchar))) = 'firm to watch'
                then 'firm to watch'
            else lower(trim(try_cast(ranking_type as varchar)))
        end as ranking_type,

        -- Standardise casing post-migration ('Publish' -> 'publish', etc.)
        lower(trim(try_cast(post_status as varchar))) as post_status,

        lower(trim(try_cast(publication_status as varchar))) as publication_status,
        try_cast(listing_type as varchar) as listing_type,
        try_cast(commentary as varchar) as commentary,
        try_cast(modified_ts as timestamp_ntz) as modified_ts

    from source

),

deduplicated as (

    select *,
        row_number() over (
            partition by ranking_id
            order by modified_ts desc
        ) as rn
    from cleaned

)

select
    ranking_id,
    edition_year,
    edition_id,
    firm_ref,
    practice_area_id,
    ranking_tier,
    ranking_type,
    post_status,
    publication_status,
    listing_type,
    commentary,
    modified_ts

from deduplicated

where rn = 1

    -- Invalid firm_ref: null, literal '0' placeholder, or not present in
    -- the firms master table (orphaned FK from source system).
    and firm_ref is not null
    and firm_ref != '0'
    and firm_ref in (select firm_ref from {{ source('raw', 'raw_firms') }})