---
name: prospect-research
description: Use when building or verifying a prospect list for a Godly Base niche — crawling directories for new accounts, corroborating who actually owns a business, deciding whether a contact is sendable, or writing rows into godly.accounts and godly.contacts. Also use whenever BBB.org, TruePeopleSearch, LinkedIn scraping, or Hunter verify credits come up, since those carry terms and allowances that are easy to break by accident.
---

# Prospect research

The Market Scraper (`AG-RES-01`) and the Ownership Verifier (`AG-RES-02`) are a
duo. One finds businesses, one proves who owns them. Neither ships alone: an
account row nobody corroborated is a lead, not an account, and sales does not
get it.

Three constraints shape everything below, and none of them are style
preferences — they are the difference between an asset and a liability:

- **Some sources are human-only.** BBB.org and TruePeopleSearch have no public
  API and terms that prohibit bulk automation. Automating them risks the
  company's access and its standing, for data we can get another way.
- **Verification costs money we do not have.** Hunter's free tier is 50
  credits/month; a verify costs 0.5. That is ~100 verifies a month against
  thousands of scraped contacts. Spend them on contacts about to be emailed.
- **Ownership claimed once is a rumor.** Two independent sources, or the
  `owner_verified` column stays empty.

## The run, start to finish

1. **Load the ICP.** Read `/brain/niches/<slug>.md` for the niche's size band,
   geography, service mix, and disqualifiers. Crawling without the playbook
   produces rows nobody can score.
2. **Crawl cheap first.** Crawl4AI runs on the local cloud at no per-page cost —
   use it for bulk directory sweeps. Firecrawl (3,000 pages/mo, metered) is for
   pages that fight back: JS-heavy, awkward markup. browser-use is for portals
   with no clean HTML. Raw output lands in `/vault/raw` before parsing.
3. **Dedupe before writing.** Match against existing `godly.accounts` on
   normalized domain first, then name + city. A duplicate account splits a
   deal history in half and nobody notices for a quarter.
4. **Write accounts unverified.** `owner_verified` stays NULL until step 5.
   Score `fit_score` (0-100) against the playbook's criteria, not vibes.
5. **Corroborate ownership** — the ladder in `references/source-rules.md`. Free
   and structured sources first; BBB queued to a human; TruePeopleSearch only
   to confirm a name already found elsewhere.
6. **Write contacts as `unverified`.** Email status changes only when the
   Outbound Prospector (`AG-SALES-01`) spends a Hunter credit at send time.
7. **Log the run and hand off.** One `godly.agent_runs` row per run. The
   verifier reads the scraper's rows; the scraper fixes what the verifier
   rejects. Then the batch goes to sales.

## The two hard source rules

**BBB.org and TruePeopleSearch: one lookup, one human, one line of record.**
The verifier does not fetch these pages — it writes a lookup into the manual
queue (`assets/manual-lookup-queue.md` shows the shape), a human opens the page
in a browser as any person would, and what comes back into the system is the
*corroboration*, not the page. Record "BBB: principal listed as Dana Harker,
accredited since 2011, checked 2026-09-01" — never a scraped copy, never a bulk
export, never a queued batch of 200 that a human "will get to".

TruePeopleSearch is last-resort only: it confirms an owner name you already
have from somewhere else. It never originates a name.

**LinkedIn goes through Unipile.** Profile data, messaging, and inbox sync run
through the compliant API (`UNIPILE_API_KEY`, 200 actions/day). Browser
automation against LinkedIn gets the account banned, and a banned account takes
the whole outbound channel with it. If Unipile is `pending` and the data is not
available, the `linkedin` column stays empty — that is a fine outcome.

### When you are about to talk yourself into it

