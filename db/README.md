# db — the vault

PostgreSQL, schema `godly`, single tenant, self-hosted on the local cloud.
Tested against PostgreSQL 16.13.

## Apply it

Fresh database:

```bash
createdb godly
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0001_baseline.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0002_roles_and_grants.sql   # optional, needs CREATEROLE
```

`0001_baseline.sql` includes `db/schema.sql` — the baseline is never copied, so
the two cannot drift. Every applied file records itself in
`godly.schema_migrations`.

**Changing the schema after v1:** add `db/migrations/NNNN_what_changed.sql` with
idempotent DDL (`create ... if not exists`, and a `do $$ ... $$` guard around
`alter table ... add constraint`, which has no `if not exists` form), *and* fold
the same change into `schema.sql` so it keeps describing the current shape.
Both files are safe to re-run.

There is no upgrade path from the pre-v1 draft: the identifier strategy changed
(see below). A database built from the old draft should be dropped and reloaded.

## Row Level Security: deliberately not used

RLS is the right default for a Supabase project where browsers talk to Postgres
through PostgREST as `anon`/`authenticated`. None of that is true here: one
company, one tenant, no per-user rows, no direct client connections. Policies
would add a planner filter to every row and protect nothing, and cargo-culted
`using (true)` policies are worse — they read as security while granting
everything. Isolation is done with roles instead, in
`0002_roles_and_grants.sql`: `godly_app` (select/insert/update, **no delete** —
agents mark, they do not erase) and `godly_readonly` for the codex and
`scripts/extract.py`. Revisit this the day a second tenant, a client login, or a
browser-facing connection appears.

## Loading db/seed.json

`scripts/load_seed.py` does all of this in one transaction. It is the loader the
order below describes, not a rewrite of it:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0001_baseline.sql
python scripts/load_seed.py --truncate      # 264 rows across 23 of 24 tables
python scripts/extract.py --list            # reads live Postgres once DATABASE_URL is set
```

Verified on PostgreSQL 16: all three migrations apply and re-apply cleanly, the
seed loads whole, `pipeline_by_stage` returns $355,000 open against $162,400
weighted, and `deployment_board` returns the four client pods with the same
capability counts Chapter I prints — the figures in the book and the figures in
the database are the same figures.

### The order, and why it is that order

The seed is a UI fixture, not a dump: it names things where the database needs
keys. Load it in one transaction, in this order (foreign keys make the order
matter; `set constraints all deferred` covers the one self-reference):

1. `company_profile` — `meta` + `org.principal`
2. `niches` — the four from `meta.niches`, id = slug of the name, plus a
   `cross-niche` row with `is_focus = false` (partners and campaigns use that
   label and it is not one of the four)
3. `departments` — from `org.chiefs`; `name` is the label agents use
   (`Sales`, `Financial`, …), `sort_order` is the doctrine order (CSO first)
4. `supervisors` — `org.chiefs[].supervisor`
5. `agents` — one statement, `set constraints all deferred` so `duo_partner`
   can point at an agent later in the list. `agents.department_code` comes from
   the seed's `chief` field (`CSO`), not its `department` label
6. `deal_stages`, `funnel_stages` — vocabularies with their display order
7. `accounts` — `seed.accounts`, **plus a stub row per account named only by a
   deal** (Ridgeway Restoration, Bluecrest Aesthetics, Halden Guard Group).
   The deal carries the niche, so the stub is derived, not invented; it has no
   `ref` until the codex mints one
8. `contacts` — `seed.contacts`, plus a stub per deal champion with no contact
   row (Ola Nkemdi, Marta Vane, Ivy Halden), attached to their deal's account
9. `deals` — resolve `account` and `contact` names to ids
10. `partners`, `campaigns`, `content_items`
11. `funnel_snapshots`, `department_throughput`
12. `front_office_capabilities`, then `deployments`, then the
    `deployment_capabilities` join — the product, and who is running which
    part of it
12. `integrations`, `brain_map`, `sources`
13. `agent_runs` — last, it references `agents`

Field transformations the loader must do:

| seed | column | note |
|---|---|---|
| `agent_runs[].started` `"2026-09-01 06:02"` | `started_at timestamptz` | no zone in the seed; read as UTC |
| `agent_runs[].cost` `"$0.94"` | `cost_usd numeric` | strip `$` |
| `agent_runs[].id` `"RUN-88401"` | `run_ref` | the primary key is generated |
| `partners[].rev_share` `"15%"` / `"—"` | `rev_share_pct numeric` / `null` | a rate is a number |
| `api_keys[].env` `"— (no public API)"` | `env_var null` | BBB and TruePeopleSearch have no API |
| `api_keys[].limit` | `quota` | `limit` is a reserved word |
| `content[].channel` `"LinkedIn, X"` | `channels text[]` | split on `,` |
| `funnel[].count` | `stage_count` | `count` shadows the aggregate in views |
| `throughput.Research` | `department_code = 'CIO'` | legacy label for Intelligence |
| `throughput.*` (14 values) | 14 days ending on the snapshot date | the seed has no dates |
| `*.niche` names | `niche_id` slug | `"Cross-niche"` → `cross-niche` |
| `accounts[].score` | `fit_score` | |

`agents[].runs_7d` is **not** loaded. It is a display counter; the
`agent_load_7d` view computes the same number from `agent_runs`, and storing it
too would create a second truth that drifts. Expect the dashboard's per-agent
run counts to change after a real load — that is the point.

## Things renamed from the draft (callers must know)

- `agents.department` → `agents.department_code` (it holds `CSO`, not `Sales`;
  the `agent_load_7d` view still exposes it as `department`, and `agent_roster`
  exposes both the code and the label)
- `departments.supervisor_id` → the `supervisors` table
- `funnel_snapshots.count` → `stage_count`
- `partners.rev_share` (text) → `partners.rev_share_pct` (numeric)
- `integrations.quota` now has a generated `usage_pct`
- `accounts`, `contacts`, `deals`, `partners`, `campaigns`, `content_items`,
  `integrations`, `sources` and `agent_runs` are keyed by `bigint` identity;
  their old text ids (`ACC-1041`, `DEAL-901`, …) live on as a unique `ref`.
  The roster (`departments`, `supervisors`, `agents`, `niches`) keeps its
  natural doctrine keys.

## Read models

`pipeline_by_stage`, `agent_load_7d` (both kept from the draft, same column
names), plus `agent_roster` (the org chart in one query), `deal_board` (deals
with the account, contact and owner names the codex prints), `funnel_latest`
(newest snapshot per stage, in funnel order) and `integration_budget` (the
credit warden's 90% sweep). All plain views: at this size a materialized view
would buy nothing and add a refresh to own.
