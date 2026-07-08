-- Grain: one row per ranking_id, same as int__rankings. This is the mart
-- that directly feeds the "Top Tier Firms" client widget (per README), so
-- flags here are deliberately scoped to what that product needs.

with int_rankings as (

    select * from {{ ref('int__rankings') }}

)

select
    edition_year,
    edition_id,
    firm_country,
    firm_city,
    ranking_id,
    firm_ref,
    firm_name,
    practice_area_id,
    practice_group,
    practice_area,
    sub_practice_area,
    ranking_tier,
    ranking_type,
    listing_type,
    commentary,
    post_status,
    publication_status,
    ranking_decision_status,

    -- Published flag: true only when the ranking post is actually live.
    -- Separated from is_top_tier below so both editorial and client-product
    -- consumers can filter independently on publication state alone.
    (post_status = 'publish') as is_published,

    -- Top tier flag: the exact criteria for counting toward the live
    -- "Top Tier Firms" widget. Defined as: tier 0 or 1 (the two highest
    -- ranking tiers), decision status is 'ranked' (not excluded by the
    -- business rules in int__rankings), and the post is actually published.
    -- ASSUMPTION: "top tier" = tiers 0-1. Not specified in the task; this
    -- is the most defensible reading given tier 0 is the highest tier seen
    -- in the source data. Would confirm this threshold with the product
    -- owner in a real scenario.
    (
        ranking_tier in (0, 1)
        and ranking_decision_status = 'ranked'
        and post_status = 'publish'
    ) as is_top_tier,

    modified_ts

from int_rankings
