# Source rules — what each research source may be used for

Verdicts come from `docs/RESEARCH-INDEX.md` and the `godly.sources` table.
Allowances come from `godly.integrations` (`used` / `quota` / `unit`), which the
Credit Warden (`AG-FIN-02`) sweeps and pauses at 90%.

## The table

| Source | Verdict | Allowance | Permitted | Never |
|---|---|---|---|---|
| Crawl4AI (self-hosted) | `adopt` | local, unmetered | Bulk niche directory sweeps, first pass on everything | — |
| Firecrawl | `adopt` | 3,000 pages/mo | JS-heavy or awkward pages Crawl4AI cannot parse | Bulk sweeps that Crawl4AI could have done |
| Scrapling | `pilot` | local | Selectors that keep breaking on a recurring crawl | — |
| browser-use | `pilot` | local | Portals and directories with no clean HTML | LinkedIn. BBB. TruePeopleSearch. |
| Apollo.io | `adopt` | 1,000 credits/mo | Company + contact enrichment, waterfall email/phone | Treating it as independent from Clay |
| Clay | `adopt` | 500 credits/mo | List building, multi-provider enrichment tables | Treating it as independent from Apollo |
| Hunter (finder) | `adopt` | shares the 50-credit pool; 1 credit, charged only on a hit | Finding an address for a contact entering a sequence | Speculative finds across a whole crawl |
| Hunter (verifier) | `adopt` | 0.5 credit per verify, same 50-credit pool | Verification at send time, by the Outbound Prospector | Verification at scrape time |
| Unipile (LinkedIn) | `pilot` | 200 actions/day, `pending` until keyed | All LinkedIn reads and messages | Any browser-driven alternative |
| BBB.org | `manual` | human lookups, one at a time | A person opening one page and reporting what it said | Any automated fetch, batch, or export |
| TruePeopleSearch | `restricted` | human lookups, last resort | Confirming an owner name already found elsewhere | Originating a name. Any automation. |

## The corroboration ladder

Work down it and stop as soon as two independent sources agree. Each rung is
slower or more constrained than the one above it, so climbing past a rung you
skipped is usually the cheaper fix.

1. **Company's own surface** — About / Leadership / Team page, footer legal
   name, press releases. Free, fast, and usually current.
2. **State registry** — Secretary of State business filing: registered agent,
   officers, formation date. Free, authoritative, independent of everything
   commercial.
3. **Licensing board** — contractor, medical, or security license registries.
   Especially strong for Roofing & Restoration, Med Spa, and Private Security.
4. **Apollo / Clay record** — counts as *one* source between them, never two.
5. **BBB.org** — queue a manual lookup. Adds standing, complaint history, and
   named principals a registry may not carry.
6. **TruePeopleSearch** — manual, last resort, confirmation only.

## Recording the corroboration

`accounts.owner_verified` holds the source pair and, where it fits, the
identifier: `KS SoS filing 2014 + BBB principal listing`. The account note at
`/brain/accounts/<slug>.md` holds the detail: what each source said, the date
checked, who checked it, and what is still unknown.

Never store copies of pages from `manual` or `restricted` sources. The record is
what a human confirmed, not what the page contained.

## Credit arithmetic worth keeping in your head

- Hunter: 50 credits/mo ÷ 0.5 per verify = **100 verifies a month**, total.
- A single month's crawl output is thousands of contacts. Verifying all of them
  is roughly 40× the allowance — this is exactly the arithmetic behind
  `DEC-2026-08-14-hunter-rationing`.
- At 90% of any allowance the Credit Warden pauses the consuming agent and files
  a `warn` run. Seeing Hunter at 44/50 in `godly.integrations` means the pause is
  imminent; verify only what is being sent today.
- Bounce rate over 3% for two consecutive weeks stops the sending domain, not
  the campaign. Unverified sends are how that happens.
