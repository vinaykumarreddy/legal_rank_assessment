# Answers — Task 5: Monitoring, Freshness & Schema Drift

## 1. Downstream dependency alerting

When `elementary.schema_changes` fires on `stg__rankings`, the alert routes through Elementary's Slack/Teams integration, which includes a direct link to Elementary's lineage view for that model. That view shows every downstream node — `int__rankings`, `fct_firm_rankings`, and any dashboards/exposures declared via `dbt exposure` blocks (e.g. the "Top Tier Firms" widget, declared as an exposure pointing at `fct_firm_rankings`). This means the on-call engineer doesn't have to manually trace dependencies — the alert itself names the affected downstream assets, sourced from dbt's own DAG metadata.

## 2. Alerting tiers

**P1 (page on-call, 24/7):**
- `fct_firm_rankings` row-count floor test fails (< 900 rows) — directly threatens the live "Top Tier Firms" widget
- `elementary.volume_anomalies` fires on `fct_firm_rankings` (severity: error) — e.g. the 15% drop from this incident
- Source freshness `error_after` breach on `raw_rankings`/`raw_submissions` — two consecutive Fivetran syncs missed, SLA at risk

**P2 (Slack/Teams, business hours):**
- Schema drift detected on `stg__rankings` (unless it also triggers a P1 volume anomaly downstream)
- `dbt_expectations` warnings (e.g. `edition_year` out of range) — data hygiene, not correctness
- Source freshness `warn_after` breach — one sync cycle late, still within SLA buffer

**Routing:** P1 → PagerDuty (or equivalent) via Elementary's alerting integration, since it needs to wake someone up. P2 → Slack/Teams webhook only, since Elementary already supports both natively and business-hours triage is sufficient.

## 3. Stale data runbook (07:30 UTC, `fct_firm_rankings` not updated)

1. Check `dbt_source_freshness_results` (Elementary table) to confirm whether the Fivetran sync itself landed on schedule.
2. If sync is late/missing: escalate to the data ingestion/Fivetran on-call — this is not a dbt problem.
3. If sync landed on time: run `dbt run -s +fct_firm_rankings` manually and read the error output directly.
4. Check `elementary_test_results` for the most recent failed test on `stg__rankings` or `int__rankings` — this identifies which layer broke.
5. If a **hard error** (not just a warning) blocked the run, do not force an override — page the model owner listed in the model's `meta` config, since blind data risks repeating this exact incident.

## 4. Pre-ingestion quality gate

Add a Fivetran **webhook-triggered check** immediately after each sync completes, before dbt ever runs: query `information_schema.columns` for `raw_rankings` and diff against a stored expected-schema snapshot. Any mismatch blocks the 06:00 UTC dbt run from starting at all (via a Dagster sensor gating the job) and pages on-call immediately — catching schema drift at the source, before a single transformation runs, rather than discovering it after `dbt test` fails at 06:00.

---

# Answers — Task 6: Incident Diagnosis

## 1. Root cause of each test result

**847 duplicate `ranking_id` (unique test):** The Fivetran log shows exactly "+847 rows synced" on an *incremental* sync. This lines up precisely with the CMS schema migration: the incremental sync picked up existing rankings again because their `tier_rank`/`listing_type` columns changed value (from the old schema to the new one), which looks like an "update" to Fivetran's change-detection logic. Each pre-migration row got re-synced as a new record alongside its original — same `ranking_id`, two rows. The count match (847 duplicates ≈ 847 extra synced rows) is the direct evidence.

**12 null `firm_ref` (not_null test):** These are very likely new rows created by the migration itself — for example, rows using the new `listing_type` field for a category of listing (e.g. sponsored/exclusive) that doesn't map to a traditional ranked firm yet, or firm references pending reconciliation post-migration. The small count (12, vs. 847) suggests a narrow edge case in the new schema, not a systemic ingestion failure.

**34 `post_status` warning (accepted_values test):** Directly caused by the casing change (`'Publish'` → `'publish'`). The test's accepted-values list was written against the pre-migration casing and never updated — a stale test, not a data problem. This is the easiest of the three to fix and lowest risk.

## 2. Steps to restore the 07:00 UTC SLA within 30 minutes

1. Update the `accepted_values` test on `post_status` to the lowercased values immediately — this unblocks the warning-level failure with no data risk (5 min).
2. Apply the `stg__rankings` dedup logic (already built) to strip the 847 duplicate rows — since this model already resolves via `row_number()` on `modified_ts`, rerunning `dbt run` should self-correct this without manual intervention (10 min).
3. For the 12 null `firm_ref` rows: apply the existing staging filter (already excludes null `firm_ref`) and manually flag these 12 rows for the CMS team to investigate post-incident — don't block the whole pipeline for 12 rows out of ~12,847 (5 min).
4. Rerun `dbt run && dbt test` end-to-end and confirm `fct_firm_rankings` row count is back within the expected floor (10 min).

## 3. Architectural change for self-healing

Add the pre-ingestion schema drift gate described in Task 5, Answer 4: a check immediately after each Fivetran sync, before dbt runs, that diffs the source schema against the last-known-good snapshot. If CMS changes a column name or type, the sync is flagged and the 06:00 UTC dbt run is held (not silently run against a changed schema) until a human confirms the staging models have been updated to match — turning "dbt run fails at 6am with cryptic test failures" into "the migration was flagged the night before it could cause damage."
