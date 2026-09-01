-- 0004_revenue — the money.
--
-- Until now the schema could say what was in the pipeline and what was
-- deployed, but not what anything costs, what was quoted, what recurs, or
-- what has actually been collected. A firm cannot answer "what is our MRR"
-- from tables that do not exist.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0004_revenue.sql

SET search_path TO godly, public;

-- The price book. One row per sellable line; proposals quote these by code.
CREATE TABLE IF NOT EXISTS price_book (
  code            text PRIMARY KEY,                 -- FO-01-SETUP, POD-CORE …
  name            text NOT NULL,
  capability_id   text REFERENCES front_office_capabilities(id) ON DELETE SET NULL,
  billing         text NOT NULL CHECK (billing IN ('one-time','monthly','usage')),
  list_price      numeric(12,2) NOT NULL CHECK (list_price >= 0),
  unit            text NOT NULL DEFAULT 'each',
  cost_to_serve   numeric(12,2) NOT NULL DEFAULT 0 CHECK (cost_to_serve >= 0),
  floor_price     numeric(12,2) NOT NULL CHECK (floor_price >= 0),
  active          boolean NOT NULL DEFAULT true,
  notes           text,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  -- the guardrail the proposal skill enforces, made structural
  CONSTRAINT price_book_floor_below_list CHECK (floor_price <= list_price),
  CONSTRAINT price_book_floor_above_cost CHECK (floor_price >= cost_to_serve)
);
COMMENT ON TABLE price_book IS
  'What we sell and what it may not be sold below. floor_price is the margin guardrail: AG-FIN-01 blocks anything under it without CEO sign-off.';

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
  ceo_override    boolean NOT NULL DEFAULT false,   -- true only when a line went below floor
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

-- Every line ever sold below its floor, and whether a human signed it off.
CREATE OR REPLACE VIEW margin_exceptions AS
SELECT q.ref AS quote, a.name AS client, l.code, p.name AS line,
       p.floor_price, l.unit_price, p.floor_price - l.unit_price AS below_floor_by,
       q.ceo_override, q.status
FROM quote_lines l
JOIN quotes q ON q.id = l.quote_id
JOIN accounts a ON a.id = q.account_id
JOIN price_book p ON p.code = l.code
WHERE l.unit_price < p.floor_price;

INSERT INTO godly.schema_migrations (version, note)
VALUES ('0004_revenue', 'Price book, quotes, retainers, invoices, and the read models that answer what we earn.')
ON CONFLICT (version) DO NOTHING;
