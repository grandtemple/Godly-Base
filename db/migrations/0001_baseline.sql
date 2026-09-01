-- 0001_baseline — the FRESH-INSTALL path, and the only migration a new
-- database runs.
--
-- db/schema.sql always describes the CURRENT shape: every later migration is
-- folded back into it. That makes replaying 0002…000N on a fresh database
-- wrong, not merely redundant — 0008 removes a column that 0004 builds a view
-- on, so a replay fails. It failed exactly that way once, which is why this
-- comment exists.
--
--   Fresh database   →  this file, then optionally 0002 for roles and grants.
--   Existing database →  only the migrations numbered above its current
--                        version, in order. Check with:
--                          select max(version) from godly.schema_migrations;
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0001_baseline.sql
--
-- \ir resolves relative to this file, so it runs from anywhere.

\ir ../schema.sql

-- schema.sql already contains every change through the version listed last
-- here, so a fresh install records them all. Without this an upgrade would
-- later try to re-apply migrations whose changes are already present.
INSERT INTO godly.schema_migrations (version, note) VALUES
  ('0001_baseline',        'Initial godly schema: roster, sales core, marketing, nerve, brain, read models.'),
  ('0003_front_office',    'The product: capability catalogue, client deployments, and the join between them.'),
  ('0004_revenue',         'Price book, quotes, retainers, invoices, and the read models that answer what we earn.'),
  ('0005_payments',        'Payment accounts with the money-transmission boundary as a CHECK, webhook idempotency ledger, payments, dunning ladder.'),
  ('0006_client_customers','The client''s customers, jobs, interactions, invoices and reviews — with RLS tenancy and a consent trigger.'),
  ('0007_model_audit',     'Pod lifetime so a churned client leaves a record; indexes on the delete-cascade and money join paths.'),
  ('0008_set_pricing',     'Set pricing: setup + monthly + hourly consulting. Discount machinery retired; billable time added.'),
  ('0009_consulting_sessions','Consulting as scheduled sessions: three a week per business, enforced by trigger; internal calendar load surfaced.')
ON CONFLICT (version) DO NOTHING;
