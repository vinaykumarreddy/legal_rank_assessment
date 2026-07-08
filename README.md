# LegalRank Technical Assessment — Submission

## Overview

This project builds a dbt pipeline for LegalRank's rankings and submissions
data. It takes raw CMS and portal exports and turns them into a clean mart
table (`fct_firm_rankings`) that feeds a client-facing widget. The monitoring
setup is designed around the incident described in the brief: a silent CMS
schema change that caused a 15% drop in the "Top Tier Firms" widget count,
which nobody noticed until the client did.

**Stack used:** dbt Core, Snowflake (trial account), Elementary,
dbt_utils, dbt_expectations.

## Project structure
models/
staging/       stg__rankings, stg__submissions, stg__firms, stg__practice_areas
intermediate/  int__rankings
marts/         fct_firm_rankings
seeds/           raw CSVs, loaded via dbt seed into the raw schema
ANSWERS.md       written answers for Tasks 5 and 6

## Key decisions and why I made them

**Invalid `firm_ref` (Task 1 & 2):** I treated a row as invalid if `firm_ref`
was null, was the literal text `'0'` (looks like a placeholder value, only
seen in rankings), or didn't match any firm in `raw_firms`. I found all
three patterns while checking the data, and I filter them the same way in
both `stg__rankings` and `stg__submissions`.

**Two tier columns (Task 1):** After the CMS change, `tier_rank` started
showing up in two formats — plain numbers (`'0'`-`'5'`) and text with a
prefix (`'TIER_1'`-`'TIER_5'`). I strip off the `TIER_` part first, then
combine it with the old `ranking_tier` column so every row ends up with one
clean tier value. I used `TRY_CAST` everywhere so if a value can't be
converted, it just becomes empty (NULL) instead of breaking the whole run.

**`ranking_type` spelling issues (Task 1):** I found this myself while
checking the data — it wasn't mentioned in the task. Some rows had typos
like `firm reccommended` or `firm_recommended`. I fixed the spelling instead
of removing those rows, because removing them would mean losing real
ranking data for no good reason. This mattered because later, in Task 3,
the business logic checks this column for an exact match.

**Removing duplicate rows:** For both `stg__rankings` and `stg__submissions`,
when the same ID showed up more than once, I kept only the newest one (based
on the last-updated timestamp). While checking `raw_rankings`, I actually
found two different reasons for duplicates — one caused by the schema
migration (same row saved under both the old and new format), and one that
looked like a separate, unrelated sync issue. Both get fixed by the same
logic.

**What counts as "top tier" (Task 4):** The task didn't say exactly what
"top tier" means, so I made a call: tier 0 or 1 (the two highest tiers),
plus the ranking must count as "ranked," plus the post must be published.
This is my best guess based on the data. In a real job, I'd check this with
whoever owns the widget before shipping it.

**Minimum row count (Task 4):** I set the floor at 900 rows for
`fct_firm_rankings`. This is based on what we actually see today (around
914 ranked rows), leaving a small buffer for normal changes, while still
catching a big drop — like the 15% drop in the incident — before it reaches
the widget.

**Freshness time limits (Task 5A):** I worked these out from the real sync
schedule mentioned in the brief — Fivetran syncs at 20:00 and 02:00 UTC,
and the mart needs to be ready by 07:00 UTC. So: warn after 6 hours (the
02:00 sync is probably late), error after 10 hours (both the 02:00 and the
earlier 20:00 sync are missing). Since this project uses fixed sample data
instead of a live feed, the freshness check correctly shows "stale" — that's
expected, not a mistake.

**Why we fix the capital letters in `post_status`:** The CMS sent this
column with mixed capital letters — `'Publish'` and `'publish'` were being
treated as two different values by mistake, even though they mean the same
thing. If we didn't fix this, reports could miss or double-count rankings
just because of a capital letter — not a real difference. So we lowercase
everything while cleaning the data, then run a simple check afterward to
confirm only the three expected values (publish, draft, pending) are left.
This also catches if the CMS ever adds a brand-new status we don't know
about yet.

