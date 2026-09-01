# Copy edits

> **Historical record.** These edits were applied on 1 September 2026 to
> `web/godly-codex.html`, the book-metaphor interface that preceded the Hero
> Capital OS. The file no longer exists; the prose that survived the rebuild
> lives in `web/hero-os.html`. Kept for the reasoning, not as a to-do list.

Fifteen edits to prose already in the repository, verified against the working tree on 1 September 2026. Quoted text is exact and unique in its file, so each block can be matched and replaced by hand. Line numbers are given as a hint only, because `web/godly-codex.html` is being edited concurrently.

Two notes before the list. First, most of this prose is good and I have not touched it; the section at the end names what I would leave alone and why. Second, one item is a data problem rather than a wording problem, and it is flagged separately at the bottom rather than dressed up as an edit.

The recurring theme in the edits that matter: the front door never says what the business does or who it serves. A reader arriving at the README or the frontispiece learns the interface metaphor before learning the company.

## web/godly-codex.html

### 1. The frontispiece never says what the firm sells

Function `frontispiece()`, verso lede, line ~733.

**Current:**

~~~
    <p class="lede drop">Godly Base runs as a company of agents. This codex is the whole of it — the wording on the left page, the working instrument on the right, and every number in both pulled from the same database you can open, filter, and carry out in Chapter V.</p>
~~~

**Proposed:**

~~~
    <p class="lede drop">Godly Base sells sales, marketing, and research retainers to four trades, and runs the whole firm as a company of AI agents. This codex is the whole of it: the reasoning on the left page, the working instrument on the right, and every number in both pulled from the same database you can open, filter, and carry out in Chapter V.</p>
~~~

**Why:** the first sentence of the book should say what the business does and who pays for it; "runs as a company of agents" describes the method to a reader who does not yet know the business.

### 2. A vital label that reads as a puzzle

Function `frontispiece()`, recto vitals grid, line ~761.

**Current:**

~~~
      ${vital(DB.agents.length + " + 7", "Agents, then supervisors")}
~~~

**Proposed:**

~~~
      ${vital(DB.agents.length + " + 7", "Agents, plus 7 supervisors")}
~~~

**Why:** "then" asks the reader to work out what the two numbers are; "plus" names them.

### 3. A number the data does not support

Function `house()`, verso, "The chain", line ~784.

**Current:**

~~~
The <b>CEO</b> reads seven briefs, not two hundred runs.
~~~

**Proposed:**

~~~
The <b>CEO</b> reads seven briefs, not the three hundred-plus runs a day behind them.
~~~

**Why:** the seeded throughput totals 345 runs on the latest day across four departments, so "two hundred" undersells the point the sentence is making. If a figure that moves with the data feels brittle, "not every run behind them" is the durable alternative.

### 4. Straight quotes in rendered prose

Function `house()`, verso, "The chain", line ~784.

**Current:**

~~~
set what "good" means there
~~~

**Proposed:**

~~~
set what &ldquo;good&rdquo; means there
~~~

**Why:** everything else in the codex is typeset with care; these are the only straight quotes in the chapter prose.

### 5. A lede that needs a second read

Function `accountsCh()`, verso lede, line ~835.

**Current:**

~~~
    <p class="lede">Pipeline the way a CRM keeps it — stages, values, owners, next actions — but written where the reasoning can sit beside the row.</p>
~~~

**Proposed:**

~~~
    <p class="lede">Pipeline the way a CRM keeps it: stages, values, owners, next actions. The difference is that the reasoning sits beside the row.</p>
~~~

**Why:** the nested dashes bury the contrast, and the point of the chapter is that contrast.

### 6. Vague quantifiers where exact figures exist

Function `signalsCh()`, verso, "What the drop is telling us", line ~899.

**Current:**

~~~
    <p>Reached to engaged holds at roughly a fifth — respectable for cold, and the deliverability warming is doing its job. The expensive loss is <b>replied to booked</b>: four in five conversations die between a human answering and a meeting existing. That is a routing problem, not a copy problem, and it belongs to the qualifier agent's queue.</p>
