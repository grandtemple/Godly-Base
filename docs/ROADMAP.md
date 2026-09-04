# Hero Capital OS — Chronological Build Plan to 100% Operable

## Context

This repo (`grandtemple/Godly-Base`, internal name only — unrelated to a separate "Godly" Christian app) is the internal build for **Hero Capital OS**, an AI-front-office-in-a-box sold to regional service businesses (roofing & restoration, med spa & aesthetics, commercial HVAC & facilities, private security). A 7-chief / 7-supervisor / 21-agent org structure (`config/agents.yaml`) reports to one human CEO.

Two branches carried this product's history as **unrelated git histories** (no common ancestor — verified directly with `git merge-base`, not assumed) until Phase 0 merged them here:
- `origin/main` (3 commits): a vision-only `HERO_CAPITAL_OS_V2_BUILD_MAP.md` describing a 3-company umbrella (agency + trading + real estate) that is **explicitly out of scope** — only the agency is being built — plus a bare `main.py` (FastAPI, only `/health` and `/send-email` via Resend, no DB, no auth). Now archived at `docs/archive/HERO_CAPITAL_OS_V2_BUILD_MAP.md`; `main.py` moved to `api/main.py`.
- `origin/claude/ai-unit-os-book-dashboard-v09iok` (14 commits): the **real build** — a 38-table Postgres schema + 9 migrations, seed data, a 4,331-line static read-only dashboard (`web/hero-os.html`), the full agent roster YAML, and docs (architecture, brand, growth, payments, research index). Confirmed directly: **no auth/operator/session table exists anywhere in `db/schema.sql`**.

Nothing currently runs end-to-end: the dashboard reads a build-time-embedded JSON snapshot, `config/agents.yaml` is a static roster nothing executes, and `docs/PAYMENTS.md` explicitly states no live Stripe key exists. This plan sequences the work from that state to a fully operating, multi-client product.

**Decisions locked in for this plan:**
- Scope is the single AI agency only — trading and real estate are permanently out of scope.
- Base branch: this branch (unified from `main` + `ai-unit-os-book-dashboard-v09iok`) is the one source of truth going forward.
- **Milestone A** ("one real client running end-to-end") is a hard gate — nothing in the post-gate phases starts before it is verifiably met.
- **Milestone B** ("full production scale") is the final target.
- Orchestrator substrate: **both**, sequenced — Phase 6's single-capability proof runs on native Claude Code primitives (Skill/subagents/cron), no new framework; Phase 9's full supervisor→agent runtime adopts **LangGraph** (already marked `adopt` in `docs/RESEARCH-INDEX.md`) once individual jobs are proven.
- Phone/voice automation (FO-01/FO-02) is **not** required for Milestone A — a human answers phones during the pilot; automating it is deferred to Phase 11a, after the gate.

---

## Phase 0 — Repository unification ✅ done
**Goal:** one branch, one source of truth.
- Merged `origin/main` into the real build (`--allow-unrelated-histories`, since the two shared no common ancestor). Kept this branch's `.gitignore`/`README.md`; took main's `main.py` (moved to `api/main.py`), `requirements.txt`, `.env.example` (merged into `config/.env.example`, which wins as canonical; root copy removed).
- Moved `HERO_CAPITAL_OS_V2_BUILD_MAP.md` to `docs/archive/` with a header noting trading/real-estate are out of scope.
- Fixed the stale path in `docs/BRAND.md` (`design-system/godly-base-codex/MASTER.md` → actual `design-system/hero-capital-os/MASTER.md`).
- **Exit criteria:** single branch builds; `db/README.md`'s apply steps and `node tools/build-data.js` still work identically.

## Phase 1 — Live database
**Goal:** a running Postgres 16 instance as the source of truth for dev/staging; nothing user-facing changes yet.
- Provision Postgres; apply `db/migrations/0001`→`0009` per `db/README.md`; run `0002_roles_and_grants.sql` (`godly_app`, `godly_readonly`).
- Load `db/seed.json` via `scripts/load_seed.py`.
- Extend `scripts/extract.py`'s existing `TABLES` mapping and `DATABASE_URL`-vs-seed fallback — reuse this, don't reinvent it in the API layer.
- Add `psycopg[binary]`/`asyncpg`, `pydantic-settings` to `requirements.txt`.
- **Dependency:** Phase 0. **Exit criteria:** `scripts/extract.py --table deals --format json` returns live rows matching seed shape.

## Phase 2 — Auth (built before any write endpoint)
**Goal:** a real credential boundary — required before Phase 3+ can safely expose anything.
- New migration `0010_auth.sql`: minimal `operators` table (starts with one row, the CEO) with hashed credentials + sessions/JWT. This is a genuine schema gap, not just an API gap.
- FastAPI auth guard wrapping every route from Phase 3 onward; a distinct scoped credential type for agent-originated calls vs. the CEO's own session.
- Out of scope: client-facing logins, SSO, per-deployment RBAC (Milestone B concern).
- **Dependency:** Phase 1. **Exit criteria:** unauthenticated mutating requests get 401; CEO can log in.

