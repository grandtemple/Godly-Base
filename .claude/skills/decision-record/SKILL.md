---
name: decision-record
description: Use when a Godly Base agent or supervisor has chosen between real alternatives — changing a threshold, rationing a credit allowance, pricing below floor margin, dropping or adopting a source or tool, opening a niche, or ruling on an escalation — and the reasoning needs to survive in the Obsidian vault rather than only as a run row. Also use when someone asks why a past choice was made and nothing but numbers can be found.
---

# Decision record

Postgres remembers *what happened*. The vault at `/brain` remembers *what it
meant*. Agents that read only the first repeat last quarter's mistakes with
better formatting — the run row shows that Hunter verification was rationed, but
only the record says the alternative was 41× over allowance and that a 3% bounce
rate for two weeks would reverse it.

There is one format. Not one per department, not one per supervisor. A vault
with three formats is a vault nobody greps.

## Does this earn a record?

A run row is the default. Records are for choices, and most work is execution.

Write a record when **any** of these is true:

- A real alternative was rejected. Somebody could reasonably have chosen
  differently.
- The choice changes standing behavior — a threshold, a cadence, a routing rule,
  what a tool is used for.
- It commits money or capacity beyond a single run: an allowance ration, a
  below-floor price, a term, a tier.
- It was an escalation outcome. Every chief or CEO ruling gets a record; that is
  what makes the ruling reusable instead of a memory.
- Reversing it later would cost real work.

A run row is enough when the work was routine, no alternative was seriously in
play, and undoing it costs nothing — a crawl completed, a sequence step sent, a
webhook retried, a post scheduled. Filing records for those buries the ones that
matter.

**The six-month test.** If a competent agent reading only the Postgres rows six
months from now would ask "why on earth did we do that?", write the record.

**The reversal test.** If you cannot name a condition that would reverse the
choice, you do not have a decision yet — you have a preference. Either find the
condition or do not file the record.

## The format

Frontmatter in a vault note. Eight keys, these names, this order.

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

Below the frontmatter, prose is optional and short: context a future reader
needs that the eight fields cannot carry. If the prose is longer than the
frontmatter, the frontmatter is not doing its job.

| Field | What good looks like |
|---|---|
| `id` | `DEC-<YYYY-MM-DD>-<slug>`, the date decided, slug in words a person would search |
| `owner` | The supervisor or chief id who owns it (`SUP-FIN`, `SUP-SALES`), or `CEO`. Supervisors write records; agents propose them |
| `question` | The actual fork, phrased as a question with two live sides |
| `numbers` | The arithmetic that decided it, with units. This field is why the record is trustworthy — if it is empty, say so and explain why there were no numbers |
| `decision` | What is now true, in the present tense, specific enough to act on |
| `rejected` | The alternative *and why it lost*. "Bulk verification at scrape time — 41x over allowance" not "bulk verification" |
| `reverses_if` | A measurable condition with a threshold and a window. "Bounce > 3% for two consecutive weeks", not "if it stops working" |
| `links` | Where the evidence lives: table rows by primary key, and vault paths |

`assets/decision-record.md` is the blank to copy.

### Writing `reverses_if` so it can actually fire

A reversal condition nobody can observe is decoration. Make it something that
shows up in a sweep the supervisor already runs:

- ✅ `Hunter allowance raised above 200 credits/mo, or bounce rate > 3% for 2 weeks`
- ✅ `Any partner tier produces < 2 intros/mo for a full quarter`
- ✅ `Firecrawl monthly pages exceed 2,400 (80% of quota) for 2 consecutive months`
- ❌ `If the numbers change` · `If it becomes a problem` · `Revisit in Q4`

A date alone is a review reminder, not a reversal condition. If the honest answer
is time-based, name what you expect to be true by then.

## Where it is written

The note goes in the Obsidian vault:

```
/brain/decisions/DEC-2026-08-14-hunter-rationing.md
```

`/brain/decisions` is written by supervisors and read by every agent on every
run. Related material lives elsewhere and is linked, never duplicated:
`/brain/niches/<slug>.md` for playbooks, `/brain/accounts/<slug>.md` for account
history, `/brain/agents/<id>.md` for standing instructions. Google Drive is the
outward face — client-facing only, never the memory.

Then mirror it into `godly.decisions` so the codex and the Vault chapter can see
it. The row carries the same fields plus `vault_path` and `linked_tables`:

```sql
INSERT INTO godly.decisions
  (id, owner, question, numbers, decision, rejected, reverses_if,
   vault_path, linked_tables)
VALUES
  ('DEC-2026-08-14-hunter-rationing', 'SUP-FIN',
   'Verify every scraped contact, or only pre-send?',
   '4,180 scraped/mo · 50 free credits · 0.5 credit per verify',
   'Verify at send time only; queue the rest unverified.',
   'Bulk verification at scrape time — 41x over allowance.',
   'Bounce rate > 3% for two consecutive weeks.',
   '/brain/decisions/DEC-2026-08-14-hunter-rationing.md',
   ARRAY['godly.contacts','godly.integrations']);
```

The vault note and the row are one decision in two memories. Writing one without
the other is how the codex ends up showing a decision nobody can read, or a note
nobody can find.

## Linking back to Postgres by primary key

`links` and `linked_tables` should let a reader land on the exact rows the
decision was made from. Prefer a key over a table name — a table name says
"somewhere in here", a key says "this row".

- `godly.accounts:ACC-1041` — the account
- `godly.deals:DEAL-901` — the deal that forced the question
- `godly.agent_runs:88406` — the run that surfaced it (`agent_runs.id` is a
  bigserial; use the numeric id)
- `godly.integrations:KEY-03` — the allowance being rationed
- `godly.contacts` — table-level, when the decision genuinely applies to all rows

One wrinkle worth knowing: the canonical example above (and `brain_map`) writes
`godly.contacts`, while `db/schema.sql` creates the tables in the `godly`
schema. Write new links as `godly.<table>` — matching what a reader can actually
query — and leave existing records alone rather than churning the vault.

Close the loop from the other side too: the run that produced the decision sets
`agent_runs.note_path` to the vault path, so anyone reading the ledger can walk
straight to the reasoning.

## Common failures

| Failure | Why it hurts | Fix |
|---|---|---|
| No `numbers` | The record becomes an opinion; the next agent re-argues it | Put the arithmetic in, or state plainly that there was none |
| `rejected` names the option but not the reason | The alternative gets re-proposed next quarter | Add the cost that killed it |
| Unobservable `reverses_if` | The decision outlives the conditions that justified it | Tie it to something a supervisor sweep already sees |
| Record without a row (or a row without a note) | Half the company cannot see it | Write both, same session |
| Records filed for routine runs | Signal drowns; nobody reads `/brain/decisions` any more | Apply the six-month test |
| Vault path in `links` but no primary key | Reader cannot find the evidence | Link the row, not just the table |
