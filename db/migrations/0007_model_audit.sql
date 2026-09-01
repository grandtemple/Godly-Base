-- 0007_model_audit — two defects found auditing the model, not by a failure.
--
-- 1. A churned client leaves no pod behind. deployments.stage allows 'Ended'
--    but there is no end date and nothing uses it, so the Palladin retainer —
--    churned in June — points at no deployment at all. "Every client we have
--    ever served" and any churn or lifetime analysis is unanswerable, which
--    for a firm whose whole argument is evidence-with-the-claim is the wrong
--    kind of hole.
--
-- 2. Twenty-three foreign keys had no supporting index. Most are harmless at
--    this size, but the ones on the CASCADE path from deployments down to a
--    customer's interactions are not: deleting a client's data is a
--    contractual obligation, and it would seq-scan every child table.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0007_model_audit.sql

SET search_path TO godly, public;

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

INSERT INTO godly.schema_migrations (version, note)
VALUES ('0007_model_audit', 'Pod lifetime so a churned client leaves a record; indexes on the delete-cascade and money join paths.')
ON CONFLICT (version) DO NOTHING;