**Why `publication_status` is not the same as `post_status`:** These look
similar but answer two different questions. `post_status` answers "is this
post actually live on the website?" `publication_status` answers "where is
this ranking in our internal editorial work — still being researched,
being worked on, or archived?" A ranking could be "researching" internally
while its post is still in "draft" — two separate things being tracked, not
the same thing written twice.

**Why I clean duplicates in staging, not in the raw data:** Raw data is
meant to be the original truth — if I change it there, I lose the ability
to go back and see exactly what the source actually sent. Staging is also
where I already check for schema changes and missing values, so keeping the
duplicate-cleanup in the same place keeps all my "make this data trustworthy"
work together in one spot. Raw stays untouched as an honest record of what
came in.

**Why I added a control/log table for rejected rows:** Instead of just
quietly dropping invalid rows, I built a separate table that keeps them,
along with a reason code for why each one was rejected. Here's why this
matters in practice: if the source team says they sent 10,000 records, and
the client expects that same count, someone is going to ask "why did we
only get 9,500?" Without a log, nobody could answer that. With this table,
I can hand back the exact list of rejected records and the reason for each
one, so the source team has something real to look into instead of just a
number that doesn't match.

**Why I check data volume at the mart level, not just staging:** I added
volume checks at two different points because each one catches a different
kind of problem. At staging, we already remove bad rows on purpose — so if
10,000 records come in and 500 get rejected, that's expected, not a
surprise. But after that, the remaining 9,500 rows go through joins and
business rules in later steps, and that number can drop again — say down to
9,000 — for reasons staging never sees, like a join not matching properly.
If nothing checks volume at the mart level, that second drop goes completely
unnoticed, even though it's the number that actually reaches the client. The
mart-level check exists just to catch that second, quiet drop.

**Why I used `COALESCE` for the tier columns:** After the CMS change, tier
information ended up split across two columns — `ranking_tier` for old rows,
`tier_rank` for new rows — and they never both have a value at the same
time. `COALESCE` picks whichever column actually has a value: it checks the
new column first, and if that's empty, falls back to the old one. This gives
one clean, single tier value no matter which schema a row originally came
from.

**Why I used `TRY_CAST` instead of just `CAST`:** With a normal `CAST`, if a
value can't convert to the expected type, the whole pipeline fails and stops
right there. With `TRY_CAST`, if a value can't convert, it just becomes
empty (NULL) instead of crashing — and the rest of the pipeline keeps
running. For example, the `tier_rank` column has values like `'0'`, `'1'`,
but also `'TIER_1'`, `'TIER_2'`. A plain `CAST` would break the moment it
hit `'TIER_1'`, since that's text, not a number. `TRY_CAST` lets it move
past that safely, so I can review and fix any bad values afterward instead
of the whole run stopping.

**Why I renamed `country` to `practice_area_country`:** Both `raw_firms`
and `raw_practice_areas` have a column called `country`, but they mean
different things — one is the firm's country, the other is the country a
practice area applies to. Since these two tables get joined together later,
keeping both named just `country` would cause an ambiguous-column error in
Snowflake — it wouldn't know which one you meant. So I renamed them to be
specific: `firm_country` and `practice_area_country`.

**Why I only added freshness checks to 2 of the 4 raw tables:** I only set
up freshness and schema-drift monitoring on `raw_rankings` and
`raw_submissions`, not all four tables. These two are the only ones that
actually sync on a schedule — Fivetran loads them at fixed times, and each
has a timestamp column showing when a row last changed. They're also the
two tables where the actual incident happened. `raw_firms` and
`raw_practice_areas` are just reference/master data — they barely change,
so a freshness check on them wouldn't mean anything; there's no expected
time for them to update by. Adding the same monitoring to all four would
just be noise, not a real signal.

## Known limitations / what I'd add with more time

