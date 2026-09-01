-- 0005_payments — connecting money movement, in both directions.
--
-- Two flows that look alike and are legally nothing alike (docs/PAYMENTS.md):
--   A. Hero bills its clients            — Hero is merchant of record.
--   B. The FO-06 agent collects for a client from THEIR customers
--                                        — the CLIENT is merchant of record.
-- Flow B funds must never touch Hero. That is money transmission, and for a
-- firm this size it is an existential exposure rather than a cost. The rule is
-- a CHECK constraint below, not a paragraph someone remembers.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0005_payments.sql

SET search_path TO godly, public;

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

INSERT INTO godly.schema_migrations (version, note)
VALUES ('0005_payments', 'Payment accounts with the money-transmission boundary as a CHECK, webhook idempotency ledger, payments, dunning ladder.')
ON CONFLICT (version) DO NOTHING;
