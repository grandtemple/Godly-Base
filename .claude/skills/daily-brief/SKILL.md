---
name: daily-brief
description: Use when a Godly Base supervisor is preparing the brief the CEO reads — the end-of-day or twice-daily sweep of agent_runs for warn/review/failed, weighted pipeline movement, credit burn against allowances, and anything needing a human decision. Also use when asked "what happened today", "what needs me", or for any status roll-up that would otherwise dump raw runs at the CEO.
---

# Daily brief

The CEO reads seven briefs a day and never raw runs. That is the contract: each
supervisor compresses their department's ledger into a page a person can act on
in two minutes. A brief that forwards the run table has done nothing — the
compression *is* the work.

Two failure modes, and the second is worse. A brief that hides an exception
costs the company a day. A brief nobody can finish reading costs the company the
habit.

## Cadence and scope

One brief per department, from that department's supervisor, covering everything
since the last brief:

| Supervisor | Department | Cadence |
|---|---|---|
| `SUP-SALES` (Ledger Prime) | CSO | hourly sweep · 18:00 brief |
| `SUP-MKT` (Herald Prime) | CMO | twice daily |
| `SUP-BD` (Bridge Prime) | CBDO | daily · weekly partner council |
| `SUP-DEV` (Forge Prime) | CTO | continuous |
| `SUP-RES` (Scriven Prime) | CIO | daily digest · weekly market report |
| `SUP-CNT` (Quill Prime) | CCO | daily editorial stand-up |
| `SUP-FIN` (Tally Prime) | CFO | daily spend check · weekly P&L |

`SUP-FIN` owns credit burn and spend across all seven departments; the other six
report their own agents' consumption and let finance hold the total.

## The sweep

Queries are in `references/sweep-queries.md` — run them, do not improvise SQL at
18:00. Order matters: exceptions before pipeline, because a green pipeline built
on a failed run is a lie.

1. **Exceptions.** Every `godly.agent_runs` row since the last brief where
   `status <> 'ok'`. Each one gets a disposition: fixed, retrying, queued for a
   human, or waiting on a decision. An exception with no disposition is the one
   thing that must never appear in a brief.
2. **Consecutive failures.** For each agent, check whether the two most recent
   runs are both `failed`. That crosses into the chief's lane automatically —
   it is not a judgment call.
3. **Pipeline movement.** Weighted value now versus at the last brief, from
   `pipeline_by_stage`. Name the deals that moved and the deals that did not
   move when they should have.
4. **Credit burn.** `godly.integrations`: anything at or above 75% of quota is
   worth a line; at 90% the Credit Warden (`AG-FIN-02`) has already paused the
   consuming agent and filed a `warn`, so the brief explains the pause rather
   than announcing the number.
5. **Spend against thresholds.** Today's `sum(cost_usd)` and month-to-date,
   checked against the escalation ladder below.
6. **Decisions needed.** Everything blocked on a human, each with the numbers,
   the options, a recommendation, and what happens if no answer arrives.
7. **Human queue.** Manual BBB / TruePeopleSearch lookups waiting, and how long
   they have waited. That queue is the one place the company's throughput
   depends on the CEO's hands.

## Escalation — where each item goes

The thresholds are not negotiable and they are not vibes. Route first, write
second: an item routed to the chief does not need CEO wording.

| Trigger | Goes to | Appears in the brief as |
|---|---|---|
| Any run `warn` / `review` / `failed` | Supervisor (you) | An exception line with its disposition |
| Two consecutive `failed` runs, same agent | Chief | Flagged, with what the chief was told and when |
| Unplanned spend > **$50 in a day** | Chief | Flagged, with the amount, the agent, and the cause |
| Contract terms — indemnity, exclusivity, termination, non-standard payment | **CEO** | A decision item, with the term and the recommendation |
| A new niche | **CEO** | A decision item, before any work starts |
| Unplanned spend > **$500 month-to-date** | **CEO** | A decision item, with month-to-date and the run rate |

"Unplanned" means spend outside the day's declared plan — an unexpected retry
storm, a metered call nobody budgeted, an overage. Planned burn inside allowance
is a line in the credit section, not an escalation. When you are unsure which
one you are looking at, treat it as unplanned and say why.

Below-floor pricing, threshold changes, and any chief or CEO ruling coming out
of a brief earn a decision record — see the `decision-record` skill. Cite the
record's id in the brief so tomorrow's brief does not re-litigate it.

## Shape of the brief

`assets/brief-template.md` is the fill-in version. Six sections, one page.

1. **Verdict** — one line: `GREEN` (nothing needs you), `HOLDING` (exceptions
   handled, watch item named), or `NEEDS YOU` (decisions below). The CEO should
   be able to stop after this line on a green day.
2. **Needs a decision** — first, because it is the only section with a deadline.
   Each item: the question, the numbers, the options, your recommendation, and
   the cost of waiting.
3. **Exceptions** — every non-`ok` run with agent, task, run id, and
   disposition. Grouped, not listed one per line, when several share a cause.
4. **Movement** — weighted pipeline delta and the deals behind it. Stalls count
   as movement in the wrong direction; name them.
5. **Burn** — allowances above 75%, today's spend, month-to-date, and any pause
   in effect.
6. **Queue** — what is waiting on a human, with age.

### Rules that keep it readable

- **Every number names its source.** `weighted $412k (pipeline_by_stage)`,
  `Hunter 44/50 (integrations:KEY-03)`. A number the CEO cannot trace is a
  number they have to ask about, which defeats the brief.
- **No raw run dumps.** Runs are evidence; cite ids, do not paste rows.
- **Say "nothing" out loud.** "No exceptions since the 18:00 brief" is a real
  line and a valuable one. Silence reads as an unfinished sweep.
- **Recommend, do not present.** "Two options, thoughts?" pushes the work back
  up. Give a recommendation and the reasoning; the CEO breaks ties, they do not
  do the analysis.
- **Keep it to a page.** Detail belongs in the vault note the brief links to.

## Common failures

| Failure | What it costs | Fix |
|---|---|---|
| Exception with no disposition | The CEO cannot tell if it is handled | Every non-`ok` run gets fixed / retrying / queued / blocked |
| Pipeline totals with no delta | Looks like progress, proves nothing | Compare against the previous brief and name what moved |
| Credit number without consequence | Reads as trivia | Say what is paused, or what will be, and when |
| Escalating everything to the CEO | The seven briefs stop being readable | Route by the table above; chiefs absorb their tier |
| Decision item with no recommendation | The work went up instead of the answer coming down | Recommend, and say what happens if nobody answers |
| Brief with no link to evidence | Nothing can be checked | Cite run ids, deal ids, and the vault note path |

## Reference

- `references/sweep-queries.md` — the SQL for each section, against the live
  schema, plus the `scripts/extract.py` fallback when `DATABASE_URL` is unset.
- `assets/brief-template.md` — the page the CEO reads.
