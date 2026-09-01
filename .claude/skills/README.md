# Skills

Four executable skills for the daily work in `config/agents.yaml`. Each one
encodes a job that already has an owner, a duo partner, and a guardrail that
costs money or standing when it is skipped. They load automatically when the
work matches; the descriptions in each `SKILL.md` frontmatter are what makes
that happen.

| Skill | The job | Owner | Duo partner |
|---|---|---|---|
| [`prospect-research`](prospect-research/SKILL.md) | Crawl a niche, corroborate ownership from two independent sources, write `accounts` + `contacts` without breaking source terms or the Hunter allowance | `AG-RES-01` Market Scraper | `AG-RES-02` Ownership Verifier |
| [`custom-proposal`](custom-proposal/SKILL.md) | Draft a proposal specific to one client from the account note and niche playbook, priced before it ships, never below floor margin without CEO sign-off | `AG-SALES-02` Proposal Architect | `AG-FIN-01` Unit Economics |
| [`decision-record`](decision-record/SKILL.md) | Write the one memory format — question, numbers, decision, rejected, reverses_if — to `/brain/decisions` and mirror it into `godly.decisions` | Supervisors (`SUP-*`), agents propose | The chief or CEO who ruled |
| [`daily-brief`](daily-brief/SKILL.md) | Sweep `agent_runs`, weighted pipeline, and credit burn into the one page the CEO reads, routed by the escalation ladder | All seven supervisors | `SUP-FIN` holds company-wide burn |

They compose. A prospect run that changes a threshold writes a decision record;
a proposal priced below floor needs CEO sign-off, which is a decision record;
the daily brief cites the records filed that day so tomorrow's brief does not
re-argue them.

Doctrine they enforce lives in [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md)
(chain of command, the double-agent rule, the memory split, the guardrails),
the roster in [`config/agents.yaml`](../../config/agents.yaml), the tables in
[`db/schema.sql`](../../db/schema.sql), and the source verdicts in
[`docs/RESEARCH-INDEX.md`](../../docs/RESEARCH-INDEX.md).

Also in `.claude/`: the four-stage feature pipeline (`agents/`, `commands/ship.md`)
for changing this repository's code. Skills are for running the business; the
pipeline is for building the machine.