~~~

**Proposed:**

~~~
    <p>Reached to engaged holds at 20%, which is respectable for cold and says the deliverability warming is working. The expensive loss is <b>replied to booked</b>: 513 replies produced 97 meetings, so four in five conversations end after a human answers. That is a routing problem, not a copy problem, and it belongs to the qualifier agent's queue.</p>
~~~

**Why:** the chapter argues that evidence should sit next to the claim, and the two figures are already on the same page in the funnel chart.

### 7. Four tiers buried in one paragraph

Function `alliancesCh()`, verso, "The program, in four tiers", line ~945.

**Current:**

~~~
    <p><b>Referral</b> — they name us, we pay on close. Lowest friction, entry tier for associations and adjusters. <b>Channel</b> — co-branded onboarding into a member base. <b>Reseller</b> — they sell an agent pod under their own name and we run it underneath. <b>Tech alliance</b> — no revenue share; they host or integrate, and both books get bigger.</p>
~~~

**Proposed:**

~~~
    <ul class="stack-sm" style="margin:0 0 10px 18px;padding:0">
      <li><b>Referral</b>: they name us, we pay on close. Lowest friction, and the entry tier for associations and adjusters.</li>
      <li><b>Channel</b>: co-branded onboarding into a member base.</li>
      <li><b>Reseller</b>: they sell an agent pod under their own name and we run it underneath.</li>
      <li><b>Tech alliance</b>: no revenue share. They host or integrate, and both books get bigger.</li>
    </ul>
~~~

**Why:** four parallel definitions are a list, and a partner scanning for their own tier should find it without reading the other three. Check the rendered spacing, since this is the first `ul` in the chapter prose.

### 8. A lede that trades clarity for cadence

Function `vaultCh()`, verso lede, line ~1024.

**Current:**

~~~
    <p class="lede">Twelve tables, one shape. Anything the business keeps is a row here first and a sentence somewhere else second.</p>
~~~

**Proposed:**

~~~
    <p class="lede">Twelve tables, one shape. Anything the business keeps becomes a row here before it becomes a sentence anywhere else.</p>
~~~

**Why:** "first" and "second" read as ordering within this page rather than precedence over the rest of the book.

### 9. A count labelled as something it is not

Function `nerveCh()`, recto vitals grid, line ~1115.

**Current:**

~~~
      ${vital(cloud.length.toString(), "Metered external services")}
~~~

**Proposed:**

~~~
      ${vital(cloud.length.toString(), "Services off the local cloud")}
~~~

**Why:** `cloud` is everything whose host is not the local cloud, which includes BBB.org and TruePeopleSearch. Neither is metered, and both are already counted in the "Manual-only, by policy" tile beside it. See the flag at the bottom of this document for the underlying double count.

### 10. The static running head names a chapter that does not exist

Markup, running head, line ~367.

**Current:**

~~~
        <span class="rh-title" id="rhTitle">The Standing Order</span>
~~~

**Proposed:**

~~~
        <span class="rh-title" id="rhTitle">An operating system bound as a book</span>
~~~

**Why:** `LEAVES[0].title` is "An operating system bound as a book", so the pre-render title flashes a name that appears nowhere else in the book.

### 11. The document title does not match the folio

Markup, line 1.

**Current:**

~~~
<title>Godly Base Codex</title>
~~~

**Proposed:**

~~~
<title>Godly Base · Operating Codex</title>
~~~

**Why:** the folio, the running head, and any shared link should agree on the name; "Operating Codex" is the phrase the footer already uses.

## README.md

The README is hard-wrapped, so the quoted blocks include their line breaks.

### 12. The opening paragraph describes the interface, not the company

Opening paragraph, lines 3 to 5.

**Current:**

~~~
An AI company bound as a book. The interface is a codex: the left page carries
the wording, the right page carries the working instrument, and every number on
both comes out of one database you can open, filter, sort, and take with you.
~~~

**Proposed:**

