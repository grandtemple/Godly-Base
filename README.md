# Godly Base

Godly Base is the operating system of a services firm that sells sales,
marketing, and research retainers to four trades: roofing and restoration, med
spa, commercial HVAC, and private security. The interface is a codex: the left
page carries the reasoning, the right page carries the working instrument, and
every number on both comes out of one database you can open, filter, sort, and
take with you.

**The firm goes to market as Hero.** "Godly Base" is the internal name for the
machine — this repository, the codex, the vault, the agent roster — and a client
never hears it. Anything a client can see says Hero, or Hero Capital where a
registered entity name is required. Godly, the Christian community app, is a
separate product by the same owner. The rules are in
[docs/BRAND.md](docs/BRAND.md).

```
web/godly-codex.html     the codex — 9 leaves, opens in any browser
db/schema.sql            Postgres schema for every data point we keep
db/seed.json             the rows the codex ships with
config/agents.yaml       the roster: 7 chiefs, 7 supervisors, 21 paired agents
config/.env.example      the nerve — key names only, never values
scripts/extract.py       CSV/JSON extraction from live Postgres or the seed
docs/ARCHITECTURE.md     chain of command, memory rules, guardrails
docs/RESEARCH-INDEX.md   40 linked sources, each with a verdict
```

## The leaves

| | Chapter | What it holds |
|---|---|---|
| — | Frontispiece | Vitals, agent throughput, today's run ledger |
| I | The House | Org chart: CEO → chief → supervisor → paired agents |
| II | Book of Accounts | Sales pipeline, deal marginalia, account file |
| III | Book of Signals | Marketing funnel, campaigns, editorial calendar |
| IV | Book of Alliances | Partnership pipeline and program tiers |
| V | The Vault | All twelve tables — filter, sort, extract as CSV or JSON |
| VI | The Nerve | Integration registry, credit meters, local cloud |
| VII | The Appendix | The research index with live links and verdicts |
| VIII | The Brain | Obsidian/Drive routing, decision records, room to grow |

Chapter tabs run down the spine; `←` and `→` turn leaves.

## Running it

The codex is a single file with no build step and no dependencies:

```bash
open web/godly-codex.html        # macOS; xdg-open on Linux, start on Windows
python3 -m http.server           # or serve the repo and visit /web/
```

The database and the extraction tool:

```bash
psql "$DATABASE_URL" -f db/schema.sql
python scripts/extract.py --list
python scripts/extract.py --table deals --format csv --out exports/
```

With `DATABASE_URL` set, `extract.py` reads live Postgres; without it, the
committed seed. Either way the columns and order match what the Vault shows.

## The rules that shape it

- **Every agent is paired.** An output no counterpart has seen is a draft.
- **Two memories.** Postgres holds what happened; the Obsidian vault holds what
  it meant, in one decision-record format with a reversal condition.
- **The local cloud holds the record.** Postgres, CRM, crawler, scheduler, and
  brain run on our own hardware. Rented services are metered and pausable.
- **No secrets in data.** The integrations table holds env var *names* and burn.
- **BBB and TruePeopleSearch stay manual.** No public API, and terms that
  prohibit bulk automation.
- **Sending reputation outranks send volume.** LinkedIn goes through a
  compliant API, and a bounce rate over 3% for two weeks stops the domain.

Details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); the stack shopping list
with verdicts is in [docs/RESEARCH-INDEX.md](docs/RESEARCH-INDEX.md).

---

### Also in this repository

A four-stage feature pipeline for Claude Code — Planner → Coder → Tester →
Reviewer, chained by `/ship` and handing off through files in `.pipeline/`.
Agent definitions live in `.claude/agents/`, the orchestrator in
`.claude/commands/ship.md`. The pipeline never merges; it stops at the
Reviewer's verdict.
