# Brand and voice

The brand and messaging system for Godly Base: what we say we are, how we sound, and what we call things. It governs the Hero Capital OS (`web/hero-os.html`), the README, client-facing copy, and anything an agent drafts for a human to send.

## Read this first: three names, one rule

Settled by Joshua on 1 September 2026: **a client never hears "Godly Base."**
The firm goes to market as **Hero**.

| Name | What it is | Who hears it |
|---|---|---|
| **Hero** | The firm as the market meets it. The spoken brand, the one on a proposal cover, a signature, a LinkedIn profile, a cold email. | Clients, prospects, partners, the public |
| **Hero Capital** | The formal entity name, used where a legal name is required. | Contracts, invoices, banking, filings |
| **Godly Base** | The repository. The system it builds is the **Hero Capital OS** — modules, database, agent roster. Internal. | Joshua, the agents, anyone reading this repo |
| **Godly** | The Christian community app. A separate product by the same owner. | Its own community |

**The rule that follows from it:** any surface a client can see says Hero.
Anything internal says Godly Base. There is no third variant, no hybrid, and
"Godly Base" never appears in client-facing copy — not in a proposal footer, not
in a sending domain, not in a case study.

This also dissolves the conflict that used to sit at the top of this document.
The agency and the app were never going to collide in market, because the agency
does not use the name in market. Whether Hero and Godly are ever publicly
connected is a separate choice Joshua has not made, and nothing in this
repository asserts one.

### One concern, stated once

"Hero Capital" is crowded, and every occupant is a finance company: venture
firms in Seattle and Santiago, a UK Companies House entity, Heroes Capital in
London, and Hero FinCorp in India. A general manager at a roofing firm who hears
"Hero Capital" files it as an investment company, which is the wrong shelf for a
firm selling operations retainers. It also means the search results for the exact
phrase are already owned.

That is an argument about the *word Capital*, not about Hero. The split above is
the cheapest fix: lead with Hero everywhere a human is listening, and keep
Hero Capital for the paperwork that needs a registered name. If Joshua wants one
name for everything, the recommendation is Hero plus a category line — "Hero —
AI operations for contractors" — rather than Hero Capital.

Before the name is used in market, two checks are worth an hour: the USPTO
register for Hero in the relevant service classes, and whichever domain the firm
intends to send email from. A sending domain that fails a trademark check later
is expensive, because deliverability reputation does not transfer.

### Still open

1. ~~Does an agency client ever hear "Godly Base"?~~ **Answered: no. They hear Hero.**
2. Is the firm's faith background part of what a roofing general manager hears, or is it private?
3. Should Hero and Godly ever be publicly connected?
4. Which venture owns the primary domain and search results for "Godly"?
5. Do Hero and Godly share one visual identity, or stay distinct?

Until 2 and 3 are answered, three defaults hold:

- No faith language in Hero copy aimed at a client or prospect. The systems-and-instruments metaphor is fine; Scripture used to sell a retainer is not.
- No commercial or sales language in Godly app copy.
- The palettes stay distinct. Do not port the OS green into the app, or the app indigo into Hero's client-facing work.

## Positioning

**One line.** Hero puts an AI front office into a business — answering the phone, working the inbox, booking the job, taking the payment, and chasing the review and the referral — so a regional operator stops losing work to the calls, quotes, and follow-ups nobody had time for.

**What it is not.** Not a chatbot on a website, not a marketing agency, and not advice. It is staffed capability: the tasks that have a trigger, a script, and a moment they must happen in. Anything needing judgment about a person escalates to a named human, and saying so plainly is part of the pitch, not a caveat buried in it.

**The positioning statement.** For owners and general managers of regional roofing, med spa, HVAC, and private security firms, who need consistent pipeline but cannot hire a full sales and marketing department, Godly Base runs that department as a paired-agent system with a single human accountable for it. Unlike a per-seat AI sales tool, we are not software the client operates; we run the work and hand over the record.

**The three proof pillars.** Every claim we make should reduce to one of these, and each one is already true in the repository:

