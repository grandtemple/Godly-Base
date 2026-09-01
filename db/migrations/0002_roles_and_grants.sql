-- 0002_roles_and_grants — least privilege for the local cloud.
--
-- Optional but recommended. Requires a role with CREATEROLE (or superuser);
-- skip it and everything still works, it just all runs as the owner.
--
-- This is the answer to "should this schema have RLS?". It should not: one
-- tenant, one company, no browser-facing Postgres, no per-user rows. What it
-- does need is that agents connect as something other than the owner, and that
-- read-only consumers (the codex, scripts/extract.py) cannot write.
--
-- Roles are cluster-wide, so creation is guarded and re-runnable. Passwords are
-- NOT set here — set them out of band, or use peer/scram auth in pg_hba.conf, so
-- no secret is ever committed.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'godly_app') THEN
    CREATE ROLE godly_app NOLOGIN;      -- the agents' write role
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'godly_readonly') THEN
    CREATE ROLE godly_readonly NOLOGIN; -- the codex, exports, dashboards
  END IF;
END $$;

-- Nobody gets anything by being logged in.
REVOKE ALL ON SCHEMA godly FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA godly FROM PUBLIC;

GRANT USAGE ON SCHEMA godly TO godly_app, godly_readonly;

GRANT SELECT ON ALL TABLES IN SCHEMA godly TO godly_readonly;

-- No DELETE for the agents: rows in this schema are the company's memory, and
-- removing one is a human act. Agents mark, they do not erase.
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA godly TO godly_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA godly TO godly_app;

-- Same rules for whatever the next migration creates.
ALTER DEFAULT PRIVILEGES IN SCHEMA godly
  GRANT SELECT ON TABLES TO godly_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA godly
  GRANT SELECT, INSERT, UPDATE ON TABLES TO godly_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA godly
  GRANT USAGE ON SEQUENCES TO godly_app;

INSERT INTO godly.schema_migrations (version, note)
VALUES ('0002_roles_and_grants', 'godly_app (no delete) and godly_readonly roles; public revoked.')
ON CONFLICT (version) DO NOTHING;