## Phase 3 — Live read path (dashboard off seed data)
**Goal:** first literal piece of Milestone A.
- Build read-only GET endpoints (via `godly_readonly`) over the existing views/tables (`pipeline_by_stage`, `agent_roster`, `deal_board`, `funnel_latest`, `revenue_now`, `collection_health`, etc.) — one combined `/api/snapshot` matching the shape `web/hero-os.html`'s `DB` object already expects.
- Replace the build-time-embedded `const DB = {...}` in `web/hero-os.html` with an async `fetch('/api/snapshot')` bootstrap before `render()` runs. Keep `tools/build-data.js`'s static embed as an explicit demo-mode fallback (useful for sales demos), not deleted.
- **Dependency:** Phases 1–2 (reads now expose real client-customer PII, sit behind auth). **Exit criteria:** editing a row in Postgres changes what the dashboard shows on next load, with zero `render()` changes.

## Phase 4 — Write path for sales/onboarding
**Goal:** turn a real prospect into a real, priced, deployed client.
- POST/PATCH endpoints for `accounts`, `contacts`, `deals`, `quotes`/`quote_lines` (the existing `enforce_set_pricing` trigger already rejects any line off `price_book.list_price` — no new validation needed), `retainers`, `deployments`, `deployment_capabilities`.
- Surface the existing consent trigger (`refuse_contact_without_consent()`) as a clean 4xx for `customer_interactions` inserts.
- Out of scope: agent-originated writes (Phase 6+), Stripe.
- **Dependency:** Phases 2–3. **Exit criteria:** a prospect can be quoted, accepted, and turned into a live `deployments` row entirely through the API.

