-- Godly Base — operating schema for the local cloud (PostgreSQL 15+, tested on 16).
-- Schema: godly.  Every table in the OS Data module is one of these.
-- Secrets are NEVER stored here: the integrations table holds env var NAMES and
-- usage counters, never values.
--
-- This file is the authoritative baseline (v1) for a *fresh* database. Every
-- change after v1 ships as db/migrations/NNNN_*.sql AND is folded back into this
-- file, so `schema.sql` always describes the current shape. See db/README.md.
--
-- Conventions applied throughout (Supabase Postgres guidance):
--   * lowercase snake_case identifiers only — never quoted mixed case.
--   * timestamptz for instants, date for calendar days; never bare timestamp.
--   * numeric for money and rates; never float, never text.
--   * text (unbounded) for strings; length limits are CHECKs when they are real.
--   * bigint GENERATED ALWAYS AS IDENTITY for tables that grow without bound;
--     natural text keys only for the fixed doctrine roster and vocabularies.
--   * every foreign key column carries an index (Postgres does not add one).
--   * explicit ON DELETE on every foreign key — no silent NO ACTION by accident.
--
-- Row Level Security is deliberately NOT enabled anywhere. This is a
-- single-tenant, self-hosted database with no anon/authenticated PostgREST roles
-- and no per-user rows: RLS here would be policy theatre that costs a planner
-- filter per row and hides nothing. Isolation is done with roles and grants
-- instead — see db/migrations/0002_roles_and_grants.sql. If Godly Base ever
-- serves a second tenant or exposes Postgres to a browser, revisit this.

CREATE SCHEMA IF NOT EXISTS godly;
SET search_path TO godly, public;

-- ------------------------------------------------------------- housekeeping
-- Applied-migration ledger. Written by the migration runner, read by humans.
CREATE TABLE IF NOT EXISTS schema_migrations (
  version     text PRIMARY KEY,              -- '0001_baseline'
  applied_at  timestamptz NOT NULL DEFAULT now(),
  note        text
);

