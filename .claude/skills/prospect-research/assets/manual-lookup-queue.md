# Manual lookup queue — BBB.org / TruePeopleSearch

One entry per lookup. A human works these one at a time in a normal browser.
The queue lives with the verifier's memory (`/brain/agents/ag-res-02.md`); each
completed entry updates `accounts.owner_verified` and the account note.

## Queue entry (written by AG-RES-02)

```yaml
- account_id: ACC-1093
  account_name: Cardinal Facility Services
  city: Wichita, KS
  source: BBB            # BBB | TruePeopleSearch
  reason: Registry lists a registered agent, not an operating principal.
  already_have: KS SoS filing 2014 — agent "Reyes Holdings LLC"
  question: Who does BBB list as principal, and what is the accreditation standing?
  queued_at: 2026-09-01
  status: open           # open | done | unavailable
```

TruePeopleSearch entries must carry an `already_have` name. If they do not, the
entry is invalid — the source confirms, it never originates.

## What comes back (written by the human)

```yaml
  status: done
  checked_by: joshua
  checked_at: 2026-09-02
  found: Principal listed as Marta Reyes, GM. Accredited since 2016, A+, no
         complaints in 3 years.
```

Then, and only then:

- `accounts.owner_verified` = `KS SoS filing 2014 + BBB principal listing`
- `/brain/accounts/cardinal-facility-services.md` records both sources, both
  dates, and anything still unresolved.
- The verifier's run row cites the note in `agent_runs.note_path`.

If the lookup comes back `unavailable` — no listing, name conflicts with the
registry — leave `owner_verified` NULL and say so in the note. A conflict
between two sources is information; papering over it is not.