- **Paired work, not raw model output**: every agent has a named counterpart, and an output no counterpart has seen is a draft. Evidence: `config/agents.yaml`, the duo field on all 21 agents.
- **The evidence travels with the number**: every deal carries the source of the contact, who confirmed the owner, and what the next move costs. Evidence: the account file in Chapter II, `db/schema.sql`.
- **Restraint we can point at**: BBB and TruePeopleSearch stay manual, LinkedIn goes through a compliant application programming interface (API), and a bounce rate over 3% for two weeks stops the sending domain. Evidence: `docs/ARCHITECTURE.md`, the guardrails section.

**What we do not claim.** We do not say "fully autonomous", "replaces your sales team", "AI employees", or any number we cannot open the table behind. The market watch list in `docs/RESEARCH-INDEX.md` names four companies selling the autonomous framing. Our difference is the human seat and the paper trail, so the copy should never blur it.

## The voice

The profile below comes from Joshua's own emails, as documented in the `godly-newsletter` skill. It is the source of truth for how he writes, and it outranks any house style in this document where the two disagree.

**Eight traits, in the order they show up in a piece of writing:**

1. **Opens warmly and directly.** He greets a person, not an audience.
2. **States the point in the first two sentences.** The reader never scrolls to find out what the message is about.
3. **Writes in the first person and owns the work.** "I've completed", "I wanted to let you know", "I'll prepare".
4. **Explains the why, not only the what.** An update names the reason behind the change.
5. **Invites rather than broadcasts.** "I'd love for you to take a look and share any thoughts", not "Check it out!"
6. **Offers one low-pressure next step, with flexibility built in.** "Or feel free to send notes directly if you'd prefer."
7. **Closes briefly and warmly.** "Looking forward to your thoughts."
8. **Keeps paragraphs to two to four sentences.** Plain, unhurried, confident, never salesy.

**The mechanics that follow from those traits:**

- Active voice, present tense, and second person for anything the reader does.
- Contractions, because they carry the warmth.
- Sentences under 20 words as the target, and one idea per paragraph.
- Specific numbers instead of vague quantifiers: "97 meetings from 513 replies", not "many meetings".
- Colons and commas where the sentence wants a break. The OS module prose earns its em dashes; nothing else does.

## Three audiences, one voice, three registers

The voice does not change between audiences. The register does: how much of Joshua is on the page, and how much invitation the piece carries.

| | Internal operating docs | Client-facing | The Godly community |
|---|---|---|---|
| **Where** | The OS, README, `docs/`, decision records, agent prompts | Proposals, outbound email, LinkedIn posts, the site | Newsletter, in-app copy, announcements |
| **Person** | "We" for standing commitments, no "I" | "I" when Joshua sends it, "we" for what the firm commits to | "I" throughout |
| **Register** | Declarative and rule-shaped. Every claim carries its evidence. | Warm and plain. The ask arrives early and stays small. | Warm and personal, closer to pastoral than to professional. |
| **Ends with** | A rule, a threshold, or a reversal condition | One next step, with an easier alternative offered | One invitation, never more than one |
| **Never** | First-person singular, or a number without a table behind it | Urgency, hype, or a second call to action | Sales language, or Scripture used as a hook |

The same fact in all three registers:

- **Internal:** "The qualifier answers inbound within 15 minutes. Replies that wait longer convert at roughly a fifth of the rate, so the response window is a guardrail, not a target."
- **Client-facing:** "When someone replies to us about your account, they hear back inside 15 minutes. I'd rather over-serve that first hour than explain a lost lead later."
- **Community:** "I've been trying to answer everyone who writes in the same day. If I've missed you, please send it again. I'd rather read it late than not at all."

**Agent-drafted copy.** Anything an agent writes in Joshua's name is a draft until he has read it, in the same sense the double-agent rule means everywhere else. Agents may draft in this voice. They may not send in it.

## What to avoid

**Words that get cut on sight:** easy, simple, quick, very, just, really, seamless, robust, leverage, unlock, supercharge, game-changing, revolutionary, "in today's fast-paced world".

**Patterns that get rewritten:**

- Hype punctuation: ALL CAPS, stacked exclamation points, "Don't miss out!"
- Rhetorical questions used as openers. They read as advertising.
- Weasel quantifiers where a number exists: significantly, many, often, typically, most.
- Summary transitions that recap the paragraph above: "With that in place…", "Now that we've covered…"
- Spec-sheet verbs: provides, enables, is configurable, is designed to.
- Metaphor verbs standing in for the literal step: moves through, lands, carries, hits.
- Passive voice. Append "by monkeys" to the sentence; if it still parses, rewrite it.
- Paragraphs over four sentences, or covering two ideas.

