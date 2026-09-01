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
