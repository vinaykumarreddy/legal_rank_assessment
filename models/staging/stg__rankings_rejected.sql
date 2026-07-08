-- Captures every ranking row excluded by stg__rankings' validity filter,
-- tagged with a specific rejection_reason. This makes data loss visible
-- and auditable instead of a silent WHERE-clause exclusion — the exact
-- gap that let yesterday's incident go undetected until the client
-- reported it.

with source as (

    select * from {{ source('raw', 'raw_rankings') }}

)

select
    ranking_id,
    firm_ref,
    modified_ts,

    case
        when firm_ref is null then 'null_firm_ref'
        when firm_ref = '0' then 'placeholder_firm_ref'
        else 'orphaned_firm_ref'
    end as rejection_reason,

    current_timestamp() as logged_at

from source

where firm_ref is null
   or firm_ref = '0'
   or firm_ref not in (select firm_ref from {{ source('raw', 'raw_firms') }})
