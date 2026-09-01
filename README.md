# Hero Capital OS

Operating system for **Hero Capital** — a parent company governing three operating
domains plus a shared AI + governance platform.

> Full spec: [`HERO_CAPITAL_OS_V2_BUILD_MAP.md`](HERO_CAPITAL_OS_V2_BUILD_MAP.md)

## Umbrella

| Domain | Scope |
| --- | --- |
| **NIT Digital Agency** | CRM, marketing ops, client onboarding, proposals, software delivery, automation, analytics, billing |
| **Trading & Investments** | Research, equity analysis, market data, backtesting, portfolio analytics, risk engine, broker adapters, approvals, journal/audit |
| **Real Estate** | Sourcing, acquisition pipeline, underwriting, due diligence, comps, document room, vendor & asset management, portfolio valuation |

Healthcare/FHIR is an installed **future capability only** — not an operating company.

## Shared platform

1. **Hero Capital Command Center** — parent-level governance, portfolio KPIs, approvals, audit visibility, AI activity
2. **Supabase / Postgres** — identity, company-scoped records, RLS, migrations, pgvector for semantic memory
3. **AI Orchestrator** — Claude, OpenAI, local llama.cpp brain, company/context routing
4. **Hero Capital MCP** — narrow, company-aware tools; document access, reporting, workflow requests; no unrestricted production shell/DB access
5. **Policy & Risk** — deterministic authorization, approval thresholds, trading limits, money-movement controls, kill switches
6. **Audit** — actor, agent/model, company, tool/action, approval, trace, result

## Control flow

```
User or scheduled workflow
  -> Hero Capital AI Orchestrator
  -> domain agent
  -> approved MCP tool
  -> policy / risk engine
  -> human approval (when required)
  -> service / database / API action
  -> audit event
```

For trading:

```
AI thesis -> deterministic risk check -> approval -> broker adapter -> execution -> audit + portfolio update
```

**The model never becomes the risk engine.**

## This repo

Early scaffold. Current contents:

| Path | Purpose |
| --- | --- |
| `HERO_CAPITAL_OS_V2_BUILD_MAP.md` | Authoritative build map / spec |
| `main.py` | FastAPI local cloud server (health check + Resend email endpoint) |
| `requirements.txt` | Python dependencies |
| `.env.example` | Required environment variables |
| `.claude/` | Multi-agent pipeline (Planner / Coder / Tester / Reviewer) + `/ship` command — on branch `claude/multi-agent-pipeline-c5r9g4` |

## Running the server

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # then fill in RESEND_API_KEY
uvicorn main:app --reload
```

- `GET /health` — liveness + whether Resend is configured
- `POST /send-email` — `{ to, subject, html, sender? }`
