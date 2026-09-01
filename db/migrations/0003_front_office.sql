-- 0003_front_office — the product itself.
--
-- Chapter I of the codex describes what Hero deploys into a client business.
-- Until now the schema modelled how the firm sells, but not what it sells.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0003_front_office.sql

SET search_path TO godly, public;

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

INSERT INTO godly.schema_migrations (version, note)
VALUES ('0003_front_office', 'The product: capability catalogue, client deployments, and the join between them.')
ON CONFLICT (version) DO NOTHING;