| The thought | What is actually true |
|---|---|
| "It's just 50 BBB pages, I'll rate-limit it" | Rate-limiting an activity the terms prohibit does not make it permitted. Queue them. |
| "TruePeopleSearch is the only place with this owner" | Then this account has one source, not two. Leave `owner_verified` empty and move on. |
| "I'll pull LinkedIn with the browser tool just this once" | The ban is permanent and applies to the seat, not the run. Unipile or nothing. |
| "Verifying at scrape time saves a step later" | 4,180 scraped/mo × 0.5 credits = 41× the monthly allowance. That decision is already recorded as `DEC-2026-08-14-hunter-rationing`. |
| "The account looks obviously legitimate" | Obvious is not corroborated. The column asks *how*, not *whether*. |

## What "two independent sources" means

Independent means the second source does not derive from the first. Apollo and
Clay both resell overlapping upstream databases — agreeing with each other is
not corroboration. A state registry filing and the company's own leadership
page are independent. A licensing board and BBB are independent.

Good `owner_verified` values look like the source pair plus what it confirmed:

- `BBB + Secretary of State` (the seed's own convention)
- `OK SoS filing 2019 + company leadership page`
- `State contractor license CIB-4471 + BBB principal listing`

If only one source has the name: leave the column NULL, set `source` to what you
used, and let the account sit. Sales works verified accounts.

## Output shape

Every crawl ends as rows in these two tables — the column list is the contract.

**`godly.accounts`** — `id` (`ACC-####`), `name`, `niche_id`, `city`,
`employees`, `revenue_band`, `owner_verified` (the source pair, or NULL),
`source` (`Apollo | Clay | Crawl4AI | Firecrawl | Manual`), `fit_score` (0-100),
`vault_note` (`/brain/accounts/<slug>.md`).

**`godly.contacts`** — `id` (`CON-####`), `account_id` (FK), `name`, `title`,
`email`, `email_status` (`unverified` on write; `verified | risky | catch-all |
invalid` only after a Hunter call), `phone`, `linkedin` (Unipile-sourced),
`channel`, `last_touch_at`.

```sql
INSERT INTO godly.accounts
  (id, name, niche_id, city, employees, revenue_band,
   owner_verified, source, fit_score, vault_note)
VALUES
  ('ACC-1093', 'Cardinal Facility Services', 'hvac', 'Wichita, KS', 48,
   '$5–10M', 'KS SoS filing 2014 + BBB principal listing', 'Crawl4AI', 81,
   '/brain/accounts/cardinal-facility-services.md');

INSERT INTO godly.contacts
  (id, account_id, name, title, email, email_status, phone, linkedin, channel)
VALUES
  ('CON-3388', 'ACC-1093', 'Marta Reyes', 'Owner / GM',
   'm.reyes@cardinalfs.com', 'unverified', '+1 316 555 0119',
   'in/marta-reyes-cfs', 'Cold email + LinkedIn');
```

The account note in `/brain/accounts/<slug>.md` carries what the row cannot:
who confirmed what, on which date, and what is still unknown. The row is the
number; the note is the meaning.

## Closing the run

Write one `godly.agent_runs` row per run: `agent_id`, `task`, `duration_s`,
`rows_touched`, `status`, `cost_usd`, `note_path`.

- `ok` — rows landed, corroboration complete or cleanly queued.
- `warn` — a quota crossed 90%, or the manual queue is growing faster than a
  human clears it. Goes to the supervisor (`SUP-RES`).
- `review` — rows landed but something needs the duo partner's eyes.
- `failed` — the crawl did not produce usable rows. Two consecutive failures on
  the same agent go to the chief (Scriven).

Unplanned spend over $50 in a day goes to the chief regardless of run status; a
new niche goes to the CEO before the first crawl, not after.

If the run changed *how* research is done — a source dropped, a threshold moved,
a tool swapped — that is a decision, and it earns a record. Use the
`decision-record` skill.

## Reference

- `references/source-rules.md` — every source with its verdict, cost, allowance,
  what is permitted, and the corroboration ladder in order.
- `assets/manual-lookup-queue.md` — the queue entry a human picks up, and the
  line that comes back.
