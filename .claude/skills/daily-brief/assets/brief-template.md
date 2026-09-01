# [Department] brief — [supervisor id] · [date, time]
Covering since [previous brief timestamp]

**VERDICT: [GREEN | HOLDING | NEEDS YOU]** — [one clause: why]

---

## Needs a decision
[Omit the section entirely on a GREEN day — do not write "none" here, write it
in the verdict line.]

**1. [The question, in one line]**
- Numbers: [the arithmetic, with sources — e.g. `$96k · 12 mo · margin 31% vs floor 38% (AG-FIN-01)`]
- Options: [A — consequence] · [B — consequence]
- Recommendation: [which, and why in one sentence]
- If no answer by [when]: [what happens by default]
- Evidence: [DEAL-###, /brain/accounts/<slug>.md]

---

## Exceptions
[Every non-`ok` run since the last brief, with a disposition. Group by cause.]

- `warn` · AG-FIN-02 · Credit sweep, Hunter at 88% of monthly (run 88406) —
  **handled**: verification paused except send-time; queue holds [N].
- `review` · AG-SALES-02 · Custom proposal, Keystone Mechanical (run 88405) —
  **waiting on AG-FIN-01** pricing sign-off, expected [when].
- `failed` ×2 · [agent] · [task] — **escalated to [chief]** at [time].

[Or: "No exceptions since the [time] brief."]

## Movement
- Weighted open pipeline: **$[now]** (`pipeline_by_stage`), from $[previous] — [delta]
- Moved: [DEAL-### Account, stage → stage, $value]
- Opened: [DEAL-### Account, $value, source]
- Stalled: [DEAL-### Account, $value, [N] days at [stage], next action [what]]

## Burn
- [Service] [used]/[quota] [unit] — [%] (`integrations:KEY-##`) — [consequence or pause in effect]
- Spend today: $[x] across [n] runs · month-to-date $[y]
- Threshold status: [under $50/day · under $500/mo] or [**over — escalated to [chief|CEO]**]

## Queue (waiting on a human)
- [N] manual [BBB | TPS] lookups open, oldest [N] days — [/brain/agents/ag-res-02.md]
- [N] accounts with `owner_verified` NULL, oldest [date]

---
Decisions filed today: [DEC-YYYY-MM-DD-slug] · Full detail: [/brain/agents/<supervisor>.md]