## Phase 5 — Stripe Flow A only
**Goal:** second literal piece of Milestone A — live payments, Hero billing its own client.
- Wire `stripe` SDK; map `price_book`→Products/Prices, `retainers`→Subscriptions, `invoices`→Stripe Invoices.
- Webhook endpoint: idempotency is already a schema guarantee (`payment_events` `UNIQUE (provider, external_event_id)`) — the endpoint just inserts-then-processes.
- Reconcile into `payments` by `external_id` only, never amount+date (per `docs/PAYMENTS.md`'s stated failure mode).
- **Explicitly do not build Flow B** (Stripe Connect) yet — no client needs it yet, and it's the highest-risk piece (money-transmission boundary) to build speculatively.
- **Dependency:** Phase 4 (real `retainers` rows), Phase 2. **Exit criteria:** a real card charges in test then live mode against a real retainer; webhook → `payment_events` → `payments` reconciles; `revenue_now` reflects it.

## Phase 6 — One real capability made operationally real
**Goal:** "agents actually executing," scoped narrowly — not the full 21-agent roster.
- Pick capabilities with `adopt`-verdict vendors already researched: **FO-03 Inbox**, **FO-04 Booking**, **FO-05 Quote/estimate**, **FO-07 Review request**. Explicitly exclude FO-01/FO-02 (phone — no vendor researched, and not required for Milestone A per the locked decision).
- Execution mechanism (locked decision): run the already-written `.claude/skills/{prospect-research,custom-proposal,daily-brief,decision-record}` as real execution logic via native Claude Code triggers (scheduled/cron or CEO-invoked) writing through the Phase 4 API — not a bespoke orchestrator yet. Each run logs to `agent_runs` (its `run_ref`/`payload` columns already anticipate this).
- Enforce the double-agent rule manually (human confirms the duo partner's check) — automated pairing is premature before a single-agent loop is proven.
- **Dependency:** Phases 3–5. **Exit criteria:** at least one of FO-03/04/05/07 produces real rows from real triggering events, logged in `agent_runs`, for a real deployment.

## Phase 7 — MILESTONE A GATE: one real paying client, end-to-end
- Pick one niche with existing real funnel motion (per `docs/GROWTH-PLAN.md`'s current 513-reply/97-meeting pipeline).
- Run one real prospect through: quote → accept → `deployments` row (`stage='Running'`) → FO-03/04/05/07 operating against real customers for a full billing cycle → Stripe Flow A collects and reconciles a real payment → dashboard shows it all live.
- **Hard exit criteria (verify every one before Phase 8 starts):**
  1. One `deployments` row, `stage='Running'`, real business, niche assigned, FO-03/04/05/07 enabled in `deployment_capabilities`.
  2. `customers`/`jobs`/`customer_interactions`/`reviews` contain real rows for that `deployment_id` (RLS from migration `0006` exercised for real).
  3. At least one `retainers` row `active`, billed/collected via Stripe Flow A, matching `payments` row reconciled by `external_id`.
  4. One full billing cycle elapsed and collected, not just invoiced.
  5. Dashboard loaded fresh (no seed fallback) shows all of the above.

---
## MILESTONE A — HARD STOP. Do not begin Phase 8 until every Phase 7 exit criterion is verified true.
---

## Phase 8 — Brain MCP server
- Adopt `obsidian-mcp` over `/brain` (path already stubbed via `OBSIDIAN_VAULT_PATH`); enforce the decision-record format at write time, mirroring into `godly.decisions`.
- Deliberately sequenced after Milestone A (reversing `docs/RESEARCH-INDEX.md`'s "brain second" order) since nothing depended on it for the single-niche pilot — only one hand-written decision record exists today.
- **Dependency:** Milestone A gate met.

## Phase 9 — Orchestrator loop (LangGraph)
- Build the real supervisor→agent runtime on **LangGraph**, parsing `config/agents.yaml` directly as the roster source of truth (don't re-declare agents in code).
- Every step writes to `agent_runs` via its existing `run_ref`/`payload` columns.
- Enforce the double-agent rule and escalation thresholds (warn/review/failed→supervisor; 2 consecutive fails or >$50/day→chief; contract/new niche/>$500/mo→CEO) as real code paths.
- **Dependency:** Phase 6 (proved which jobs work), Phase 8 (somewhere real to write decisions).

## Phase 10 — Guardrails enforced in code
- Credit Warden: wire the orchestrator to check `integrations.usage_pct` (already a generated column) before any metered call, pausing at `CREDIT_WARN_THRESHOLD`.
- Sending-domain bounce ceiling (`SEND_DOMAIN_BOUNCE_CEILING`) as an automatic kill switch.
- BBB.org/TruePeopleSearch remain permanently human-queued/manual (compliance boundary, not technical — never automate). LinkedIn stays on Unipile's compliant API only.
- **Dependency:** Phase 9.

## Phase 11 — Remaining front-office capabilities
- **11a Phone (FO-01/FO-02):** net-new vendor research spike (Vapi/Bland/Retell/Twilio Voice) — zero prior research exists; treat as its own mini-milestone, sequence after Phase 10's guardrails given phone is the highest-stakes channel for a runaway agent.
- **11b Flow B (FO-06):** Stripe Connect Standard OAuth callback, nightly reconciliation sweep, FO-06 webhook — build only once a real client actually needs it.
- **11c FO-08/FO-09:** graduate from `pilot` to real per actual usage; no new infra needed.
- Before this phase starts producing agent-driven rows, disambiguate `front_office_capabilities.status='live'` (currently a commercial/marketing flag) from engineering status, to avoid the dashboard overclaiming capabilities that have never actually executed.
- **Dependency:** Phase 9 (all sub-phases), Phase 10 (before 11a specifically).

## Phase 12 — Niches 2, 3, 4
- Apply `docs/ARCHITECTURE.md`'s own stated gate ("a fifth niche only once the fourth runs without the CEO in the loop") one tier down: don't start niche 2 until niche 1 runs without the CEO in the loop.
- Each niche needs its own `/brain/niches/<slug>.md` playbook and vocabulary/objection content — content work, not schema work.
- Track `docs/GROWTH-PLAN.md`'s 35% reply-to-meeting gate (currently 19%) as a parallel business track, not an engineering dependency.
- **Dependency:** niche 1 running without CEO-in-the-loop.

## Phase 13 — Multi-tenant hardening
- Extend RLS-by-`deployment_id` beyond migration `0006`'s five tables only if/when client-side dashboard logins are introduced.
- Fix the pooled-connection GUC problem: `godly.current_deployment()` relies on session-level `SET app.deployment_id`, which doesn't survive a transaction-mode pooler — switch to `SET LOCAL` per request, verified under real concurrent multi-deployment load.
- Per-deployment resource isolation in the orchestrator so one client's stuck agent run can't starve another's queue.
- **Dependency:** Phases 9–12 (need multiple real concurrent deployments to harden against).

## Phase 14 — MILESTONE B: full production scale
- All 9 FO capabilities engineering-live (Phase 11), all 4 niches active with real clients (Phase 12), multi-client capacity hardened and load-tested (Phase 13), orchestrator + MCP server + code-enforced guardrails running in production with no manual workarounds remaining (Phases 8–10, verified against real usage).

---

## Verification approach per phase
- Phases 0–2: `git log`/`git diff` review, `psql` connectivity check, a manual login round-trip.
- Phases 3–5: manual end-to-end walkthrough in a browser against staging (load dashboard, create a deal, quote it, charge a Stripe test-mode card, confirm webhook → reconciled row), plus direct `psql` inspection of the affected tables.
- Phase 6–7: run the actual pilot — this phase's "test" is a real client, verified against the five hard exit criteria listed under Phase 7, checked directly in the database and the live dashboard, not simulated.
- Phases 8+: verify via the orchestrator's own `agent_runs` log for real (not seed) rows, and confirm guardrail kill-switches trip under a deliberately induced condition (e.g. a synthetic 91%-quota test) before trusting them in production.

## Critical files
- `db/schema.sql`, `db/migrations/0001`–`0009` (esp. `0006_client_customers.sql` for RLS, `0005_payments.sql` for the Flow A/B constraint)
- `docs/PAYMENTS.md`, `docs/ARCHITECTURE.md`, `docs/RESEARCH-INDEX.md`, `docs/GROWTH-PLAN.md`
- `config/agents.yaml`, `config/.env.example`
- `web/hero-os.html`, `tools/build-data.js`
- `scripts/extract.py`, `scripts/load_seed.py`
- `.claude/skills/{prospect-research,custom-proposal,daily-brief,decision-record}`
- `api/main.py`
