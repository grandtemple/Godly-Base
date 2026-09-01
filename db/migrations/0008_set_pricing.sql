-- 0008_set_pricing — prices are published, not negotiated.
--
-- The offer is three components and nothing else:
--   1. a set SETUP fee, one time
--   2. a set MONTHLY fee, everything included
--   3. CONSULTING at a set hourly rate, billed for time actually worked
--
-- That decision removes more than it adds. floor_price, ceo_override and the
-- margin_exceptions view all existed to police discounting below a floor. With
-- set pricing there is no discount conversation, so the floor is not a control
-- any more — it is a place for an exception to hide. The guardrail becomes the
-- opposite shape: a quote line MUST equal the published price, enforced by a
-- trigger, and a line that does not match is a defect rather than a discount.
--
-- What it adds is the thing set pricing needs and the old model had no room
-- for: somewhere to record billable hours.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0008_set_pricing.sql

SET search_path TO godly, public;

-- ------------------------------------------------ 1. retire the discount rig
DROP VIEW IF EXISTS margin_exceptions;
ALTER TABLE price_book DROP CONSTRAINT IF EXISTS price_book_floor_below_list;
ALTER TABLE price_book DROP CONSTRAINT IF EXISTS price_book_floor_above_cost;
ALTER TABLE price_book DROP COLUMN IF EXISTS floor_price;
ALTER TABLE quotes     DROP COLUMN IF EXISTS ceo_override;

-- hourly joins one-time and monthly as a billing shape
ALTER TABLE price_book DROP CONSTRAINT IF EXISTS price_book_billing_check;
ALTER TABLE price_book ADD  CONSTRAINT price_book_billing_check
  CHECK (billing IN ('one-time','monthly','hourly'));

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

INSERT INTO godly.schema_migrations (version, note)
VALUES ('0008_set_pricing', 'Set pricing: setup + monthly + hourly consulting. Discount machinery retired; billable time added.')
ON CONFLICT (version) DO NOTHING;
