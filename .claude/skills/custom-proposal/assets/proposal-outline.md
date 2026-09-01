# Proposal outline — fill in, then delete every bracket

Client-facing. Plain language, no internal agent ids, no vocabulary the client
would not use about their own business.

---

## [Client legal name] — [engagement name]
Prepared for [decision owner, by name and title] · [date] · valid through [date]

### 1. What we heard
[3–5 specifics from discovery, in their words, with dates. Names of people and
systems they mentioned. If you cannot fill this from /brain/accounts/<slug>.md,
discovery is not finished.]

### 2. What it is costing
[The gap in their numbers: volume, hours, response times, close rate, no-show
rate. One quantified line beats a paragraph of adjectives. Cite where the number
came from — their words or their data.]

### 3. What we will do
**Workstream A — [name]**
- [Deliverable, with the form it takes]
- [Deliverable]

**Workstream B — [name]**
- [Deliverable]

**First 30 days:** [the specific things that exist by day 30]

### 4. How it runs
- Cadence: [weekly call / async report + monthly review]
- Your point of contact: [who, response time]
- Reporting: [what they see, where, how often]
- We will need: [access, accounts, introductions, data]

### 5. Proof
[One engagement in this niche, with numbers and a timeframe. If there is not
one, name the closest adjacent work and say plainly that they would be the first
in this segment. Never invent a case study or a metric.]

### 6. Investment
| | |
|---|---|
| Engagement | [name] |
| Term | [12 mo retainer / 6 mo pilot / project] |
| Investment | [$X / month, or $X total] |
| Included | [scope boundaries, in plain terms] |
| Not included | [the explicit exclusions — this section prevents the fight] |

[Priced with AG-FIN-01. Margin at this price: internal only, never in this
document.]

### 7. What we need from you
- Decision owner: [name]
- Access to: [systems]
- To start [date], we need [item] by [date]

### 8. The line
Start date [date] · term [term] · [what signing means and what happens next]

---

## Internal block — do not send

```yaml
account_id:      ACC-####
deal_id:         DEAL-###
niche:           [niche_id]
playbook:        /brain/niches/<slug>.md
account_note:    /brain/accounts/<slug>.md
priced_by:       AG-FIN-01
cost_to_serve:   $[monthly]
margin_at_price: [%]
floor_margin:    [% — from AG-FIN-01, this engagement shape]
below_floor:     no | yes → CEO sign-off DEC-YYYY-MM-DD-<slug>
custom_terms:    none | [terms → CEO]
drive_path:      /Hero/Clients/<account>/
run_status:      review → ok once AG-FIN-01 signs
```
