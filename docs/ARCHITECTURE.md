# Godly Base — architecture

An AI company that reads as a book. One human seat, seven chiefs, seven
supervisors, twenty-one agents, one database, one brain.

## Three parties, and the words for them

Every table, every agent charter and every piece of copy uses these words and
only these words. Getting them mixed up is how a client's customer ends up in a
Hero prospecting list.

| Word | Who | Where they live |
|---|---|---|
| **Hero** | us | the whole of this repository |
| **The client** | the business owner who buys a pod | `godly.accounts`, and `godly.contacts` for the people at that business |
| **The customer** | the client's customer — whoever buys their roof, their facial, their service call | `godly.customers`, scoped to one pod |

`contacts` is Hero's prospects. `customers` is the client's. They are different
tables on purpose, and nothing should ever move a row between them.

### The customer data is not Hero's

Hero is the processor. The client is the controller. Practically:

- **Isolation is enforced by the database.** The five customer tables carry
  row-level security keyed on `deployment_id`, FORCED so the table owner is
  subject to it too. A pod with no tenant set reads zero rows — it fails closed.
- **Export and deletion are the client's call**, and `scripts/extract.py` will
  produce their data on request in CSV or JSON.
- **Consent is enforced by a trigger**, not a prompt. An agent that dials and
  texts consumers is inside TCPA; do-not-contact and per-channel consent are
  checked on insert, because an agent can be argued out of an instruction and
  cannot be argued out of a constraint.
- **Nothing is pooled across clients.** One client's customer list never trains,
  informs or seeds anything for another, and there is no table where it could.

## The four layers

| Layer | What it is | Where it runs |
|---|---|---|
| **The OS** | `web/hero-os.html` — the interface. Ten modules behind a fixed rail; the URL is the state. | Anywhere; published as an Artifact |
| **The vault** | Postgres (`db/schema.sql`), schema `godly`. Every data point the business keeps. | Local cloud |
| **The nerve** | Integrations registry + API keys, scoped per agent. | Local cloud + metered APIs |
| **The brain** | Obsidian vault at `/brain`, served over MCP. Decisions, playbooks, account notes. | Local cloud |

## Chain of command

```
CEO (human)
 └── Chief (7: CSO CMO CBDO CTO CIO CCO CFO)
      └── Supervisor (1 per department)
           └── Agents (3 per department, each paired with a named counterpart)
```

**The double-agent rule.** Every agent has a duo partner recorded in
`config/agents.yaml` and in `godly.agents.duo_partner`. Pairs cross departments
where the check is more useful there: the proposal architect pairs with unit
economics, the writer with the fact-checker, the prospector with the qualifier.
An output no partner has seen is a draft, not a deliverable.

**Escalation.** `warn`/`review`/`failed` runs go to the supervisor. Two
consecutive failures, or unplanned spend over $50/day, go to the chief.
Contract terms, a new niche, or unplanned spend over $500/month go to the CEO.
The CEO reads seven briefs a day, never raw runs.

**Growth.** A department earns a fourth agent by showing a queue its three
cannot clear for two consecutive weeks. Pairs before agents, agents before
departments, departments before tiers.

## Two memories, kept separate

Postgres remembers *what happened* — rows, amounts, timestamps, costs. The
Obsidian vault remembers *what it meant* — the decision, the alternative
rejected, the condition that would reverse it. Agents that read only the first
repeat last quarter's mistakes with better formatting.

Every run writes a row (`godly.agent_runs`). Every *decision* writes a note in
one format only:

```yaml
---
id: DEC-2026-08-14-hunter-rationing
owner: SUP-FIN
question: Verify every scraped contact, or only pre-send?
numbers: 4,180 scraped/mo · 50 free credits · 0.5 credit per verify
decision: Verify at send time only; queue the rest unverified.
rejected: Bulk verification at scrape time — 41x over allowance.
reverses_if: Bounce rate > 3% for two consecutive weeks.
links: [godly.contacts, /brain/agents/ag-res-02]
---
```

Google Drive holds only what a client opens: proposals, contracts, deliverables,
handed-over exports. It is the outward face, never the memory.

## Getting the data out

The codex's Vault chapter filters any table and copies it as CSV or JSON. For
files on disk:

```bash
python scripts/extract.py --list
python scripts/extract.py --table deals --format csv --out exports/
python scripts/extract.py --table contacts --where "email_status='verified'" --format json
python scripts/extract.py --all --out exports/
```

With `DATABASE_URL` set it reads live Postgres; without it, the committed seed
in `db/seed.json`. Secrets are never in the database or the UI — the
`integrations` table holds env var *names* and usage, never values.

## Guardrails that are not negotiable

- **Credit warden (AG-FIN-02)** pauses the consuming agent at 90% of any monthly
  allowance and files a `warn` run. Hunter's free tier is 50 credits/month and a
  verify costs 0.5 — verification is rationed to contacts about to be emailed.
- **BBB.org and TruePeopleSearch stay manual.** No public API, terms that
  prohibit bulk automation. The verifier queues them for a human, one at a time,
  and records the corroboration rather than the page.
- **LinkedIn goes through a compliant API** (Unipile), never browser automation
  that gets accounts banned.
- **Sending reputation is the asset.** Bounce rate over 3% for two weeks stops
  the sending domain, not the campaign.

## Niches

Four, served in depth: Roofing & Restoration, Med Spa & Aesthetics, Commercial
HVAC & Facilities, Private Security Services. Each has its own playbook,
vocabulary, objection set, and proof in `/brain/niches/`. A fifth is added only
when the fourth runs without the CEO in the loop.
