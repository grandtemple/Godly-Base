-- 0006_client_customers — the third party.
--
-- Hero sells to a CLIENT (a business owner). The client sells to THEIR
-- CUSTOMER. The pod's whole job happens against that third party: it answers
-- their call, books their job, invoices them, and asks them for a review — and
-- until now none of them had a table. FO-04 declared it writes to "bookings",
-- FO-06 to "invoices, payments" and FO-07 to "reviews". None existed. The
-- invoices in 0004 are Hero's own, billed to the client.
--
-- Two boundaries are structural here, alongside the money boundary in 0005:
--   1. TENANCY. One client's customer list must be unreachable from another
--      client's pod. RLS, forced, keyed on deployment_id.
--   2. CONSENT. An AI that calls and texts consumers is subject to TCPA and,
--      in two-party states, recording consent. A trigger refuses outbound
--      contact to anyone marked do-not-contact.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0006_client_customers.sql

SET search_path TO godly, public;

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

INSERT INTO godly.schema_migrations (version, note)
VALUES ('0006_client_customers', 'The client''s customers, jobs, interactions, invoices and reviews — with RLS tenancy and a consent trigger.')
ON CONFLICT (version) DO NOTHING;