**Faith language.** In agency copy, none. In Godly copy, Scripture is something to sit with, never a hook, a subject-line device, or a close. Quote it in full with its reference, and let it stand without a sales turn after it.

**A note on the metaphor.** The book conceit is the whole system: leaves, chapters, marginalia, the folio, the vault. It works because it is consistent. Do not stack a second metaphor on top of it. Nothing in this product is a journey, an engine, or a north star.

## Naming conventions

**The three names.** "Hero" for the firm in market, "Hero Capital" only where a legal entity name is required, "Godly Base" for the internal operating system, "Godly" for the community app. Never GodlyBase, godlybase, Godly-Base, or GB outside a code identifier; never HeroCapital, Hero Cap, or HC. The repository slug `Godly-Base` is the one exception and stays as it is, because it is internal.

**Which name goes where.** A proposal, an email signature, a case study, a LinkedIn profile, a landing page, a contract, an invoice: Hero (or Hero Capital where the paperwork demands a registered name). The OS, the database, agent charters, decision records, this repository: internal names only. If you cannot tell whether a surface is client-facing, assume it is and write Hero.

**Chapters.** Roman numerals in order, with two title shapes already established: `Book of <Plural Noun>` for a pipeline the business runs, and `The <Singular Noun>` for a system it depends on. A new chapter picks the shape that matches its job, and the reserved chapters keep their titles: IX Service Delivery, X Finance and Forecast, XI Client Portals.

**Agents.** Chiefs carry one-word English nouns naming their function: Ledger, Herald, Bridge, Forge, Scriven, Quill, Tally. Supervisors are the chief's name plus "Prime". Working agents carry plain role names in title case: Outbound Prospector, Ownership Verifier, Credit Warden. Do not give a working agent a human first name. The names should read as offices, because that is what they are.

**Identifiers.** These are already consistent and should stay that way:

- Agents: `AG-<DEPT>-<NN>`, supervisors `SUP-<DEPT>`, departments by chief code (`CSO`, `CMO`, `CBDO`, `CTO`, `CIO`, `CCO`, `CFO`).
- Records: `DEAL-9NN`, `PTR-2NN`, `CMP-5NN`, `CNT-7NN`.
- Decisions: `DEC-YYYY-MM-DD-<kebab-slug>`, owner recorded as a `SUP-` code.

**Niches.** Write them out in full, with the ampersand, exactly as `db/seed.json` holds them: Roofing & Restoration, Med Spa & Aesthetics, Commercial HVAC & Facilities, Private Security Services. In prose outside a table, "and" replaces the ampersand.

**Capitalization.** Sentence case for headings in documents and chapter body copy. Title case for chapter titles, navigation labels, and buttons. The codex, the vault, the brain, and the nerve take a lowercase article in running prose and title case only as chapter titles.

## Visual identity

The visual system has its own source of truth: `design-system/godly-base-codex/MASTER.md`, with page-level overrides in `design-system/godly-base-codex/pages/`. Tokens, contrast rules, and the validated chart palette live there and are not repeated here, so they cannot go stale in two places. Brand owns the three rules that sit above the tokens:

- **One accent.** Gilt marks the spine, the current leaf, and an active control. It is not a highlighter, and it never becomes a second brand color.
- **Status color is reserved.** The good, attention, critical, and idle tokens carry meaning. Never use them decoratively, never use them as chart series, and never add a fifth state without adding it to `statusPill` first.
- **The type carries the identity.** Fraunces for display, Spectral for body, JetBrains Mono for data and identifiers. If the two ventures should ever look related, the shared element is this typography, not the color.

The Godly newsletter template uses a different palette: cream, indigo, and gold. Leave it alone until question 5 at the top of this document is answered.

## Before anything ships

Six checks, in order:

1. **Point first.** Does the first sentence say what this is about?
2. **Evidence.** Does every number name the table, run, or source it came from?
3. **Register.** Is the person and the level of invitation right for this audience?
4. **Banned list.** No hype words, no weasel quantifiers, no second metaphor.
5. **Names.** Godly Base, Godly, niches, agent names, and identifiers written the house way.
6. **One ask.** Client-facing and community pieces carry a single next step, and it is a small one.
