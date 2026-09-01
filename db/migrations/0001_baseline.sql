-- 0001_baseline — the v1 shape of the godly schema.
--
-- The baseline is not copied here: it *is* db/schema.sql, included below, so the
-- two can never drift. Every later migration is a hand-written, idempotent
-- ALTER script in this directory and is also folded back into schema.sql, which
-- always describes the current shape.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0001_baseline.sql
--
-- \ir resolves relative to this file, so run it from anywhere.

\ir ../schema.sql

INSERT INTO godly.schema_migrations (version, note)
VALUES ('0001_baseline', 'Initial godly schema: roster, sales core, marketing, nerve, brain, read models.')
ON CONFLICT (version) DO NOTHING;