- No CI/CD pipeline set up (e.g. GitHub Actions running `dbt build` on
  every pull request) — I'd add this with more time.
- Elementary's volume anomaly check needs some history of past runs before
  it can properly detect anything unusual; on this first run it correctly
  says "not enough data" rather than giving a false result. In a real job,
  this would build up a baseline after the first few days.
- I didn't set up Dagster (mentioned as part of the production stack) —
  this project runs through the dbt command line directly. I explain how
  Dagster asset checks would fit in inside `ANSWERS.md`.
- I set up Snowflake roles and warehouses manually for this trial account;
  in a real job I'd manage this through Terraform instead.

## How to run this project

```bash
dbt deps
dbt seed
dbt run
dbt test
dbt source freshness
```

Everything passes with zero errors (`dbt run && dbt test`). A few warnings
show up on purpose — see below for what they are and why they're expected.

## Architecture: before and after

**Current state** — how the assessment data actually behaves: invalid
`firm_ref` rows get quietly dropped in a `WHERE` clause, with no record kept
and no alert sent. The only way anyone finds out is the client noticing the
widget count looks wrong — which is exactly what happened in the incident
this assessment is based on.

![Current state: silent drop](docs/architecture-current-state.svg)

**What I'd improve** — a control/log table (`stg__rankings_rejected`) keeps
every rejected row along with a reason code, and a threshold check
(`assert_rejection_rate_below_threshold`) fires a warning if more than 2% of
rows get rejected, sending an alert to the CMS/source team before the mart
or the widget are affected. This goes beyond what the task asked for — see
`models/staging/stg__rankings_rejected.sql` and
`tests/assert_rejection_rate_below_threshold.sql`.

![Proposed state: control table with threshold alert](docs/architecture-proposed-state.svg)

## Test warnings — what they are and why they're expected

Running `dbt test` gives 35 passing and 3 warnings, zero errors. Here's
what each warning is:

1. **7 rows with badly formatted emails** in `stg__submissions` — a data
   hygiene issue, not something that breaks the pipeline logic.
2. **Recency check warning** on `stg__rankings` — expected, since this
   project uses fixed sample data instead of a real, live daily feed.
3. **Rejection rate warning** — this checks whether more than 2% of
   `raw_rankings` rows got rejected due to invalid `firm_ref`. On this
   dataset, the real rejection rate is about 5.4% (56 invalid rows out of
   1,040), so it correctly fires. I set this to `warn` rather than `error`
   since it's an extra check I added beyond the task requirements, showing
   the alert logic works — not a required pipeline gate. This is the same
   type of problem (a sudden spike in bad rows) as the incident in the
   brief — this check proves it would get caught here automatically,
   instead of reaching the client first.

To see the exact breakdown behind that number:
```sql
SELECT rejection_reason, COUNT(*)
FROM legalrank.staging.stg__rankings_rejected
GROUP BY rejection_reason;
```
## Test results

Running `dbt test` gives:

Zero errors, 3 warnings. Here's what each warning is and why it's expected:

1. **7 rows with badly formatted emails** in `stg__submissions` — a data
    issue, not something that breaks the pipeline logic.

2. **Recency check warning** on `stg__rankings` — expected, since this
   project uses fixed sample data instead of a real, live daily feed.
   
3. **Rejection rate warning** — checks whether more than 2% of
   `raw_rankings` rows got rejected due to invalid `firm_ref`. On this
   dataset, the real rejection rate is about 5.4% (56 invalid rows out of
   1,040), so it correctly fires. This is the same type of problem (a
   sudden spike in bad rows) as the incident in the brief — this check
   proves it would get caught here automatically, instead of reaching the
   client first.

To see the exact breakdown behind the rejection rate:
```sql
SELECT rejection_reason, COUNT(*)
FROM legalrank.staging.stg__rankings_rejected
GROUP BY rejection_reason;
```
Note : In Docs added architecture diagram with design change
