# Research index — the stack, with verdicts

Every source below is linked and marked with what we intend to do about it.
This is the same list the codex renders in Chapter VII (`db/seed.json` →
`godly.sources`), kept here so it is greppable and reviewable in a diff.

**Verdicts.** `adopt` — in the stack now or next sprint. `pilot` — one bounded
test with a decision date. `watch` — matters later, not now. `study` — a company
whose product decisions inform ours. `manual` / `restricted` — human in the loop
only, for terms-of-service reasons that are not negotiable.

## Agent frameworks

| Source | Kind | Verdict | Why it is on the list |
|---|---|---|---|
| [LangGraph](https://github.com/langchain-ai/langgraph) | OSS | `adopt` | Stateful graph orchestration with human-in-the-loop checkpoints — the spine for supervisor→agent handoffs. |
| [CrewAI](https://github.com/crewAIInc/crewAI) | OSS | `pilot` | Role-playing crews: fastest way to stand up a department of three agents and a supervisor. |
| [AG2 (AutoGen community fork)](https://github.com/ag2ai/ag2) | OSS | `watch` | Conversation-shaped multi-agent; Microsoft moved AutoGen into Agent Framework, AG2 carries the v0.2 lineage. |
| [Microsoft Agent Framework](https://github.com/microsoft/agent-framework) | OSS | `watch` | Where AutoGen + Semantic Kernel converged; relevant if we ever run on Azure. |
| [Dify](https://github.com/langgenius/dify) | OSS | `pilot` | Self-hostable LLM app platform — useful as the internal console for non-engineers. |
| [Frameworks comparison (2026)](https://www.firecrawl.dev/blog/best-open-source-agent-frameworks) | Reading | `read` | Current landscape read on adoption and trade-offs. |

## Scraping & research

| Source | Kind | Verdict | Why it is on the list |
|---|---|---|---|
| [Crawl4AI](https://github.com/unclecode/crawl4ai) | OSS | `adopt` | Local-first crawler, clean markdown out, no per-page fee — runs on our local cloud for bulk niche sweeps. |
| [Firecrawl](https://github.com/firecrawl/firecrawl) | OSS + API | `adopt` | Site → markdown/JSON with a mature hosted API; use for anything JS-heavy or awkward. |
| [Scrapling](https://github.com/D4Vinci/Scrapling) | OSS | `pilot` | Adaptive selectors that survive layout changes — cuts scraper maintenance. |
| [browser-use](https://github.com/browser-use/browser-use) | OSS | `pilot` | Agent drives a real browser; for portals and directories with no clean HTML. |
| [Scrapy](https://github.com/scrapy/scrapy) | OSS | `adopt` | The boring, reliable workhorse for scheduled large crawls. |
| [Crawlee](https://github.com/apify/crawlee) | OSS | `watch` | Node-side crawling with queue + proxy handling built in. |

## CRM & sales system

| Source | Kind | Verdict | Why it is on the list |
|---|---|---|---|
| [Twenty CRM](https://github.com/twentyhq/twenty) | OSS | `adopt` | Modern open-source Salesforce/HubSpot alternative, self-hosted, no per-seat cost — our system of record. |
| [EspoCRM](https://github.com/espocrm/espocrm) | OSS | `watch` | Lighter and feature-mature (mass email, IMAP sync, report builder) if Twenty proves heavy. |
| [HubSpot API](https://developers.hubspot.com/) | API | `adopt` | Mirror deals outward for clients who already live in HubSpot. |
| [Salesforce REST API](https://developer.salesforce.com/docs) | API | `watch` | Enterprise clients only; heavier integration cost. |

## Marketing & publishing

| Source | Kind | Verdict | Why it is on the list |
|---|---|---|---|
| [Postiz](https://github.com/gitroomhq/postiz-app) | OSS | `adopt` | Self-hosted scheduling to 30+ networks with AI drafting — the Octopost-shaped piece of the stack. |
| [Mautic](https://github.com/mautic/mautic) | OSS | `pilot` | Mature open marketing automation: nurture, scoring, landing pages. |
| [listmonk](https://github.com/knadh/listmonk) | OSS | `adopt` | Fast self-hosted newsletter + campaign sender; cheap at volume. |
| [n8n](https://github.com/n8n-io/n8n) | OSS | `adopt` | The connective tissue between CRM, sender, scraper, and the brain. |
| [Flowise](https://github.com/FlowiseAI/Flowise) | OSS | `watch` | Visual LLM flows for quick internal tools. |

## Sales intelligence

| Source | Kind | Verdict | Why it is on the list |
|---|---|---|---|
| [Apollo.io API](https://docs.apollo.io/reference/apollo-api) | API | `adopt` | 240M+ contacts, waterfall email/phone enrichment, MCP server. Seat-priced — meter it. |
| [Hunter.io API](https://hunter.io/api-documentation/) | API | `adopt` | Email finder (1 credit, only charged on a hit) + verifier (0.5 credit). Free tier is 50 credits/mo — the 50-credit mark to watch. |
| [Hunter Email Verifier](https://hunter.io/api/email-verifier) | API | `adopt` | Deliverability gate before any send; protects domain reputation. |
| [Clay](https://www.clay.com/) | SaaS | `adopt` | Waterfall enrichment across many providers in one table — best list-building surface today. |
| [BBB.org](https://www.bbb.org/) | Web | `manual` | Standing, complaints, and named principals. No public API — verifier agent reads it as a human would, no bulk scraping. |
| [TruePeopleSearch](https://www.truepeoplesearch.com/) | Web | `restricted` | Last-resort corroboration of an owner name already found elsewhere. Terms prohibit automated harvesting — keep it manual and logged. |
| [Unipile (LinkedIn API)](https://www.unipile.com/) | API | `pilot` | Compliant route to LinkedIn messaging and inbox sync instead of browser automation that gets accounts banned. |

## Brain & memory

| Source | Kind | Verdict | Why it is on the list |
|---|---|---|---|
| [obsidian-mcp](https://github.com/lstpsche/obsidian-mcp) | OSS | `adopt` | Dependency-free MCP server over the vault; works whether Obsidian is open or not. |
| [knowledge-base-server](https://github.com/willynikes2/knowledge-base-server) | OSS | `pilot` | SQLite FTS5 memory + Obsidian sync + MCP/REST — a candidate for the decision memory bank. |
| [awesome-mcp-servers](https://github.com/TensorBlock/awesome-mcp-servers) | Index | `read` | Directory of MCP servers; scan before building any connector by hand. |
| [Model Context Protocol](https://github.com/modelcontextprotocol) | Spec | `adopt` | The wire format the whole brain speaks. |

## Market watch

| Source | Kind | Verdict | Why it is on the list |
|---|---|---|---|
| [Jasper](https://www.jasper.ai/) | Company | `study` | Brand-context agents with knowledge bases; the benchmark for on-brand content at scale. |
| [Clay](https://www.clay.com/) | Company | `study` | Owns the enrichment layer; study their credit model before pricing ours. |
| [HeyGen](https://www.heygen.com/) | Company | `study` | AI avatar video — cheapest path to per-prospect video in proposals. |
| [Warmly](https://www.warmly.ai/) | Company | `study` | Signal-based orchestration: de-anonymize traffic, act in the moment. |
| [Smartly.io](https://www.smartly.io/) | Company | `study` | Paid-media automation; the model for closed-loop creative optimization. |
| [11x](https://www.11x.ai/) | Company | `study` | AI SDR positioning — direct comparison set for our outbound pod. |
| [Artisan](https://www.artisan.co/) | Company | `study` | 'AI employee' packaging; watch how they price a seat vs. an outcome. |
| [Regie.ai](https://www.regie.ai/) | Company | `study` | Sequence generation + agentic prospecting inside existing CRMs. |

## Build order

1. **Vault first.** `db/schema.sql` on the local cloud, then Twenty CRM against
   the same Postgres instance. Nothing else works without a system of record.
2. **Brain second.** Obsidian vault at `/brain`, an MCP server over it, and the
   decision-record format enforced from day one. Retrofitting memory is painful.
3. **Research pod third.** Crawl4AI locally, Firecrawl for pages that fight
   back, Hunter at send time only. This fills the vault with real rows.
4. **Outbound fourth.** Sequences through the SMTP pool, LinkedIn through
   Unipile, replies routed to the qualifier. Warm domains before volume.
5. **Publishing fifth.** Postiz for social, listmonk for the newsletter,
   n8n stitching the seams.
6. **Orchestration last.** LangGraph holds supervisor→agent state once the
   individual jobs are proven. Orchestrating work that does not yet work is how
   teams spend three months building a framework and shipping nothing.

## What we are deliberately not buying yet

Per-seat sales platforms (Apollo seats beyond one, 11x, Artisan) price the thing
we are building. We buy their *data* and study their *packaging*; we do not rent
their agents. Revisit when a niche pod is profitable and the constraint is
headcount rather than software.
