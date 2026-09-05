-- 0010_auth — the credential boundary Phase 2 requires before any write
-- endpoint is safe to expose. See docs/ROADMAP.md, Phase 2.
--
-- One operator today: the CEO seat. Client-facing logins, SSO, and
-- per-deployment RBAC are explicitly out of scope here — see Phase 13.
-- Passwords are hashed by the API (bcrypt) before they ever reach this
-- table; nothing plaintext is written or logged. Create the first operator
-- with scripts/create_operator.py, not by hand.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0010_auth.sql

SET search_path TO godly, public;

CREATE TABLE IF NOT EXISTS operators (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email         text NOT NULL UNIQUE,
  password_hash text NOT NULL,        -- bcrypt; the API hashes, never stores plaintext
  display_name  text NOT NULL,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_login_at timestamptz
);
COMMENT ON TABLE operators IS
  'Hero''s own internal users (the CEO seat today). Not client-facing.';

-- godly_readonly backs the OS dashboard and scripts/extract.py — both are
-- read surfaces a client or a casual export could eventually reach. A
-- password hash must never sit behind that role, so this table is carved
-- out of the blanket `GRANT SELECT ON ALL TABLES` in 0002_roles_and_grants.sql.
-- NOTE: if 0002 is applied or re-applied AFTER this table exists, its
-- blanket grant re-runs and re-exposes this table — re-run the REVOKE below.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'godly_readonly') THEN
    REVOKE SELECT ON operators FROM godly_readonly;
  END IF;
END $$;

INSERT INTO godly.schema_migrations (version, note)
VALUES ('0010_auth', 'Operators table — the credential boundary before any write endpoint; excluded from godly_readonly.')
ON CONFLICT (version) DO NOTHING;
