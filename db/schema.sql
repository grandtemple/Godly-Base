-- Godly Base — operating schema for the local cloud (PostgreSQL 15+).
-- Every table in the codex's Vault chapter is one of these. Secrets are NEVER
-- stored here: the integrations table holds env var NAMES and usage, not keys.

CREATE SCHEMA IF NOT EXISTS godly;
SET search_path TO godly, public;

-- ---------------------------------------------------------------- reference
CREATE TABLE IF NOT EXISTS niches (
  id            text PRIMARY KEY,
  name          text NOT NULL UNIQUE,
  playbook_path text,                       -- Obsidian: /brain/niches/<slug>.md
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------- the roster
CREATE TABLE IF NOT EXISTS departments (
  code          text PRIMARY KEY,           -- CSO, CMO, CBDO, CTO, CIO, CCO, CFO
  title         text NOT NULL,
  chief_name    text NOT NULL,
  charter       text NOT NULL,
  supervisor_id text NOT NULL,
  cadence       text NOT NULL
);

CREATE TABLE IF NOT EXISTS agents (
  id            text PRIMARY KEY,           -- AG-SALES-01
  name          text NOT NULL,
  department    text NOT NULL REFERENCES departments(code),
  reports_to    text NOT NULL,              -- supervisor id
  duo_partner   text REFERENCES agents(id), -- the double-agent rule, enforced in data
  charter       text NOT NULL,
  memory_path   text NOT NULL,              -- /brain/agents/<id>.md
  status        text NOT NULL DEFAULT 'active'
                CHECK (status IN ('hot','active','idle','paused')),
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS agents_department_idx ON agents (department);

CREATE TABLE IF NOT EXISTS agent_runs (
  id            bigserial PRIMARY KEY,
  agent_id      text NOT NULL REFERENCES agents(id),
  task          text NOT NULL,
  started_at    timestamptz NOT NULL DEFAULT now(),
  duration_s    integer,
  rows_touched  integer NOT NULL DEFAULT 0,
  status        text NOT NULL CHECK (status IN ('ok','warn','review','failed')),
  cost_usd      numeric(10,4) NOT NULL DEFAULT 0,
  note_path     text,                        -- the vault note this run wrote
  payload       jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS agent_runs_agent_started_idx ON agent_runs (agent_id, started_at DESC);
CREATE INDEX IF NOT EXISTS agent_runs_status_idx ON agent_runs (status) WHERE status <> 'ok';

-- ---------------------------------------------------------------- sales core
CREATE TABLE IF NOT EXISTS accounts (
  id              text PRIMARY KEY,
  name            text NOT NULL,
  niche_id        text REFERENCES niches(id),
  city            text,
  employees       integer,
  revenue_band    text,
  owner_verified  text,                      -- how ownership was corroborated
  source          text,                      -- Apollo | Clay | Crawl4AI | Manual
  fit_score       integer CHECK (fit_score BETWEEN 0 AND 100),
  vault_note      text,                      -- /brain/accounts/<slug>.md
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS accounts_niche_idx ON accounts (niche_id);

CREATE TABLE IF NOT EXISTS contacts (
  id            text PRIMARY KEY,
  account_id    text NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name          text NOT NULL,
  title         text,
  email         text,
  email_status  text NOT NULL DEFAULT 'unverified'
                CHECK (email_status IN ('verified','risky','catch-all','unverified','invalid')),
  phone         text,
  linkedin      text,
  channel       text,
  last_touch_at date
);
CREATE INDEX IF NOT EXISTS contacts_account_idx ON contacts (account_id);
CREATE INDEX IF NOT EXISTS contacts_sendable_idx ON contacts (email_status) WHERE email_status = 'verified';

CREATE TABLE IF NOT EXISTS deals (
  id            text PRIMARY KEY,
  account_id    text NOT NULL REFERENCES accounts(id),
  contact_id    text REFERENCES contacts(id),
  stage         text NOT NULL CHECK (stage IN
                ('New','Qualified','Discovery','Proposal','Negotiation','Closed Won','Closed Lost')),
  value_usd     numeric(12,2) NOT NULL DEFAULT 0,
  term          text,
  probability   numeric(4,3) NOT NULL DEFAULT 0 CHECK (probability BETWEEN 0 AND 1),
  owner_agent   text REFERENCES agents(id),
  next_action   text,
  opened_at     date NOT NULL DEFAULT current_date,
  closed_at     date,
  crm_external_id text                        -- HubSpot / Twenty mirror id
);
CREATE INDEX IF NOT EXISTS deals_stage_idx ON deals (stage);
CREATE INDEX IF NOT EXISTS deals_open_idx ON deals (owner_agent) WHERE stage NOT LIKE 'Closed%';

-- ------------------------------------------------------- partnerships (BD)
CREATE TABLE IF NOT EXISTS partners (
  id              text PRIMARY KEY,
  name            text NOT NULL,
  partner_type    text NOT NULL CHECK (partner_type IN ('Referral','Channel','Reseller','Tech Alliance')),
  niche_id        text REFERENCES niches(id),
  stage           text NOT NULL CHECK (stage IN ('Intro','Qualified','Pilot','Negotiation','Signed','Ended')),
  intros_per_month integer NOT NULL DEFAULT 0,
  rev_share       text,
  owner_agent     text REFERENCES agents(id),
  note            text,
  signed_at       date
);

-- ------------------------------------------------------------- marketing
CREATE TABLE IF NOT EXISTS campaigns (
  id            text PRIMARY KEY,
  name          text NOT NULL,
  channel       text NOT NULL,               -- Cold email | LinkedIn | Newsletter | Paid
  niche_id      text REFERENCES niches(id),
  owner_agent   text REFERENCES agents(id),
  status        text NOT NULL DEFAULT 'draft'
                CHECK (status IN ('draft','running','paused','ended')),
  sent          integer NOT NULL DEFAULT 0,
  replied       integer NOT NULL DEFAULT 0,
  booked        integer NOT NULL DEFAULT 0,
  won           integer NOT NULL DEFAULT 0,
  started_at    date
);

CREATE TABLE IF NOT EXISTS content_items (
  id            text PRIMARY KEY,
  title         text NOT NULL,
  format        text,
  niche_id      text REFERENCES niches(id),
  channels      text[],
  status        text NOT NULL DEFAULT 'idea'
                CHECK (status IN ('idea','drafting','in review','scheduled','published')),
  publish_at    date,
  owner_agent   text REFERENCES agents(id),
  asset_path    text
);

CREATE TABLE IF NOT EXISTS funnel_snapshots (
  id            bigserial PRIMARY KEY,
  captured_on   date NOT NULL DEFAULT current_date,
  stage         text NOT NULL,
  count         integer NOT NULL,
  note          text,
  UNIQUE (captured_on, stage)
);

-- ---------------------------------------------------------- the nerve
CREATE TABLE IF NOT EXISTS integrations (
  id            text PRIMARY KEY,
  service       text NOT NULL,
  purpose       text NOT NULL,
  env_var       text,                        -- the NAME only. Never the value.
  host          text NOT NULL CHECK (host IN ('local cloud','cloud','web')),
  status        text NOT NULL CHECK (status IN ('live','pending','manual','restricted','disabled')),
  used          numeric(12,2) NOT NULL DEFAULT 0,
  quota         numeric(12,2) NOT NULL DEFAULT 0,
  unit          text,
  checked_at    timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE integrations IS
  'Registry of connections. Secrets live in the local .env, loaded per-agent by scope.';

-- ------------------------------------------------------------- the brain
CREATE TABLE IF NOT EXISTS brain_map (
  path          text PRIMARY KEY,
  zone          text NOT NULL,               -- Obsidian | Postgres | Google Drive | Local object store
  holds         text NOT NULL,
  written_by    text NOT NULL,
  read_by       text NOT NULL
);

CREATE TABLE IF NOT EXISTS decisions (
  id              text PRIMARY KEY,          -- DEC-2026-08-14-hunter-rationing
  owner           text NOT NULL,
  question        text NOT NULL,
  numbers         text,
  decision        text NOT NULL,
  rejected        text,
  reverses_if     text NOT NULL,
  vault_path      text NOT NULL,
  linked_tables   text[],
  decided_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sources (
  name          text PRIMARY KEY,
  category      text NOT NULL,
  url           text NOT NULL,
  kind          text NOT NULL,               -- OSS | API | SaaS | Company | Web | Index | Reading
  verdict       text NOT NULL CHECK (verdict IN ('adopt','pilot','watch','read','study','manual','restricted')),
  note          text,
  reviewed_at   date NOT NULL DEFAULT current_date
);

-- ------------------------------------------------------------- read models
CREATE OR REPLACE VIEW pipeline_by_stage AS
SELECT stage,
       count(*)                       AS deals,
       sum(value_usd)                 AS value_usd,
       sum(value_usd * probability)   AS weighted_usd
FROM deals
GROUP BY stage;

CREATE OR REPLACE VIEW agent_load_7d AS
SELECT a.id, a.name, a.department, a.duo_partner,
       count(r.id)                    AS runs_7d,
       coalesce(sum(r.cost_usd), 0)   AS cost_7d
FROM agents a
LEFT JOIN agent_runs r
       ON r.agent_id = a.id
      AND r.started_at > now() - interval '7 days'
GROUP BY a.id, a.name, a.department, a.duo_partner;
