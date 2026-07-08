-- Fails when more than 2% of raw_rankings rows are rejected during
-- staging. This is the "would have caught it" check for this incident:
-- a schema migration causing a sudden spike in invalid firm_ref rows
-- gets flagged here before it ever reaches the mart, and routes to the
-- CMS/source team specifically, since they're the ones who can fix it.

{{ config(severity='warn') }}

with counts as (

    select
        (select count(*) from {{ ref('stg__rankings_rejected') }}) as rejected_count,
        (select count(*) from {{ source('raw', 'raw_rankings') }}) as total_count

)

select *
from counts
where rejected_count::float / nullif(total_count, 0) > 0.06