-- One trigger function for every updated_at column; search_path is pinned to ''
-- so the function cannot be hijacked by a caller's search_path.
CREATE OR REPLACE FUNCTION godly.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------- the seat
-- Single-row table: the company's own facts and the one human seat. The CHECK on
-- a boolean primary key is the standard way to make "exactly one row" a
-- constraint rather than a convention.
CREATE TABLE IF NOT EXISTS company_profile (
  id              boolean PRIMARY KEY DEFAULT true CHECK (id),
  company_name    text NOT NULL,
  founded_year    smallint NOT NULL CHECK (founded_year BETWEEN 1900 AND 2200),
  brain_uri       text NOT NULL,             -- 'Obsidian vault @ /brain (MCP)'
  principal_name  text NOT NULL,
  principal_role  text NOT NULL,
  principal_note  text,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------- reference
CREATE TABLE IF NOT EXISTS niches (
  id            text PRIMARY KEY,            -- stable slug: 'roofing-restoration'
  name          text NOT NULL UNIQUE,        -- UNIQUE because the seed and the UI join on the display name
  is_focus      boolean NOT NULL DEFAULT true,  -- doctrine: exactly four served in depth; 'cross-niche' is a bucket, not a niche
  playbook_path text UNIQUE,                 -- /brain/niches/<slug>.md — one playbook cannot serve two niches
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------- the roster
-- The roster is fixed by doctrine (7 departments, 7 supervisors, 21 agents) and
-- its identifiers ('CSO', 'SUP-SALES', 'AG-SALES-01') are written into
-- config/agents.yaml, vault notes and memory paths. Natural text keys are the
-- right call here: the set is capped, the keys are stable, and every join reads
-- as the doctrine reads. Growing tables below use surrogate bigint keys instead.
CREATE TABLE IF NOT EXISTS departments (
  code          text PRIMARY KEY CHECK (code = upper(code) AND code <> ''),  -- CSO, CMO, CBDO, CTO, CIO, CCO, CFO
  name          text NOT NULL UNIQUE,        -- 'Sales' — the label the seed and OS show
  title         text NOT NULL,               -- 'Chief Sales Officer'
  chief_name    text NOT NULL,               -- 'Ledger'
  charter       text NOT NULL,
  sort_order    smallint NOT NULL UNIQUE,    -- org-chart order is doctrine (CSO first), not alphabetical
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Supervisors live in their own table rather than as departments.supervisor_id:
-- that column was an unenforced text reference and made departments/agents a
-- circular pair. One supervisor per department is enforced by the UNIQUE on
-- department_code.
CREATE TABLE IF NOT EXISTS supervisors (
  id              text PRIMARY KEY,          -- SUP-SALES
  department_code text NOT NULL UNIQUE REFERENCES departments(code) ON DELETE RESTRICT,
  name            text NOT NULL,
  cadence         text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  -- Redundant as a key, but a composite FK target must be UNIQUE: it is what
  -- lets agents prove they report to their own department's supervisor.
  UNIQUE (id, department_code)
);

CREATE TABLE IF NOT EXISTS agents (
  id              text PRIMARY KEY,          -- AG-SALES-01
  name            text NOT NULL,
  department_code text NOT NULL REFERENCES departments(code) ON DELETE RESTRICT,
  reports_to      text NOT NULL,             -- supervisor id; integrity via the composite FK below
  -- The double-agent rule. Kept as a self-reference rather than a pairing table
  -- because the relation is directed and NOT symmetric in practice (AG-MKT-02's
  -- partner is AG-CNT-01, whose own partner is AG-CNT-02); a pairing table would
  -- either lose that or reject the roster. DEFERRABLE INITIALLY DEFERRED so all
  -- 21 agents load in one transaction in any order — this is what removes the
  -- seeding order dependency. NO ACTION, not RESTRICT: RESTRICT is never
  -- deferred, so it would defeat the point; NO ACTION still blocks the delete at
  -- commit, which is the doctrine (re-pair before you retire an agent).
  duo_partner     text NOT NULL REFERENCES agents(id) ON DELETE NO ACTION
                    DEFERRABLE INITIALLY DEFERRED CHECK (duo_partner <> id),
  charter         text NOT NULL,
  memory_path     text NOT NULL UNIQUE,      -- /brain/agents/<id>.md — two agents sharing one memory file is a bug
  status          text NOT NULL DEFAULT 'active'
                    CHECK (status IN ('hot','active','idle','paused')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  -- Declarative proof that an agent reports to the supervisor of its own
  -- department; without it, reports_to was free text.
  FOREIGN KEY (reports_to, department_code)
    REFERENCES supervisors (id, department_code) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS agents_department_idx  ON agents (department_code);
CREATE INDEX IF NOT EXISTS agents_reports_to_idx  ON agents (reports_to, department_code);  -- also the index for the composite FK
CREATE INDEX IF NOT EXISTS agents_duo_partner_idx ON agents (duo_partner);                  -- FK index: partner lookups and delete checks

-- Append-only run log: the highest-volume table here (21 agents x hundreds of
-- runs/day). Surrogate identity key; the OS 'RUN-88401' label is kept as a
-- unique reference, not as the primary key.
CREATE TABLE IF NOT EXISTS agent_runs (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_ref       text UNIQUE,                 -- 'RUN-88401' / runtime job id; null when the runtime does not mint one
  agent_id      text NOT NULL REFERENCES agents(id) ON DELETE RESTRICT,  -- never lose spend history by deleting an agent
  task          text NOT NULL,
  started_at    timestamptz NOT NULL DEFAULT now(),
  duration_s    integer CHECK (duration_s >= 0),
  rows_touched  integer NOT NULL DEFAULT 0 CHECK (rows_touched >= 0),
  status        text NOT NULL CHECK (status IN ('ok','warn','review','failed')),
  cost_usd      numeric(12,4) NOT NULL DEFAULT 0 CHECK (cost_usd >= 0),  -- numeric, never float: this number is summed into budgets
  note_path     text,                        -- the vault note this run wrote
  payload       jsonb NOT NULL DEFAULT '{}'::jsonb
);
-- The two real reads: "this agent's recent runs" and "what needs escalating".
CREATE INDEX IF NOT EXISTS agent_runs_agent_started_idx
  ON agent_runs (agent_id, started_at DESC);  -- equality column first, range column last
-- Partial + covering: the escalation feed is a few rows out of millions, and the
-- index answers it without touching the heap. (The old index was on status
-- inside a predicate that already fixed status — a column that is constant in
-- the predicate buys nothing.)
CREATE INDEX IF NOT EXISTS agent_runs_escalation_idx
  ON agent_runs (started_at DESC) INCLUDE (agent_id, status, task)
  WHERE status <> 'ok';
-- Not partitioned, on purpose: partitioning pays off past ~100M rows or when old
-- data must be dropped instantly. At the current rate that is years away, and
-- range partitioning by started_at would force a partition-maintenance job today.
-- When it is warranted: PARTITION BY RANGE (started_at), monthly partitions, and
-- the primary key becomes (id, started_at). No jsonb index on payload until a
-- query actually filters on it — an unused GIN index is pure write cost.

-- ---------------------------------------------------------------- sales core
-- From here down, tables grow with the business, so the primary key is a bigint
-- identity and the OS human label ('ACC-1041') is a nullable UNIQUE `ref`.
-- Why: those labels are display codes minted by the UI, they can be renumbered,
-- rows created by an agent may not have one yet, and an 8-byte sequential key
-- keeps the indexes small and the inserts local.
CREATE TABLE IF NOT EXISTS accounts (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ref             text UNIQUE,               -- ACC-1041
  name            text NOT NULL CHECK (btrim(name) <> ''),
  niche_id        text REFERENCES niches(id) ON DELETE RESTRICT,
  city            text,
  employees       integer CHECK (employees >= 0),
  revenue_band    text,
  owner_verified  text,                      -- how ownership was corroborated (doctrine: two independent sources)
  source          text,                      -- Apollo | Clay | Crawl4AI | Manual
  fit_score       smallint CHECK (fit_score BETWEEN 0 AND 100),
  vault_note      text UNIQUE,               -- /brain/accounts/<slug>.md
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS accounts_niche_idx ON accounts (niche_id);
-- Crawlers re-find the same firm every run; this is the dedupe guard AG-RES-01
-- relies on. City is part of the key so two genuinely different firms with the
-- same name in different metros can both exist.
CREATE UNIQUE INDEX IF NOT EXISTS accounts_name_city_uniq
  ON accounts (lower(name), lower(coalesce(city, '')));

CREATE TABLE IF NOT EXISTS contacts (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ref           text UNIQUE,                 -- CON-3301
  account_id    bigint NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,  -- a contact has no meaning without its account
  name          text NOT NULL CHECK (btrim(name) <> ''),
  title         text,
  email         text CHECK (email IS NULL OR email LIKE '%_@_%.__%'),  -- cheap shape check; verification is email_status' job
  email_status  text NOT NULL DEFAULT 'unverified'
                CHECK (email_status IN ('verified','risky','catch-all','unverified','invalid')),
  phone         text,
  linkedin      text,
  channel       text,
  last_touch_at date,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  -- A status can only describe an address that exists.
  CHECK (email IS NOT NULL OR email_status = 'unverified')
);
CREATE INDEX IF NOT EXISTS contacts_account_idx ON contacts (account_id);
-- One row per human, whichever agent found them. Partial: contacts without an
-- address (phone-only, LinkedIn-only) must not collide with each other.
CREATE UNIQUE INDEX IF NOT EXISTS contacts_email_uniq
  ON contacts (lower(email)) WHERE email IS NOT NULL;
-- The send queue: sendable contacts, stalest first. Indexing last_touch_at (not
-- email_status, which the predicate already fixes) is what makes the ordering free.
CREATE INDEX IF NOT EXISTS contacts_sendable_idx
  ON contacts (last_touch_at NULLS FIRST) WHERE email_status = 'verified';

-- Deal stages are a lookup table rather than a CHECK list because the pipeline
-- view needs a stable display order and needs stages with zero deals to still
-- appear. (Vocabularies that are only validated, never ordered or aggregated —
-- statuses, partner stages — stay as CHECK constraints: cheaper, no join.)
CREATE TABLE IF NOT EXISTS deal_stages (
  stage       text PRIMARY KEY,
  sort_order  smallint NOT NULL UNIQUE,
  is_closed   boolean NOT NULL DEFAULT false,
  is_won      boolean NOT NULL DEFAULT false,
  CHECK (NOT is_won OR is_closed)            -- won implies closed
);

CREATE TABLE IF NOT EXISTS deals (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ref             text UNIQUE,               -- DEAL-901
  account_id      bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,  -- money: never cascade a deal away
  contact_id      bigint REFERENCES contacts(id) ON DELETE SET NULL,           -- the deal outlives the champion who left
  stage           text NOT NULL REFERENCES deal_stages(stage) ON UPDATE CASCADE ON DELETE RESTRICT,
  value_usd       numeric(12,2) NOT NULL DEFAULT 0 CHECK (value_usd >= 0),
  term            text,
  probability     numeric(4,3) NOT NULL DEFAULT 0 CHECK (probability BETWEEN 0 AND 1),
  owner_agent     text REFERENCES agents(id) ON DELETE SET NULL,               -- unowned deal is a fact worth seeing, not an error
  next_action     text,
  opened_at       date NOT NULL DEFAULT current_date,
  closed_at       date CHECK (closed_at IS NULL OR closed_at >= opened_at),
  crm_external_id text,                      -- HubSpot / Twenty mirror id
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
  -- No niche_id: a deal's niche is its account's niche. One place to change it.
);
CREATE INDEX IF NOT EXISTS deals_stage_idx      ON deals (stage);       -- FK index + the OS stage filter
CREATE INDEX IF NOT EXISTS deals_account_idx    ON deals (account_id);  -- FK index: account -> deals on every account panel
CREATE INDEX IF NOT EXISTS deals_contact_idx    ON deals (contact_id);
-- The working pipeline. The closed stages are spelled out because an index
-- predicate must be immutable and cannot join to deal_stages.is_closed; keep the
-- two in step when the vocabulary changes.
CREATE INDEX IF NOT EXISTS deals_open_owner_idx
  ON deals (owner_agent) INCLUDE (stage, value_usd, probability)
  WHERE stage NOT IN ('Closed Won','Closed Lost');
-- The CRM mirror id must be unique when present, and is absent for most rows.
CREATE UNIQUE INDEX IF NOT EXISTS deals_crm_external_uniq
  ON deals (crm_external_id) WHERE crm_external_id IS NOT NULL;
-- owner_agent gets the partial index above and no full one: every read of it is
-- "this agent's open deals". The only thing a full index would speed up is the
-- ON DELETE SET NULL sweep when an agent is retired, which happens roughly never.


-- ------------------------------------------------------- partnerships (BD)
CREATE TABLE IF NOT EXISTS partners (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ref              text UNIQUE,              -- PTR-201
  name             text NOT NULL,
  partner_type     text NOT NULL CHECK (partner_type IN ('Referral','Channel','Reseller','Tech Alliance')),
  niche_id         text REFERENCES niches(id) ON DELETE RESTRICT,
  stage            text NOT NULL CHECK (stage IN ('Intro','Qualified','Pilot','Negotiation','Signed','Ended')),
  intros_per_month integer NOT NULL DEFAULT 0 CHECK (intros_per_month >= 0),
  rev_share_pct    numeric(5,2) CHECK (rev_share_pct BETWEEN 0 AND 100),  -- was text '15%': a rate is a number
  owner_agent      text REFERENCES agents(id) ON DELETE SET NULL,
  note             text,
  signed_at        date,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  -- A signature date only means something once the partnership was signed.
  CHECK (signed_at IS NULL OR stage IN ('Signed','Ended'))
);
CREATE INDEX IF NOT EXISTS partners_niche_idx ON partners (niche_id);
CREATE INDEX IF NOT EXISTS partners_owner_idx ON partners (owner_agent);
CREATE UNIQUE INDEX IF NOT EXISTS partners_name_uniq ON partners (lower(name));  -- one row per partner organisation

-- ------------------------------------------------------------- marketing
CREATE TABLE IF NOT EXISTS campaigns (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ref           text UNIQUE,                 -- CMP-501
  name          text NOT NULL,
  channel       text NOT NULL,               -- Cold email | LinkedIn | Newsletter | Paid — open vocabulary, new channels arrive
  niche_id      text REFERENCES niches(id) ON DELETE RESTRICT,
  owner_agent   text REFERENCES agents(id) ON DELETE SET NULL,
  status        text NOT NULL DEFAULT 'draft'
                CHECK (status IN ('draft','running','paused','ended')),
  sent          integer NOT NULL DEFAULT 0 CHECK (sent >= 0),
  replied       integer NOT NULL DEFAULT 0 CHECK (replied >= 0),
  booked        integer NOT NULL DEFAULT 0 CHECK (booked >= 0),
  won           integer NOT NULL DEFAULT 0 CHECK (won >= 0),
  started_at    date,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  -- A reply requires a send. The rest of the funnel is deliberately NOT chained:
  -- CMP-505 books meetings with zero replies (partner-sourced attribution), so
  -- booked <= replied would be a false constraint.
  CHECK (replied <= sent)
  -- No "running implies started_at" check: the shipped seed runs four campaigns
  -- with no recorded start date, and inventing one to satisfy a constraint is
  -- worse than admitting the date is unknown.
);
CREATE INDEX IF NOT EXISTS campaigns_niche_idx ON campaigns (niche_id);
CREATE INDEX IF NOT EXISTS campaigns_owner_idx ON campaigns (owner_agent);

CREATE TABLE IF NOT EXISTS content_items (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ref           text UNIQUE,                 -- CNT-701
  title         text NOT NULL,
  format        text,
  niche_id      text REFERENCES niches(id) ON DELETE RESTRICT,
  channels      text[] NOT NULL DEFAULT '{}',
  status        text NOT NULL DEFAULT 'idea'
                CHECK (status IN ('idea','drafting','in review','scheduled','published')),
  publish_at    date,
  owner_agent   text REFERENCES agents(id) ON DELETE SET NULL,
  asset_path    text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  -- NULLs inside an array are the classic array footgun (they break = ANY and
  -- array_position semantics); forbid them at the door.
  CHECK (array_position(channels, NULL) IS NULL),
  -- Anything scheduled or published has a date; drafts need not.
  CHECK (status NOT IN ('scheduled','published') OR publish_at IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS content_niche_idx ON content_items (niche_id);
CREATE INDEX IF NOT EXISTS content_owner_idx ON content_items (owner_agent);
-- The editorial calendar read: what is coming up, in order.
CREATE INDEX IF NOT EXISTS content_calendar_idx
  ON content_items (publish_at) WHERE status IN ('scheduled','in review');
-- No GIN index on channels yet: four rows and no query filters on it. Add
-- `USING gin (channels)` the day the OS filters content by channel.

-- Funnel stages are ordered for display and must show even at zero, so they get
-- a lookup table for the same reason deal_stages does.
CREATE TABLE IF NOT EXISTS funnel_stages (
  stage       text PRIMARY KEY,
  sort_order  smallint NOT NULL UNIQUE,
  description text
);

CREATE TABLE IF NOT EXISTS funnel_snapshots (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  captured_on   date NOT NULL DEFAULT current_date,
  stage         text NOT NULL REFERENCES funnel_stages(stage) ON UPDATE CASCADE ON DELETE RESTRICT,
  stage_count   integer NOT NULL CHECK (stage_count >= 0),  -- named stage_count, not count: `count` shadows the aggregate in every view
  note          text,
  UNIQUE (captured_on, stage)                -- one measurement per stage per day; also the index that serves "latest snapshot"
);
-- No separate index on captured_on: the UNIQUE (captured_on, stage) index has it
-- as the leftmost column and already answers range and latest-first scans. The
-- stage foreign key is left unindexed on purpose — funnel_stages holds six rows
-- that are never deleted, so the only cost would be write amplification.
-- Not partitioned: one row per stage per day is ~2k rows a year.

-- Daily runs per department — the OS throughput sparkline. Composite
-- natural key: it is a measurement identified by its dimensions, and a surrogate
-- id would only invite duplicate days.
CREATE TABLE IF NOT EXISTS department_throughput (
  department_code text NOT NULL REFERENCES departments(code) ON DELETE CASCADE,
  captured_on     date NOT NULL,
  runs            integer NOT NULL CHECK (runs >= 0),
  PRIMARY KEY (department_code, captured_on)
);

-- ---------------------------------------------------------- the nerve
CREATE TABLE IF NOT EXISTS integrations (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ref           text UNIQUE,                 -- KEY-01
  service       text NOT NULL UNIQUE,        -- one registry row per service, or usage counters double-count
  purpose       text NOT NULL,
  env_var       text,                        -- the NAME only. Never the value. NULL where there is no API at all.
  host          text NOT NULL CHECK (host IN ('local cloud','cloud','web')),
  status        text NOT NULL CHECK (status IN ('live','pending','manual','restricted','disabled')),
  used          numeric(12,2) NOT NULL DEFAULT 0 CHECK (used >= 0),
  quota         numeric(12,2) NOT NULL DEFAULT 0 CHECK (quota >= 0),  -- 0 = unmetered (self-hosted)
  unit          text,
  -- Stored generated column: the credit warden's number, computed once on write
  -- instead of in every dashboard query. NULL when unmetered.
  usage_pct     numeric(6,2) GENERATED ALWAYS AS
                  (CASE WHEN quota > 0 THEN round(used * 100 / quota, 2) END) STORED,
  checked_at    timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE integrations IS
  'Registry of connections. Secrets live in the local .env, loaded per-agent by scope.';
-- Two services must not read the same env var: that is how a quota gets blamed
-- on the wrong agent. Partial because manual sources (BBB, TruePeopleSearch)
-- have no env var at all.
CREATE UNIQUE INDEX IF NOT EXISTS integrations_env_var_uniq
  ON integrations (env_var) WHERE env_var IS NOT NULL;
-- AG-FIN-02 pauses a consuming agent at 90% of any monthly allowance; this makes
-- that sweep an index scan over a handful of rows instead of a table scan.
CREATE INDEX IF NOT EXISTS integrations_over_budget_idx
  ON integrations (service) WHERE quota > 0 AND used >= quota * 0.9;

-- ------------------------------------------------------------- the brain
CREATE TABLE IF NOT EXISTS brain_map (
  path          text PRIMARY KEY,            -- '/brain/decisions' or 'godly.*' — the address is the identity
  zone          text NOT NULL,               -- Obsidian | Postgres | Google Drive | Local object store
  holds         text NOT NULL,
  written_by    text NOT NULL,
  read_by       text NOT NULL,
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS decisions (
  id              text PRIMARY KEY,          -- DEC-2026-08-14-hunter-rationing; mirrors the vault note's frontmatter id
  owner           text NOT NULL,             -- no FK: the owner may be the CEO seat, a chief or a supervisor — three different tables
  question        text NOT NULL,
  numbers         text,
  decision        text NOT NULL,
  rejected        text,
  reverses_if     text NOT NULL,             -- doctrine: a decision without a reversal condition is an opinion
  vault_path      text NOT NULL UNIQUE,      -- one note per decision, both directions
  linked_tables   text[] NOT NULL DEFAULT '{}' CHECK (array_position(linked_tables, NULL) IS NULL),
  decided_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS decisions_decided_at_idx ON decisions (decided_at DESC);

CREATE TABLE IF NOT EXISTS sources (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name          text NOT NULL,
  category      text NOT NULL,
  url           text NOT NULL,
  kind          text NOT NULL,               -- OSS | API | SaaS | Company | Web | Index | Reading | Spec — open vocabulary
  verdict       text NOT NULL CHECK (verdict IN ('adopt','pilot','watch','read','study','manual','restricted')),
  note          text,
  reviewed_at   date NOT NULL DEFAULT current_date,
  -- name was the primary key in the draft, which the research index cannot
  -- satisfy: 'Clay' is filed twice, once as a tool to adopt and once as a
  -- company to study. The identity is (category, name).
  UNIQUE (category, name)
);
CREATE INDEX IF NOT EXISTS sources_verdict_idx ON sources (verdict) WHERE verdict IN ('adopt','pilot');

-- ------------------------------------------------------------- updated_at
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['company_profile','niches','departments','supervisors','agents',
                           'accounts','contacts','deals','partners','campaigns',
                           'content_items','integrations','brain_map']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON godly.%I', t || '_touch_updated_at', t);
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE ON godly.%I
         FOR EACH ROW EXECUTE FUNCTION godly.touch_updated_at()',
      t || '_touch_updated_at', t);
  END LOOP;
END $$;

-- ------------------------------------------------- the product (0003)
-- The capability catalogue: the same nine everywhere, configured per client.
CREATE TABLE IF NOT EXISTS front_office_capabilities (
  id            text PRIMARY KEY,                 -- FO-01 … stable, printed in proposals
  capability    text NOT NULL UNIQUE,
  channel       text NOT NULL,                    -- phone | email, web form, SMS | calendar | any
  does          text NOT NULL,
  replaces      text NOT NULL,                    -- the failure it removes; this is the pitch
  writes_to     text NOT NULL,                    -- client-side records the agent creates
  status        text NOT NULL DEFAULT 'pilot'
                CHECK (status IN ('live','pilot','planned','retired')),
  sort_order    smallint NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE front_office_capabilities IS
  'What Hero ships. Deployments reference these; proposals quote them by id.';

-- One row per client business running a pod.
CREATE TABLE IF NOT EXISTS deployments (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id    bigint REFERENCES accounts(id) ON DELETE SET NULL,
  client_name   text NOT NULL,                    -- kept even if the account row is removed
  niche_id      text REFERENCES niches(id) ON DELETE RESTRICT,
  stage         text NOT NULL CHECK (stage IN ('Pilot','Onboarding','Running','Paused','Ended')),
  live_since    date NOT NULL,
  note          text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (client_name, live_since)
);
CREATE INDEX IF NOT EXISTS deployments_running_idx ON deployments (live_since DESC) WHERE stage = 'Running';

-- Which capabilities are switched on for which client. The join is the product.
CREATE TABLE IF NOT EXISTS deployment_capabilities (
  deployment_id bigint NOT NULL REFERENCES deployments(id) ON DELETE CASCADE,
  capability_id text   NOT NULL REFERENCES front_office_capabilities(id) ON DELETE RESTRICT,
  enabled_on    date   NOT NULL DEFAULT current_date,
  PRIMARY KEY (deployment_id, capability_id)
);

CREATE OR REPLACE TRIGGER front_office_capabilities_touch_updated_at
  BEFORE UPDATE ON front_office_capabilities
  FOR EACH ROW EXECUTE FUNCTION godly.touch_updated_at();
CREATE OR REPLACE TRIGGER deployments_touch_updated_at
  BEFORE UPDATE ON deployments
  FOR EACH ROW EXECUTE FUNCTION godly.touch_updated_at();

-- What is live where, in one read — the shape Chapter I prints.
CREATE OR REPLACE VIEW deployment_board AS
SELECT d.id,
       d.client_name,
       d.niche_id,
       d.stage,
       d.live_since,
       count(dc.capability_id)                                   AS capabilities_live,
       array_agg(c.capability ORDER BY c.sort_order)
         FILTER (WHERE dc.capability_id IS NOT NULL)             AS capabilities,
       d.note
FROM deployments d
LEFT JOIN deployment_capabilities dc ON dc.deployment_id = d.id
LEFT JOIN front_office_capabilities c ON c.id = dc.capability_id
GROUP BY d.id, d.client_name, d.niche_id, d.stage, d.live_since, d.note;

-- ------------------------------------------------------------- read models
-- Plain views, not materialized: every one of these reads tens to thousands of
-- rows on a single-node box. Materialize only when EXPLAIN says so, because a
-- matview needs a refresh owner and goes stale between runs.

-- Pipeline board. LEFT JOIN from the stage list so an empty stage still renders
-- as a zero column instead of disappearing from the chart.
CREATE OR REPLACE VIEW pipeline_by_stage AS
SELECT s.stage,
       s.sort_order,
       s.is_closed,
       count(d.id)                                   AS deals,
       coalesce(sum(d.value_usd), 0)                 AS value_usd,
       coalesce(sum(d.value_usd * d.probability), 0) AS weighted_usd
FROM deal_stages s
LEFT JOIN deals d ON d.stage = s.stage
GROUP BY s.stage, s.sort_order, s.is_closed
ORDER BY s.sort_order;

-- Agent load over the trailing week. Column names kept from v0 (id, name,
-- department, duo_partner, runs_7d, cost_7d) so the codex keeps working;
-- escalations_7d is added because that is the number a supervisor acts on.
-- GROUP BY a.id alone is legal: the rest are functionally dependent on the key.
CREATE OR REPLACE VIEW agent_load_7d AS
SELECT a.id,
       a.name,
       a.department_code                             AS department,
       a.duo_partner,
       count(r.id)                                   AS runs_7d,
       coalesce(sum(r.cost_usd), 0)                  AS cost_7d,
       count(r.id) FILTER (WHERE r.status <> 'ok')   AS escalations_7d
FROM agents a
LEFT JOIN agent_runs r
       ON r.agent_id = a.id
      AND r.started_at > now() - interval '7 days'
GROUP BY a.id;

-- The org chart in one read — otherwise the codex issues 21 lookups to render it.
CREATE OR REPLACE VIEW agent_roster AS
SELECT a.id,
       a.name,
       a.status,
       d.code        AS department_code,
       d.name        AS department,
       d.title       AS chief_title,
       d.chief_name,
       s.id          AS supervisor_id,
       s.name        AS supervisor_name,
       s.cadence     AS supervisor_cadence,
       a.duo_partner,
       p.name        AS duo_partner_name,
       a.charter,
       a.memory_path
FROM agents a
JOIN departments d ON d.code = a.department_code
JOIN supervisors s ON s.id   = a.reports_to
JOIN agents p      ON p.id   = a.duo_partner
ORDER BY d.sort_order, a.id;

-- The deal board with the names the UI actually prints, so it never does
-- deal -> account -> contact as three round trips per row.
CREATE OR REPLACE VIEW deal_board AS
SELECT dl.id,
       dl.ref,
       dl.stage,
       st.sort_order,
       st.is_closed,
       ac.name                     AS account_name,
       n.name                      AS niche,
       ct.name                     AS contact_name,
       ct.email                    AS contact_email,
       dl.value_usd,
       dl.probability,
       dl.value_usd * dl.probability AS weighted_usd,
       dl.term,
       dl.owner_agent,
       ag.name                     AS owner_agent_name,
       dl.next_action,
       dl.opened_at,
       dl.closed_at
FROM deals dl
JOIN deal_stages st ON st.stage = dl.stage
JOIN accounts ac    ON ac.id    = dl.account_id
LEFT JOIN niches n  ON n.id     = ac.niche_id
LEFT JOIN contacts ct ON ct.id  = dl.contact_id
LEFT JOIN agents ag ON ag.id    = dl.owner_agent
ORDER BY st.sort_order, dl.value_usd DESC;

-- Most recent measurement per funnel stage, in funnel order. DISTINCT ON is the
-- Postgres idiom for "latest row per group" and rides the unique index.
CREATE OR REPLACE VIEW funnel_latest AS
SELECT latest.stage,
       fs.sort_order,
       latest.captured_on,
       latest.stage_count,
       latest.note
FROM (
  SELECT DISTINCT ON (f.stage) f.stage, f.captured_on, f.stage_count, f.note
  FROM funnel_snapshots f
  ORDER BY f.stage, f.captured_on DESC
) latest
JOIN funnel_stages fs ON fs.stage = latest.stage
ORDER BY fs.sort_order;

-- The credit warden's dashboard: what is metered, how close to the ceiling.
CREATE OR REPLACE VIEW integration_budget AS
SELECT service,
       purpose,
       host,
       status,
       used,
       quota,
       unit,
       usage_pct,
       usage_pct >= 90 AS at_pause_threshold,   -- doctrine: pause the consuming agent at 90%
       checked_at
FROM integrations
WHERE quota > 0
ORDER BY usage_pct DESC NULLS LAST;

-- ------------------------------------------------- the money (0004)
-- The price book. One row per sellable line; proposals quote these by code.
CREATE TABLE IF NOT EXISTS price_book (
  code            text PRIMARY KEY,                 -- FO-01-SETUP, POD-CORE …
  name            text NOT NULL,
  capability_id   text REFERENCES front_office_capabilities(id) ON DELETE SET NULL,
  billing         text NOT NULL CHECK (billing IN ('one-time','monthly','hourly')),
  list_price      numeric(12,2) NOT NULL CHECK (list_price >= 0),
  unit            text NOT NULL DEFAULT 'each',
  cost_to_serve   numeric(12,2) NOT NULL DEFAULT 0 CHECK (cost_to_serve >= 0),
  active          boolean NOT NULL DEFAULT true,
  notes           text,
  -- Set pricing: the published price is the only price. The guardrail is the
  -- enforce_set_pricing trigger, which refuses a quote line that does not match.
  updated_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE price_book IS
  'What we sell, at the only price we sell it for. Set pricing: the enforce_set_pricing trigger refuses a quote line that does not match list_price.';

CREATE TABLE IF NOT EXISTS quotes (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ref             text UNIQUE,                      -- QTE-1001
  deal_id         bigint REFERENCES deals(id) ON DELETE SET NULL,
  account_id      bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  status          text NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','in review','sent','accepted','declined','expired')),
  term_months     smallint NOT NULL CHECK (term_months BETWEEN 1 AND 60),
  sent_on         date,
  decided_on      date,
  prepared_by     text REFERENCES agents(id) ON DELETE SET NULL,
  priced_by       text REFERENCES agents(id) ON DELETE SET NULL,  -- the second pair of eyes
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quotes_decided_after_sent CHECK (decided_on IS NULL OR sent_on IS NULL OR decided_on >= sent_on),
  CONSTRAINT quotes_sent_has_date CHECK (status IN ('draft','in review') OR sent_on IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS quotes_open_idx ON quotes (sent_on DESC) WHERE status IN ('sent','in review');

CREATE TABLE IF NOT EXISTS quote_lines (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  quote_id        bigint NOT NULL REFERENCES quotes(id) ON DELETE CASCADE,
  code            text NOT NULL REFERENCES price_book(code) ON DELETE RESTRICT,
  quantity        numeric(10,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price      numeric(12,2) NOT NULL CHECK (unit_price >= 0),
  UNIQUE (quote_id, code)
);

-- What recurs. This is the number the business lives or dies on.
CREATE TABLE IF NOT EXISTS retainers (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id      bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  deployment_id   bigint REFERENCES deployments(id) ON DELETE SET NULL,
  quote_id        bigint REFERENCES quotes(id) ON DELETE SET NULL,
  mrr             numeric(12,2) NOT NULL CHECK (mrr >= 0),
  cost_to_serve   numeric(12,2) NOT NULL DEFAULT 0 CHECK (cost_to_serve >= 0),
  started_on      date NOT NULL,
  term_months     smallint NOT NULL CHECK (term_months BETWEEN 1 AND 60),
  status          text NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active','paused','churned','completed')),
  ended_on        date,
  churn_reason    text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT retainers_end_after_start CHECK (ended_on IS NULL OR ended_on >= started_on),
  CONSTRAINT retainers_ended_has_date CHECK (status IN ('active','paused') OR ended_on IS NOT NULL),
  CONSTRAINT retainers_churn_has_reason CHECK (status <> 'churned' OR churn_reason IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS retainers_active_idx ON retainers (started_on) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS invoices (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ref             text UNIQUE,                      -- INV-2026-0044
  retainer_id     bigint REFERENCES retainers(id) ON DELETE SET NULL,
  account_id      bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  period_start    date NOT NULL,
  period_end      date NOT NULL,
  amount          numeric(12,2) NOT NULL CHECK (amount >= 0),
  issued_on       date NOT NULL,
  due_on          date NOT NULL,
  paid_on         date,
  status          text NOT NULL DEFAULT 'issued'
                  CHECK (status IN ('draft','issued','paid','late','written off')),
  CONSTRAINT invoices_period_ordered CHECK (period_end >= period_start),
  CONSTRAINT invoices_due_after_issue CHECK (due_on >= issued_on),
  CONSTRAINT invoices_paid_has_date CHECK (status <> 'paid' OR paid_on IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS invoices_outstanding_idx ON invoices (due_on) WHERE status IN ('issued','late');

CREATE OR REPLACE TRIGGER price_book_touch_updated_at BEFORE UPDATE ON price_book
  FOR EACH ROW EXECUTE FUNCTION godly.touch_updated_at();
CREATE OR REPLACE TRIGGER quotes_touch_updated_at BEFORE UPDATE ON quotes
  FOR EACH ROW EXECUTE FUNCTION godly.touch_updated_at();
CREATE OR REPLACE TRIGGER retainers_touch_updated_at BEFORE UPDATE ON retainers
  FOR EACH ROW EXECUTE FUNCTION godly.touch_updated_at();

-- ------------------------------------------------------------- read models

-- The headline. Gross margin is carried alongside so MRR is never read alone.
CREATE OR REPLACE VIEW revenue_now AS
SELECT
  coalesce(sum(mrr) FILTER (WHERE status = 'active'), 0)                          AS mrr,
  coalesce(sum(mrr) FILTER (WHERE status = 'active'), 0) * 12                     AS arr,
  coalesce(sum(mrr - cost_to_serve) FILTER (WHERE status = 'active'), 0)          AS gross_profit_monthly,
  count(*) FILTER (WHERE status = 'active')                                       AS active_retainers,
  count(*) FILTER (WHERE status = 'churned')                                      AS churned_retainers,
  CASE WHEN sum(mrr) FILTER (WHERE status = 'active') > 0
       THEN round(sum(mrr - cost_to_serve) FILTER (WHERE status = 'active')
                  / sum(mrr) FILTER (WHERE status = 'active'), 4)
  END                                                                            AS gross_margin
FROM retainers;

CREATE OR REPLACE VIEW revenue_by_client AS
SELECT a.name AS client, a.niche_id, r.mrr, r.cost_to_serve,
       r.mrr - r.cost_to_serve                                   AS gross_profit,
       r.started_on, r.term_months, r.status,
       r.mrr * r.term_months                                     AS contract_value,
       (current_date - r.started_on) / 30                        AS months_in
FROM retainers r JOIN accounts a ON a.id = r.account_id;

-- Quote → close, the only conversion number that touches money.
CREATE OR REPLACE VIEW quote_performance AS
SELECT q.status,
       count(*)                                                  AS quotes,
       coalesce(sum(l.line_total), 0)                            AS value,
       round(avg(q.decided_on - q.sent_on), 1)                   AS avg_days_to_decide
FROM quotes q
LEFT JOIN LATERAL (
  SELECT sum(quantity * unit_price) AS line_total FROM quote_lines WHERE quote_id = q.id
) l ON true
GROUP BY q.status;

-- What is owed, and how late. The credit warden's counterpart on the way in.
CREATE OR REPLACE VIEW receivables AS
SELECT i.ref, a.name AS client, i.amount, i.issued_on, i.due_on, i.status,
       CASE WHEN i.status IN ('issued','late') THEN current_date - i.due_on END AS days_overdue
FROM invoices i JOIN accounts a ON a.id = i.account_id
WHERE i.status IN ('issued','late')
ORDER BY i.due_on;


-- --------------------------------------------- payments (0005)
-- Which merchant account, whose it is, and where the money lands.
CREATE TABLE IF NOT EXISTS payment_accounts (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  provider        text NOT NULL CHECK (provider IN ('stripe','square','quickbooks','servicetitan','manual')),
  owner           text NOT NULL CHECK (owner IN ('hero','client')),
  account_id      bigint REFERENCES accounts(id) ON DELETE CASCADE,   -- null when owner = 'hero'
  external_id     text,                                              -- acct_… / merchant id
  access          text NOT NULL DEFAULT 'oauth'
                  CHECK (access IN ('oauth','api-key','none')),
  settles_to_hero boolean NOT NULL DEFAULT false,
  status          text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','connected','revoked','disabled')),
  connected_on    date,
  note            text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  -- THE boundary. A client-owned account can never settle to Hero.
  CONSTRAINT payment_accounts_client_never_settles_to_hero
    CHECK (owner <> 'client' OR settles_to_hero = false),
  -- Hero's own account has no client attached; a client account must name one.
  CONSTRAINT payment_accounts_owner_shape
    CHECK ((owner = 'hero' AND account_id IS NULL) OR (owner = 'client' AND account_id IS NOT NULL)),
  CONSTRAINT payment_accounts_connected_has_external_id
    CHECK (status <> 'connected' OR external_id IS NOT NULL),
  UNIQUE (provider, external_id)
);
COMMENT ON TABLE payment_accounts IS
  'Merchant accounts. owner=hero bills our clients; owner=client is a delegated Connect/API account we operate but never settle from. The CHECK is the money-transmission boundary.';

-- Every webhook we have ever accepted. The unique constraint IS the idempotency.
CREATE TABLE IF NOT EXISTS payment_events (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  provider        text NOT NULL,
  external_event_id text NOT NULL,
  kind            text NOT NULL,                    -- invoice.paid, charge.refunded …
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb,
  received_at     timestamptz NOT NULL DEFAULT now(),
  processed_at    timestamptz,
  error           text,
  UNIQUE (provider, external_event_id)              -- a replayed webhook lands here and stops
);
CREATE INDEX IF NOT EXISTS payment_events_unprocessed_idx
  ON payment_events (received_at) WHERE processed_at IS NULL;

-- Money that actually moved. Flow A rows carry an invoice; Flow B rows do not.
CREATE TABLE IF NOT EXISTS payments (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_account_id bigint NOT NULL REFERENCES payment_accounts(id) ON DELETE RESTRICT,
  invoice_id      bigint REFERENCES invoices(id) ON DELETE SET NULL,  -- Flow A only
  deployment_id   bigint REFERENCES deployments(id) ON DELETE SET NULL, -- Flow B: whose pod collected it
  external_id     text,                             -- pi_… / ch_…
  amount          numeric(12,2) NOT NULL CHECK (amount >= 0),
  currency        text NOT NULL DEFAULT 'USD',
  method          text CHECK (method IN ('card','ach','link','cash','check','other')),
  status          text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','succeeded','failed','refunded','disputed')),
  paid_at         timestamptz,
  failure_reason  text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT payments_succeeded_has_time CHECK (status <> 'succeeded' OR paid_at IS NOT NULL),
  CONSTRAINT payments_failed_has_reason  CHECK (status <> 'failed' OR failure_reason IS NOT NULL),
  UNIQUE (payment_account_id, external_id)
);
CREATE INDEX IF NOT EXISTS payments_invoice_idx ON payments (invoice_id) WHERE invoice_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS payments_unmatched_idx ON payments (created_at)
  WHERE invoice_id IS NULL AND deployment_id IS NULL;

-- The ladder. Chasing money is a capability we sell, so we run it on ourselves.
CREATE TABLE IF NOT EXISTS dunning_attempts (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  invoice_id      bigint NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  step            smallint NOT NULL CHECK (step BETWEEN 1 AND 6),
  channel         text NOT NULL CHECK (channel IN ('email','sms','phone','none')),
  by_agent        text REFERENCES agents(id) ON DELETE SET NULL,   -- null when a human took it
  attempted_at    timestamptz NOT NULL DEFAULT now(),
  outcome         text NOT NULL DEFAULT 'sent'
                  CHECK (outcome IN ('sent','opened','replied','promised','paid','no answer','refused')),
  note            text,
  UNIQUE (invoice_id, step)
);
COMMENT ON TABLE dunning_attempts IS
  'One row per rung climbed. Step 5 is a human call and step 6 is the CEO service-pause decision — an agent may not take either.';

CREATE OR REPLACE TRIGGER payment_accounts_touch_updated_at
  BEFORE UPDATE ON payment_accounts FOR EACH ROW EXECUTE FUNCTION godly.touch_updated_at();

-- ------------------------------------------------------------- read models

-- Are we collecting? Cash in against what was billed.
CREATE OR REPLACE VIEW collection_health AS
SELECT
  count(*)                                                            AS invoices,
  coalesce(sum(amount), 0)                                            AS billed,
  coalesce(sum(amount) FILTER (WHERE status = 'paid'), 0)             AS collected,
  coalesce(sum(amount) FILTER (WHERE status IN ('issued','late')), 0) AS outstanding,
  coalesce(sum(amount) FILTER (WHERE status = 'late'), 0)             AS overdue,
  round(avg(paid_on - issued_on) FILTER (WHERE status = 'paid'), 1)   AS avg_days_to_pay,
  CASE WHEN sum(amount) > 0
       THEN round(coalesce(sum(amount) FILTER (WHERE status = 'paid'), 0) / sum(amount), 4)
  END                                                                 AS collected_share
FROM invoices;

-- What the payment agent should be working right now, and which rung it is on.
CREATE OR REPLACE VIEW dunning_queue AS
SELECT i.id AS invoice_id, i.ref, a.name AS client, i.amount, i.due_on,
       current_date - i.due_on                        AS days_overdue,
       coalesce(max(d.step), 0)                       AS last_step,
       coalesce(max(d.step), 0) + 1                   AS next_step,
       CASE WHEN coalesce(max(d.step), 0) + 1 >= 5 THEN 'human' ELSE 'agent' END AS next_owner,
       max(d.attempted_at)                            AS last_attempt
FROM invoices i
JOIN accounts a ON a.id = i.account_id
LEFT JOIN dunning_attempts d ON d.invoice_id = i.id
WHERE i.status IN ('issued','late')
GROUP BY i.id, i.ref, a.name, i.amount, i.due_on
ORDER BY i.due_on;

-- Money that arrived and matched nothing. This should always be empty.
CREATE OR REPLACE VIEW unreconciled_payments AS
SELECT p.id, p.external_id, p.amount, p.paid_at, pa.provider, pa.owner
FROM payments p
JOIN payment_accounts pa ON pa.id = p.payment_account_id
WHERE p.status = 'succeeded' AND p.invoice_id IS NULL AND p.deployment_id IS NULL;

-- Which connections are live, and whether any client has revoked us.
CREATE OR REPLACE VIEW payment_connections AS
SELECT pa.provider, pa.owner, coalesce(a.name, 'Hero Capital') AS holder,
       pa.status, pa.access, pa.settles_to_hero, pa.connected_on, pa.note
FROM payment_accounts pa
LEFT JOIN accounts a ON a.id = pa.account_id
ORDER BY pa.owner DESC, pa.status, holder;

-- ------------------------------ the client's customers (0006)
-- The client's customer. This is the client's data; Hero is the processor.
CREATE TABLE IF NOT EXISTS customers (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  deployment_id   bigint NOT NULL REFERENCES deployments(id) ON DELETE CASCADE,
  name            text NOT NULL,
  phone           text,
  email           text,
  address         text,
  arrived_via     text CHECK (arrived_via IN ('inbound call','web form','SMS','referral','walk-in','repeat','import')),
  referred_by     bigint REFERENCES customers(id) ON DELETE SET NULL,
  consent_sms     boolean NOT NULL DEFAULT false,
  consent_email   boolean NOT NULL DEFAULT false,
  consent_recording boolean NOT NULL DEFAULT false,   -- two-party states need this before recording
  do_not_contact  boolean NOT NULL DEFAULT false,
  first_seen      date NOT NULL DEFAULT current_date,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT customers_reachable CHECK (phone IS NOT NULL OR email IS NOT NULL),
  UNIQUE (deployment_id, phone),
  UNIQUE (deployment_id, email)
);
COMMENT ON TABLE customers IS
  'The CLIENT''S customers, not Hero''s. Hero is the processor: this data is exported or deleted on the client''s instruction. godly.contacts is the other thing entirely — Hero''s own prospects.';
-- tenant column leads every index, because every query is filtered by it first
CREATE INDEX IF NOT EXISTS customers_tenant_idx ON customers (deployment_id, first_seen DESC);
CREATE INDEX IF NOT EXISTS customers_contactable_idx ON customers (deployment_id)
  WHERE do_not_contact = false;

-- A unit of work the client actually sells. Whatever their product is.
CREATE TABLE IF NOT EXISTS jobs (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  deployment_id   bigint NOT NULL REFERENCES deployments(id) ON DELETE CASCADE,
  customer_id     bigint NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  title           text NOT NULL,                     -- 'Hail damage inspection', 'Botox follow-up'
  service_type    text,                              -- the client's own vocabulary
  status          text NOT NULL DEFAULT 'enquiry'
                  CHECK (status IN ('enquiry','quoted','booked','in progress','done','invoiced','paid','lost','cancelled')),
  value           numeric(12,2) CHECK (value IS NULL OR value >= 0),
  scheduled_for   timestamptz,
  completed_on    date,
  booked_by       text REFERENCES agents(id) ON DELETE SET NULL,   -- null when a human booked it
  lost_reason     text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT jobs_lost_has_reason CHECK (status <> 'lost' OR lost_reason IS NOT NULL),
  CONSTRAINT jobs_booked_has_time CHECK (status NOT IN ('booked','in progress') OR scheduled_for IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS jobs_tenant_idx ON jobs (deployment_id, created_at DESC);
CREATE INDEX IF NOT EXISTS jobs_customer_idx ON jobs (customer_id);
CREATE INDEX IF NOT EXISTS jobs_open_idx ON jobs (deployment_id, scheduled_for)
  WHERE status IN ('enquiry','quoted','booked','in progress');

-- Every touch the pod had with a customer. This is the work, itemized.
CREATE TABLE IF NOT EXISTS customer_interactions (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  deployment_id   bigint NOT NULL REFERENCES deployments(id) ON DELETE CASCADE,
  customer_id     bigint NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  job_id          bigint REFERENCES jobs(id) ON DELETE SET NULL,
  channel         text NOT NULL CHECK (channel IN ('phone','sms','email','web form')),
  direction       text NOT NULL CHECK (direction IN ('inbound','outbound')),
  handled_by      text REFERENCES agents(id) ON DELETE SET NULL,   -- null = a human took it
  occurred_at     timestamptz NOT NULL DEFAULT now(),
  duration_s      integer CHECK (duration_s IS NULL OR duration_s >= 0),
  outcome         text NOT NULL DEFAULT 'handled'
                  CHECK (outcome IN ('handled','booked','quoted','escalated','no answer','voicemail','refused')),
  summary         text,
  escalated_to    text,                              -- the named human, when it was handed over
  CONSTRAINT interactions_escalated_names_someone
    CHECK (outcome <> 'escalated' OR escalated_to IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS interactions_tenant_idx ON customer_interactions (deployment_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS interactions_customer_idx ON customer_interactions (customer_id, occurred_at DESC);

-- The CLIENT'S invoice to THEIR customer. Not godly.invoices, which is ours.
CREATE TABLE IF NOT EXISTS customer_invoices (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  deployment_id   bigint NOT NULL REFERENCES deployments(id) ON DELETE CASCADE,
  job_id          bigint NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  external_id     text,                              -- on the CLIENT's processor account
  amount          numeric(12,2) NOT NULL CHECK (amount >= 0),
  deposit         numeric(12,2) NOT NULL DEFAULT 0 CHECK (deposit >= 0),
  issued_on       date NOT NULL DEFAULT current_date,
  due_on          date NOT NULL,
  paid_on         date,
  status          text NOT NULL DEFAULT 'issued'
                  CHECK (status IN ('draft','issued','part paid','paid','late','written off')),
  CONSTRAINT customer_invoices_due_after_issue CHECK (due_on >= issued_on),
  CONSTRAINT customer_invoices_deposit_within CHECK (deposit <= amount),
  CONSTRAINT customer_invoices_paid_has_date CHECK (status <> 'paid' OR paid_on IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS customer_invoices_tenant_idx ON customer_invoices (deployment_id, due_on);

-- FO-07. Asked at the one moment the customer is happiest.
CREATE TABLE IF NOT EXISTS reviews (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  deployment_id   bigint NOT NULL REFERENCES deployments(id) ON DELETE CASCADE,
  job_id          bigint NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  platform        text NOT NULL DEFAULT 'google' CHECK (platform IN ('google','facebook','yelp','other')),
  requested_on    date NOT NULL DEFAULT current_date,
  left_on         date,
  rating          smallint CHECK (rating BETWEEN 1 AND 5),
  status          text NOT NULL DEFAULT 'asked'
                  CHECK (status IN ('asked','left','declined','no response')),
  CONSTRAINT reviews_left_has_detail CHECK (status <> 'left' OR (left_on IS NOT NULL AND rating IS NOT NULL)),
  UNIQUE (job_id, platform)                          -- ask once per job per platform, not twice
);
CREATE INDEX IF NOT EXISTS reviews_tenant_idx ON reviews (deployment_id, requested_on DESC);

CREATE OR REPLACE TRIGGER customers_touch_updated_at BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION godly.touch_updated_at();
CREATE OR REPLACE TRIGGER jobs_touch_updated_at BEFORE UPDATE ON jobs
  FOR EACH ROW EXECUTE FUNCTION godly.touch_updated_at();

-- ---------------------------------------------------- boundary 2: consent
-- An AI that dials and texts consumers is inside TCPA. Marking someone
-- do-not-contact has to mean something a buggy or prompt-injected agent
-- cannot talk its way past, so it is a trigger, not a rule in a prompt.
CREATE OR REPLACE FUNCTION godly.refuse_contact_without_consent()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c record;
BEGIN
  IF NEW.direction <> 'outbound' THEN RETURN NEW; END IF;   -- inbound is always allowed
  SELECT do_not_contact, consent_sms, consent_email INTO c
    FROM godly.customers WHERE id = NEW.customer_id;
  IF c.do_not_contact THEN
    RAISE EXCEPTION 'customer % is marked do-not-contact; outbound % refused', NEW.customer_id, NEW.channel
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.channel = 'sms' AND NOT c.consent_sms THEN
    RAISE EXCEPTION 'customer % has not consented to SMS', NEW.customer_id USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.channel = 'email' AND NOT c.consent_email THEN
    RAISE EXCEPTION 'customer % has not consented to email', NEW.customer_id USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
COMMENT ON FUNCTION godly.refuse_contact_without_consent() IS
  'Boundary: consent is enforced in the database because an agent can be talked out of a prompt but not out of a trigger.';

CREATE OR REPLACE TRIGGER interactions_respect_consent
  BEFORE INSERT ON customer_interactions
  FOR EACH ROW EXECUTE FUNCTION godly.refuse_contact_without_consent();

-- ---------------------------------------------------- boundary 1: tenancy
-- One client's customer list must be unreachable from another client's pod.
-- The pod sets `app.deployment_id` on its connection; the policy filters on it.
-- The setting is read inside a scalar subquery so the planner evaluates it once
-- per query rather than once per row.
CREATE OR REPLACE FUNCTION godly.current_deployment() RETURNS bigint
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('app.deployment_id', true), '')::bigint
$$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['customers','jobs','customer_interactions','customer_invoices','reviews'] LOOP
    EXECUTE format('ALTER TABLE godly.%I ENABLE ROW LEVEL SECURITY', t);
    -- FORCE, so the table owner is subject to the policy too. Without this a
    -- migration or a careless superuser session reads across every client.
    EXECUTE format('ALTER TABLE godly.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON godly.%I', t || '_tenant_isolation', t);
    EXECUTE format($p$
      CREATE POLICY %I ON godly.%I
        USING (deployment_id = (SELECT godly.current_deployment()))
        WITH CHECK (deployment_id = (SELECT godly.current_deployment()))
    $p$, t || '_tenant_isolation', t);
  END LOOP;
END $$;

-- The role a pod connects as. Least privilege: it works its own client's rows
-- and cannot delete a customer's history to tidy a mistake away.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'godly_pod') THEN
    CREATE ROLE godly_pod NOLOGIN;
  END IF;
END $$;
GRANT USAGE ON SCHEMA godly TO godly_pod;
GRANT SELECT, INSERT, UPDATE ON
  godly.customers, godly.jobs, godly.customer_interactions,
  godly.customer_invoices, godly.reviews TO godly_pod;
GRANT EXECUTE ON FUNCTION godly.current_deployment() TO godly_pod;

-- ------------------------------------------------------------- read models

-- What a pod actually did, per client. The number a renewal conversation needs.
-- Aggregated in separate LATERAL subqueries, NOT one join across three
-- one-to-many tables. Joining customers, jobs and interactions together
-- multiplies every row against the others, and sum(j.value) then counts each
-- job once per interaction. The first cut of this view reported $612,720 of
-- work won against $25,530 of actual jobs.
CREATE OR REPLACE VIEW pod_activity AS
SELECT d.id AS deployment_id, d.client_name,
       cu.customers, ix.interactions, ix.inbound, ix.escalated,
       jb.jobs, jb.jobs_booked, jb.work_won
FROM deployments d
LEFT JOIN LATERAL (
  SELECT count(*) AS customers FROM customers c WHERE c.deployment_id = d.id
) cu ON true
LEFT JOIN LATERAL (
  SELECT count(*)                                          AS interactions,
         count(*) FILTER (WHERE direction = 'inbound')     AS inbound,
         count(*) FILTER (WHERE outcome = 'escalated')     AS escalated
  FROM customer_interactions i WHERE i.deployment_id = d.id
) ix ON true
LEFT JOIN LATERAL (
  SELECT count(*)                                                                  AS jobs,
         count(*) FILTER (WHERE status IN ('booked','in progress','done','invoiced','paid')) AS jobs_booked,
         coalesce(sum(value) FILTER (WHERE status IN ('done','invoiced','paid')), 0)         AS work_won
  FROM jobs j WHERE j.deployment_id = d.id
) jb ON true;

-- Reviews asked versus left. FO-07 either works or it does not.
CREATE OR REPLACE VIEW review_performance AS
SELECT d.client_name,
       count(*)                                        AS asked,
       count(*) FILTER (WHERE r.status = 'left')       AS left_review,
       round(avg(r.rating) FILTER (WHERE r.rating IS NOT NULL), 2) AS avg_rating
FROM reviews r JOIN deployments d ON d.id = r.deployment_id
GROUP BY d.client_name;

-- Who the pod may lawfully contact, and by which channel.
CREATE OR REPLACE VIEW contactable_customers AS
SELECT id, deployment_id, name,
       (NOT do_not_contact) AND phone IS NOT NULL                   AS may_call,
       (NOT do_not_contact) AND consent_sms   AND phone IS NOT NULL AS may_sms,
       (NOT do_not_contact) AND consent_email AND email IS NOT NULL AS may_email,
       consent_recording                                            AS may_record
FROM customers;

-- ------------------------------------------ audit fixes (0007)
-- ---------------------------------------------------------- 1. pod lifetime
ALTER TABLE deployments ADD COLUMN IF NOT EXISTS ended_on date;
ALTER TABLE deployments ADD COLUMN IF NOT EXISTS ended_reason text;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'deployments_ended_shape' AND conrelid = 'godly.deployments'::regclass) THEN
    ALTER TABLE deployments ADD CONSTRAINT deployments_ended_shape
      CHECK (stage <> 'Ended' OR (ended_on IS NOT NULL AND ended_reason IS NOT NULL));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'deployments_end_after_start' AND conrelid = 'godly.deployments'::regclass) THEN
    ALTER TABLE deployments ADD CONSTRAINT deployments_end_after_start
      CHECK (ended_on IS NULL OR ended_on >= live_since);
  END IF;
END $$;

-- Every pod we have ever run, live or not, with what it was worth.
CREATE OR REPLACE VIEW pod_lifetime AS
SELECT d.id, d.client_name, d.niche_id, d.stage, d.live_since, d.ended_on,
       coalesce(d.ended_on, current_date) - d.live_since        AS days_live,
       r.mrr, r.status                                          AS retainer_status,
       r.mrr * (coalesce(d.ended_on, current_date) - d.live_since) / 30.0 AS revenue_to_date,
       coalesce(d.ended_reason, r.churn_reason)                 AS why_it_ended
FROM deployments d
LEFT JOIN LATERAL (
  SELECT mrr, status, churn_reason FROM retainers r
  WHERE r.deployment_id = d.id ORDER BY started_on DESC LIMIT 1
) r ON true;

-- ------------------------------------------------- 2. index the cascade path
-- Deleting a deployment cascades to customers, then jobs, then interactions,
-- invoices and reviews. Each child FK without an index is a sequential scan
-- per parent row, holding locks the whole way down.
CREATE INDEX IF NOT EXISTS customer_interactions_job_idx ON customer_interactions (job_id);
CREATE INDEX IF NOT EXISTS customer_invoices_job_idx     ON customer_invoices (job_id);
CREATE INDEX IF NOT EXISTS customers_referred_by_idx     ON customers (referred_by);
CREATE INDEX IF NOT EXISTS deployment_capabilities_capability_idx ON deployment_capabilities (capability_id);

-- Money tables: joined on every revenue read, and RESTRICT on delete means an
-- unindexed FK turns a price-book edit into a scan of every quote line.
CREATE INDEX IF NOT EXISTS retainers_account_idx    ON retainers (account_id);
CREATE INDEX IF NOT EXISTS retainers_deployment_idx ON retainers (deployment_id);
CREATE INDEX IF NOT EXISTS retainers_quote_idx      ON retainers (quote_id);
CREATE INDEX IF NOT EXISTS invoices_account_idx     ON invoices (account_id);
CREATE INDEX IF NOT EXISTS invoices_retainer_idx    ON invoices (retainer_id);
CREATE INDEX IF NOT EXISTS quotes_account_idx       ON quotes (account_id);
CREATE INDEX IF NOT EXISTS quotes_deal_idx          ON quotes (deal_id);
CREATE INDEX IF NOT EXISTS quote_lines_code_idx     ON quote_lines (code);
CREATE INDEX IF NOT EXISTS payments_deployment_idx  ON payments (deployment_id);
CREATE INDEX IF NOT EXISTS payment_accounts_account_idx ON payment_accounts (account_id);
CREATE INDEX IF NOT EXISTS deployments_account_idx  ON deployments (account_id);
CREATE INDEX IF NOT EXISTS deployments_niche_idx    ON deployments (niche_id);
CREATE INDEX IF NOT EXISTS price_book_capability_idx ON price_book (capability_id);
CREATE INDEX IF NOT EXISTS funnel_snapshots_stage_idx ON funnel_snapshots (stage);

-- Deliberately NOT indexed: the agent-attribution columns
--   customer_interactions.handled_by, jobs.booked_by, dunning_attempts.by_agent,
--   quotes.prepared_by, quotes.priced_by
-- The roster is 21 rows, agents are never deleted, and none of these is a
-- filter on a hot path. They are write cost for no reader. Add one the day a
-- per-agent attribution report exists and shows up slow.

-- ---------------------------------------- set pricing (0008)
-- (0008 retired the discount rig; the definitions above are already the
-- post-0008 shape, so nothing is dropped here.)

-- Margin is still watched — it is just watched on the published price now,
-- because that is the only price there is.
CREATE OR REPLACE VIEW price_margin AS
SELECT code, name, billing, unit, list_price, cost_to_serve,
       list_price - cost_to_serve                                    AS gross_per_unit,
       CASE WHEN list_price > 0
            THEN round((list_price - cost_to_serve) / list_price, 4) END AS gross_margin
FROM price_book WHERE active
ORDER BY billing, code;

-- ------------------------------------------- 2. the price is the price
CREATE OR REPLACE FUNCTION godly.enforce_set_pricing()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE listed numeric(12,2);
BEGIN
  SELECT list_price INTO listed FROM godly.price_book WHERE code = NEW.code;
  IF listed IS NULL THEN
    RAISE EXCEPTION 'no price book entry for %', NEW.code USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF NEW.unit_price <> listed THEN
    RAISE EXCEPTION 'set pricing: % is % and may not be quoted at %',
      NEW.code, listed, NEW.unit_price USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
COMMENT ON FUNCTION godly.enforce_set_pricing() IS
  'Set pricing is only real if it cannot be quietly departed from. A quote line that does not match the published price is refused.';

CREATE OR REPLACE TRIGGER quote_lines_set_pricing
  BEFORE INSERT OR UPDATE ON quote_lines
  FOR EACH ROW EXECUTE FUNCTION godly.enforce_set_pricing();

-- ------------------------------------------------ 3. billable time
CREATE TABLE IF NOT EXISTS time_entries (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id    bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  deployment_id bigint REFERENCES deployments(id) ON DELETE SET NULL,
  worked_on     date NOT NULL,
  hours         numeric(6,2) NOT NULL CHECK (hours > 0 AND hours <= 24),
  rate          numeric(10,2) NOT NULL CHECK (rate >= 0),   -- snapshot: the rate the day it was worked
  description   text NOT NULL,
  worked_by     text,                                        -- a human name; consulting is human time
  agent_id      text REFERENCES agents(id) ON DELETE SET NULL,
  invoice_id    bigint REFERENCES invoices(id) ON DELETE SET NULL,   -- null = not yet billed
  approved      boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now(),
  -- unapproved time is never billed; approval is what turns work into revenue
  CONSTRAINT time_entries_billed_is_approved CHECK (invoice_id IS NULL OR approved),
  CONSTRAINT time_entries_has_a_worker CHECK (worked_by IS NOT NULL OR agent_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS time_entries_unbilled_idx ON time_entries (account_id, worked_on)
  WHERE invoice_id IS NULL;
CREATE INDEX IF NOT EXISTS time_entries_invoice_idx ON time_entries (invoice_id);
COMMENT ON TABLE time_entries IS
  'Consulting hours at the published rate. Work in progress until approved, revenue only once invoiced.';

-- Invoices now come from three places, and it matters which.
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'monthly';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'invoices_kind_check') THEN
    ALTER TABLE invoices ADD CONSTRAINT invoices_kind_check
      CHECK (kind IN ('setup','monthly','hours'));
  END IF;
END $$;

-- Work done and not yet paid for. The number that quietly funds a business
-- or quietly drains one.
CREATE OR REPLACE VIEW unbilled_time AS
SELECT a.name AS client, count(*) AS entries,
       sum(t.hours)                                        AS hours,
       sum(t.hours * t.rate)                               AS value,
       sum(t.hours) FILTER (WHERE NOT t.approved)          AS hours_awaiting_approval,
       min(t.worked_on)                                    AS oldest_entry
FROM time_entries t JOIN accounts a ON a.id = t.account_id
WHERE t.invoice_id IS NULL
GROUP BY a.name
ORDER BY value DESC;

-- What the whole offer earns, by component.
CREATE OR REPLACE VIEW revenue_by_component AS
SELECT 'monthly' AS component,
       coalesce(sum(mrr) FILTER (WHERE status = 'active'), 0)                     AS recurring,
       coalesce(sum(mrr - cost_to_serve) FILTER (WHERE status = 'active'), 0)     AS gross
FROM retainers
UNION ALL
SELECT 'setup',
       coalesce(sum(amount) FILTER (WHERE kind = 'setup' AND status = 'paid'), 0), 0
FROM invoices
UNION ALL
SELECT 'hours',
       coalesce(sum(t.hours * t.rate) FILTER (WHERE i.status = 'paid'), 0),
       coalesce(sum(t.hours * t.rate) FILTER (WHERE i.status = 'paid'), 0)
FROM time_entries t LEFT JOIN invoices i ON i.id = t.invoice_id;

-- --------------------------- consulting sessions (0009)
CREATE TABLE IF NOT EXISTS consulting_sessions (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id     bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  deployment_id  bigint REFERENCES deployments(id) ON DELETE SET NULL,
  scheduled_for  timestamptz NOT NULL,
  duration_min   integer NOT NULL DEFAULT 60 CHECK (duration_min BETWEEN 15 AND 480),
  status         text NOT NULL DEFAULT 'scheduled'
                 CHECK (status IN ('scheduled','held','cancelled','no-show')),
  held_by        text,                              -- consulting is human time
  purpose        text NOT NULL,
  notes          text,
  -- Monday-start week the session falls in. Stored, not derived at read time,
  -- so the entitlement check and its index agree on one definition of "week".
  week_start     date GENERATED ALWAYS AS ((scheduled_for AT TIME ZONE 'UTC')::date
                   - ((extract(isodow FROM (scheduled_for AT TIME ZONE 'UTC'))::int) - 1)) STORED,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE consulting_sessions IS
  'Consulting slots on the internal calendar. Three a week per business; a fourth is refused by trigger, not by a policy someone remembers.';

-- The entitlement check reads this index rather than scanning the table.
CREATE INDEX IF NOT EXISTS consulting_sessions_entitlement_idx
  ON consulting_sessions (account_id, week_start)
  WHERE status IN ('scheduled','held');
CREATE INDEX IF NOT EXISTS consulting_sessions_calendar_idx
  ON consulting_sessions (scheduled_for) WHERE status = 'scheduled';
CREATE INDEX IF NOT EXISTS consulting_sessions_deployment_idx ON consulting_sessions (deployment_id);

-- Billable hours come from a session that was actually held.
ALTER TABLE time_entries ADD COLUMN IF NOT EXISTS session_id bigint
  REFERENCES consulting_sessions(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS time_entries_session_idx ON time_entries (session_id);

CREATE OR REPLACE TRIGGER consulting_sessions_touch_updated_at
  BEFORE UPDATE ON consulting_sessions
  FOR EACH ROW EXECUTE FUNCTION godly.touch_updated_at();

-- ------------------------------------------------------ the weekly cap
CREATE OR REPLACE FUNCTION godly.enforce_weekly_session_cap()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  cap    constant int := 3;
  booked int;
BEGIN
  -- A cancelled or no-show session gives the slot back.
  IF NEW.status NOT IN ('scheduled','held') THEN RETURN NEW; END IF;

  SELECT count(*) INTO booked
  FROM godly.consulting_sessions s
  WHERE s.account_id  = NEW.account_id
    AND s.week_start  = ((NEW.scheduled_for AT TIME ZONE 'UTC')::date
                          - ((extract(isodow FROM (NEW.scheduled_for AT TIME ZONE 'UTC'))::int) - 1))
    AND s.status IN ('scheduled','held')
    AND s.id IS DISTINCT FROM NEW.id;

  IF booked >= cap THEN
    RAISE EXCEPTION
      'session cap: account % already has % sessions in the week beginning %; the limit is %',
      NEW.account_id, booked,
      ((NEW.scheduled_for AT TIME ZONE 'UTC')::date
        - ((extract(isodow FROM (NEW.scheduled_for AT TIME ZONE 'UTC'))::int) - 1)),
      cap
      USING ERRCODE = 'check_violation',
            HINT = 'Offer the next week, or agree a scope change. Do not book a fourth.';
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE TRIGGER consulting_sessions_weekly_cap
  BEFORE INSERT OR UPDATE ON consulting_sessions
  FOR EACH ROW EXECUTE FUNCTION godly.enforce_weekly_session_cap();

-- ------------------------------------------------------------ read models

-- What each business has used and has left, this week and next.
CREATE OR REPLACE VIEW session_entitlement AS
SELECT a.id AS account_id, a.name AS client, w.week_start,
       count(s.id) FILTER (WHERE s.status IN ('scheduled','held')) AS booked,
       3 - count(s.id) FILTER (WHERE s.status IN ('scheduled','held')) AS remaining,
       count(s.id) FILTER (WHERE s.status = 'held')                 AS held,
       count(s.id) FILTER (WHERE s.status = 'no-show')              AS no_shows
FROM accounts a
CROSS JOIN (
  SELECT (current_date - (extract(isodow FROM current_date)::int - 1))::date AS week_start
  UNION ALL
  SELECT (current_date - (extract(isodow FROM current_date)::int - 1) + 7)::date
) w
LEFT JOIN consulting_sessions s
       ON s.account_id = a.id AND s.week_start = w.week_start
WHERE EXISTS (SELECT 1 FROM retainers r WHERE r.account_id = a.id AND r.status = 'active')
GROUP BY a.id, a.name, w.week_start
ORDER BY w.week_start, a.name;

-- The internal calendar, whole-firm. Capacity is surfaced, never auto-refused:
-- a full week is a conversation, not an error.
CREATE OR REPLACE VIEW calendar_load AS
SELECT week_start,
       count(*) FILTER (WHERE status IN ('scheduled','held'))            AS sessions,
       sum(duration_min) FILTER (WHERE status IN ('scheduled','held')) / 60.0 AS hours,
       count(DISTINCT account_id) FILTER (WHERE status IN ('scheduled','held')) AS businesses
FROM consulting_sessions
GROUP BY week_start
ORDER BY week_start;