~~~
Godly Base runs a services firm as a company of AI agents, selling sales,
marketing, and research retainers to four trades: roofing and restoration, med
spa, commercial HVAC, and private security. The interface is a codex: the left
page carries the reasoning, the right page carries the working instrument, and
every number on both comes out of one database you can open, filter, sort, and
take with you.
~~~

**Why:** a reader landing on the repository should learn the business before the metaphor, and "wording" undersells the left page that the codex itself describes as arguing.

### 13. Name the relationship between Godly Base and Godly

New paragraph after the opening. **Hold this one until Joshua confirms the relationship**; see the top of `docs/BRAND.md`.

**Current:** (insert directly below the paragraph in edit 12, before the fenced file listing)

**Proposed:**

~~~
Godly Base is the operating system of the services firm. Godly, the Christian
community app, is a separate product by the same owner; the two share a name
root and nothing else, including their codebases.
~~~

**Why:** the two ventures share a name with no stated relationship, which is the single most confusing thing about this repository for a new reader. The wording above is a placeholder for whatever Joshua confirms, and should not ship before he does.

### 14. A macOS-only command presented as the way to run it

Section "Running it", line 39.

**Current:**

~~~
open web/godly-codex.html        # or: python3 -m http.server && visit /web/
~~~

**Proposed:**

~~~
open web/godly-codex.html        # macOS; xdg-open on Linux, start on Windows
python3 -m http.server           # or serve the repo and visit /web/
~~~

**Why:** the file opens anywhere, but the command as written only works on one platform, which contradicts the "no build step, no dependencies" claim above it.

### 15. Three unrelated rules in one bullet

Section "The rules that shape it", lines 61 to 62.

**Current:**

~~~
- **BBB and TruePeopleSearch stay manual**, LinkedIn goes through a compliant
  API, and sending reputation outranks send volume.
~~~

**Proposed:**

~~~
- **BBB and TruePeopleSearch stay manual.** No public API, and terms that
  prohibit bulk automation.
- **Sending reputation outranks send volume.** LinkedIn goes through a
  compliant API, and a bounce rate over 3% for two weeks stops the domain.
~~~

**Why:** every other rule in the list is one idea with a bolded name; this one carries three and loses the threshold that makes the last claim credible.

## What I would not touch

Called out so the lead can see where I looked and chose to leave the prose alone.

- **`frontispiece()`, the niches paragraph.** "We do not sell to everyone" is the sharpest positioning sentence in the repository, and the fifth-niche condition is exactly the kind of proof the brand voice asks for.
- **`house()`, the double-agent rule.** "Pairing is a structure, not a courtesy: an unpaired output is treated as a draft." Nothing to add.
- **`signalsCh()`, channel doctrine.** "Cold email carries volume, LinkedIn carries credibility, the newsletter carries patience." Three metaphor verbs that earn their place, because each one names a different real property of the channel.
- **`nerveCh()`, the lede and the Hunter marginalia.** Both accurate against `db/seed.json`: 16 connections, 5 on the local cloud, and the 50-credit tripwire matches the architecture.
- **`appendixCh()`, "Scraping, honestly".** The restraint paragraph is the most persuasive thing in the book for a buyer who has been burned by a scraper, and its closing line does the work.
- **`brainCh()`, the two-memories section.** "An agent that reads only the first repeats last quarter's mistakes with better formatting" is the best sentence in the codex.
- **The reserved chapters in `brainCh()`.** Naming the condition that opens each unwritten chapter is a stronger statement than any roadmap.
- **`accountsCh()`, "Nothing enters this book on a hunch."** Keep.

## Flagged, not edited

**The nerve counts two services twice.** `nerveCh()` splits `DB.api_keys` on `k.host === "local cloud"`, so BBB.org and TruePeopleSearch land in the "External, metered" card, get a meter rendered for them, and are counted both in the external tile and in the hard-coded "2" for manual-only. Edit 9 fixes the label, but the honest fix is a third bucket for `host: "web"`, rendered without a meter. That is a code change and belongs to the lead.
