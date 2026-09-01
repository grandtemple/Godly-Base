-- 0009_consulting_sessions — consulting is sessions, not an open meter.
--
-- Set pricing gave consulting an hourly rate. That is only half a policy: an
-- hourly rate with no cap is an open-ended commitment against one human's
-- calendar, and the first client to discover it consumes the week.
--
-- The rule: THREE SESSIONS PER WEEK PER BUSINESS, booked on the internal
-- calendar. A fourth is refused by the database, because a cap that lives in
-- a prompt is a cap a client can talk an agent out of.
--
-- Two limits, and they are different:
--   * per-client entitlement — 3 sessions in any Monday-start week
--   * whole-firm capacity     — one human's calendar, surfaced not enforced,
--                               because the right response to a full week is
--                               a judgment call, not a rejection.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0009_consulting_sessions.sql

SET search_path TO godly, public;

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

INSERT INTO godly.schema_migrations (version, note)
VALUES ('0009_consulting_sessions', 'Consulting as scheduled sessions: three a week per business, enforced by trigger; internal calendar load surfaced.')
ON CONFLICT (version) DO NOTHING;
