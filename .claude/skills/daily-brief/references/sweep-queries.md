# Sweep queries

Against `godly` (PostgreSQL 15+, `db/schema.sql`). Substitute the department's
agent ids or filter on `agents.department`. `:since` is the timestamp of your
last brief — for a daily supervisor that is roughly `now() - interval '24 hours'`.

Without `DATABASE_URL`, the same rows come from the committed seed:

```bash
python scripts/extract.py --list
python scripts/extract.py --table agent_runs --format json
python scripts/extract.py --table deals --format csv --out exports/
python scripts/extract.py --table api_keys --format json     # → godly.integrations
```

`--where` is ignored in seed mode; filter after extraction.

## 1. Exceptions since the last brief

```sql
SELECT r.id, r.agent_id, a.name, r.task, r.started_at,
       r.status, r.rows_touched, r.cost_usd, r.note_path
FROM godly.agent_runs r
JOIN godly.agents a ON a.id = r.agent_id
WHERE r.started_at > :since
  AND r.status <> 'ok'
  AND a.department = :dept
ORDER BY
  CASE r.status WHEN 'failed' THEN 0 WHEN 'review' THEN 1 ELSE 2 END,
  r.started_at;
```

## 2. Two consecutive failures — the chief's trigger

```sql
WITH ranked AS (
  SELECT agent_id, status,
         row_number() OVER (PARTITION BY agent_id ORDER BY started_at DESC) AS rn
  FROM godly.agent_runs
)
SELECT agent_id
FROM ranked
WHERE rn <= 2
GROUP BY agent_id
HAVING count(*) FILTER (WHERE status = 'failed') = 2;
```

## 3. Weighted pipeline, and what moved

```sql
-- current position
SELECT stage, deals, value_usd, weighted_usd FROM godly.pipeline_by_stage
ORDER BY array_position(ARRAY['New','Qualified','Discovery','Proposal',
                              'Negotiation','Closed Won','Closed Lost'], stage);

-- total to quote in the brief
SELECT round(sum(value_usd * probability)) AS weighted_open_usd
FROM godly.deals
WHERE stage NOT LIKE 'Closed%';

-- opened and closed since the last brief
SELECT id, account_id, stage, value_usd, probability, owner_agent, next_action
FROM godly.deals
WHERE opened_at >= :since::date OR closed_at >= :since::date
ORDER BY value_usd DESC;

-- stalls: open deals with no run touching them lately
SELECT d.id, d.account_id, d.stage, d.value_usd, d.next_action, d.opened_at
FROM godly.deals d
WHERE d.stage NOT LIKE 'Closed%'
  AND d.opened_at < current_date - interval '14 days'
ORDER BY d.value_usd * d.probability DESC;
```

There is no deal stage-history table, so "movement" is the weighted total
compared with the figure in your previous brief, plus the opened/closed rows
above. Keep yesterday's number in the brief note so today's delta is computable;
`godly.funnel_snapshots` carries the same idea for marketing stages
(`UNIQUE (captured_on, stage)` — one row per stage per day).

## 4. Credit burn against allowances

```sql
SELECT id, service, env_var, status, used, quota, unit,
       round(100 * used / nullif(quota, 0), 1) AS pct
FROM godly.integrations
WHERE quota > 0
  AND used / nullif(quota, 0) >= 0.75
ORDER BY pct DESC;
```

75% is the line worth mentioning. 90% is where `AG-FIN-02` pauses the consuming
agent and files a `warn` run — at that point the brief explains the pause, not
the percentage. `quota = 0` means self-hosted and unmetered (Crawl4AI, Postiz,
Twenty, Obsidian) — skip those. Hunter (`KEY-03`, 50 credits/mo at 0.5 per
verify) and Instantly sends are the two that bite.

## 5. Spend against the escalation ladder

```sql
-- today, by agent
SELECT r.agent_id, a.name, round(sum(r.cost_usd), 2) AS usd, count(*) AS runs
FROM godly.agent_runs r
JOIN godly.agents a ON a.id = r.agent_id
WHERE r.started_at >= current_date
GROUP BY r.agent_id, a.name
ORDER BY usd DESC;

-- today, total — compare against $50/day unplanned → chief
SELECT round(sum(cost_usd), 2) AS usd_today
FROM godly.agent_runs WHERE started_at >= current_date;

-- month to date — compare against $500/mo unplanned → CEO
SELECT round(sum(cost_usd), 2) AS usd_mtd
FROM godly.agent_runs WHERE started_at >= date_trunc('month', current_date);
```

`agent_runs.cost_usd` does not distinguish planned from unplanned spend. Compare
the total against the day's declared plan; when the split is genuinely unclear,
treat the excess as unplanned and say so in the brief.

## 6. Seven-day load, for context on an agent that is misbehaving

```sql
SELECT id, name, department, duo_partner, runs_7d, cost_7d
FROM godly.agent_load_7d
WHERE department = :dept
ORDER BY cost_7d DESC;
```

## 7. Waiting on a human

Manual BBB / TruePeopleSearch lookups are not a table — they live in the
verifier's queue (`/brain/agents/ag-res-02.md`, shape in the `prospect-research`
skill). The database proxy is accounts stuck without corroboration:

```sql
SELECT id, name, city, niche_id, source, fit_score, created_at
FROM godly.accounts
WHERE owner_verified IS NULL
ORDER BY created_at;
```

Report the count and the age of the oldest, not the list.
