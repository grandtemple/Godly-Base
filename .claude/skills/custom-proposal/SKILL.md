---
name: custom-proposal
description: Use when writing, revising, or pricing a client proposal, statement of work, or retainer offer for a Hero account — the AI front office a client is buying for their own business — including when a deal is moving to the Proposal stage, when a prospect asks "what would this cost", when a discount or custom term is on the table, or when a draft needs to clear the unit-economics partner before it goes to a client.
---

# Custom proposal

The Proposal Architect (`AG-SALES-02`) writes proposals a client could not have
received from anyone else, and prices them with the Unit Economics agent
(`AG-FIN-01`). That pairing is the whole point of the duo: a proposal that wins
at a price that loses is a worse outcome than no proposal.

A proposal that could be sent to any firm in the niche with the name swapped is
a brochure. Send the brochure and you compete on price, because you have given
the client nothing else to compare.

## Before drafting: read three things

1. **The account row** — `godly.accounts` for `name`, `city`, `employees`,
   `revenue_band`, `niche_id`, `owner_verified`, `fit_score`. If
   `owner_verified` is NULL, stop: nobody has confirmed who owns this business,
   so nobody knows who signs.
2. **The account note** — `/brain/accounts/<slug>.md`. This is where discovery
   lives: what they said, in their words, with dates and names. Everything in
   section 1 of the proposal comes from here or it is invented.
3. **The niche playbook** — `/brain/niches/<slug>.md`. Vocabulary, objection
   set, proof, and the pricing shape that niche accepts. Roofing talks about
   storm capacity and claim cycles; med spa talks about no-show rates and
   rebooking. Using the wrong vocabulary reads as "we do not work with people
   like you."

Also pull the open deal from `godly.deals` (`value_usd`, `term`, `probability`,
`next_action`) and, if a competitor is in the room, the current sweep from
`AG-RES-03`.

## Section structure

`assets/proposal-outline.md` is the fill-in version. The order matters — it
moves from their world to ours to the number, so the price lands after the value
rather than before it.

1. **What we heard.** Their situation in their language, quoting discovery with
   dates and names. Three to five specifics that could only be about them.
2. **What it is costing.** The gap, in their numbers. "Eleven inbound calls a
   day go to voicemail after 5pm" beats "you are losing revenue."
3. **What we will do.** Two or three named workstreams with concrete
   deliverables. Not capabilities — deliverables, with a first-30-days list.
4. **How it runs.** Cadence, who they talk to, response times, where reporting
   lands, what we need access to. This section is where trust is either built
   or quietly lost.
5. **Proof.** One engagement from the same niche with real numbers, or an
   honest "you would be our first in this segment, here is the adjacent one."
   Fabricated proof is not a shortcut, it is a lawsuit.
6. **Investment.** Price, term, what is included, what is explicitly not.
   Priced by `AG-FIN-01` before this section is written, not after.
7. **What we need from you.** Access, the decision owner by name, and dates.
8. **The line.** Start date, term, and signature — one page, no surprises.

Keep it as short as it can be while still being specific. Length is not
seriousness; specificity is.

## Pricing: the handoff to AG-FIN-01

Draft scope first, then send the costing request. Pricing before scope is
guessing, and pricing after sending is malpractice.

Send `AG-FIN-01`:

- the scope, as the deliverables from section 3
- estimated delivery hours per month, by workstream
- metered tool consumption the engagement adds (Apollo/Clay/Hunter credits,
  Firecrawl pages, sending volume) — these are real costs from
  `godly.integrations`, not rounding
- the proposed term (`12 mo retainer`, `6 mo pilot`, project)
- the price you intend to quote

Get back: cost to serve, margin at that price, and the **floor margin** for this
engagement shape. The floor number lives with unit economics — ask for it,
do not assume it, and do not carry a number from a previous deal into this one.

### The floor-margin rule

**Nothing ships below floor margin without CEO sign-off.** Not for a logo, not
for a first client in a niche, not because the pipeline looks thin this month.

When the price you want to quote comes in under floor:

1. **Re-scope first.** Cut a workstream, lengthen the term, move something to a
   milestone. Most below-floor proposals are over-scoped, not under-priced.
2. **If it still belongs below floor**, it is a CEO decision, and it is a
   decision that earns a record — question, numbers, what was rejected, and what
   would reverse it. Use the `decision-record` skill; put the record's id in the
   deal's `next_action` and the run's `note_path`.
3. **Do not send while waiting.** The run stays `review` until sign-off lands.

Custom contract terms — indemnity, exclusivity, termination, payment terms
outside the standard — go to the CEO too, at any margin. So does the first
proposal in a new niche.

## Shipping it

- File the client-facing document to Google Drive under
  `/Hero/Clients/<account>/`. Drive is the outward face and holds only
  what a client opens; the reasoning stays in the vault.
- Update `godly.deals`: `stage` = `Proposal`, `value_usd`, `term`,
  `probability`, `next_action` (the walkthrough date, not "follow up"),
  `owner_agent` = `AG-SALES-02`.
- Append the pricing basis and the rejected alternatives to
  `/brain/accounts/<slug>.md`. Six months from now the renewal conversation
  depends on remembering why the number was the number.
- Write the `godly.agent_runs` row. It stays `review` until `AG-FIN-01` has
  signed the pricing — an output no partner has seen is a draft, not a
  deliverable. Only then does it become `ok`.

## Common failures

| Failure | What it looks like | Fix |
|---|---|---|
| Brochure proposal | Sections 1 and 2 could be pasted into any account | Go back to the account note; if it is thin, discovery is not finished |
| Price before scope | A number quoted on a call, scope written to fit it | Re-scope to the number in writing, or re-quote |
| Silent discount | Below floor, sent, sign-off "to be confirmed" | Stop the send. Floor is a gate, not a guideline |
| Capability list | "AI-powered outbound, full-funnel analytics" | Name the deliverable and when it lands |
| Invented proof | A case study with numbers nobody can source | Use the adjacent real one and say it is adjacent |
| Vault-less ship | Proposal in Drive, reasoning nowhere | Drive holds the artifact, the vault holds the why |

## The template

`web/proposal-template.html` is the client-facing document. It is tokenized from
`design-system/tokens.json`, so it carries the same palette and type as
everything else Hero ships, and it prints cleanly on A4 and Letter.

Fill every `{{PLACEHOLDER}}`; leave none in a document that goes to a client.
The pricing lines come from `godly.price_book` by code, quantities and prices
from `godly.quote_lines`, and the reference from `godly.quotes.ref` — never
typed by hand, so the proposal and the database agree on what was offered.

Before it sends: every line must match `godly.price_book` exactly. There is no
floor to clear and no discount to authorise — the `enforce_set_pricing` trigger
refuses a quote line that does not equal the published price, so a mismatch is a
defect in the draft rather than a concession to argue about.

## The three components, and only these three

| Line | Billing | Price |
|---|---|---|
| Configuration and go-live | one-time | `HERO-SETUP` |
| Front office pod | monthly | `HERO-MONTHLY` — all nine capabilities, no tiers |
| Consulting | hourly | `HERO-CONSULT`, up to **three sessions a week** |

Never quote a subset of capabilities at a lower monthly price; the pod is the
whole front office or it is nothing. If a prospect wants less, the answer is the
same price with fewer capabilities switched on, or no deal.

State the session cap in the terms every time. It is an entitlement, and a
client who discovers it late feels sold to. `godly.consulting_sessions` refuses
a fourth booking in the same week, so a promise made in a proposal that ignores
it will simply fail at the calendar.
