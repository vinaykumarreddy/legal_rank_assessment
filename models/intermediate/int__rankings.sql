-- Grain: one row per ranking_id (same grain as stg__rankings). This model
-- enriches each ranking with firm/practice-area display names and derives
-- ranking_decision_status; it does not aggregate or fan out rows. firm_ref
-- and practice_area_id are both unique in their respective reference tables
-- (verified during profiling), so these joins cannot duplicate rows.

with rankings as (

    select * from {{ ref('stg__rankings') }}

),

firms as (

    select * from {{ ref('stg__firms') }}

),

practice_areas as (

    select * from {{ ref('stg__practice_areas') }}

),

joined as (

    select
        -- Edition identifiers
        rankings.edition_year,
        rankings.edition_id,

        -- Geography
        firms.firm_country,
        firms.firm_city,

        -- Entity identifiers
        rankings.ranking_id,
        rankings.firm_ref,
        firms.firm_name,
        rankings.practice_area_id,
        practice_areas.practice_group,
        practice_areas.practice_area,
        practice_areas.sub_practice_area,

        -- Ranking attributes
        rankings.ranking_tier,
        rankings.ranking_type,
        rankings.listing_type,
        rankings.commentary,

        -- Status fields
        rankings.post_status,
        rankings.publication_status,

        -- Derived business logic:
        --   firm recommended + tier 0                                  -> not ranked
        --   firm to watch + tier 0 AND post_status != 'publish'        -> not ranked
        --   all other cases                                           -> ranked
        case
            when rankings.ranking_type = 'firm recommended'
                and rankings.ranking_tier = 0
                then 'not ranked'
            when rankings.ranking_type = 'firm to watch'
                and rankings.ranking_tier = 0
                and rankings.post_status != 'publish'
                then 'not ranked'
            else 'ranked'
        end as ranking_decision_status,

        -- Timestamps
        rankings.modified_ts

    from rankings

    left join firms
        on rankings.firm_ref = firms.firm_ref

    left join practice_areas
        on rankings.practice_area_id = practice_areas.practice_area_id

)

select * from joined
