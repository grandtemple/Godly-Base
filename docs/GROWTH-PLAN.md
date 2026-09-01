# Growth plan

Seven marketing plays chosen for the firm as it stands today. Every play below is client-facing, so all of it ships under **Hero** — "Godly Base" is the internal name for the machine and never appears in market. The plays are drawn from the 139-idea library in the `marketing-ideas` skill. The point of this document is what we left out. A pre-revenue firm with one human seat can run about three plays well; the other four are staged behind them.

## The constraints these picks answer

- **Stage**: early. The pipeline in `db/seed.json` is the shape we are building toward, not a track record we can cite in public yet.
- **Team**: one human, seven supervisors, twenty-one agents. Agent hours are close to free. Joshua's hours are the scarce resource, and every play below is scored on how many of them it needs.
- **Buyer**: an owner or general manager at a regional roofing, med spa, HVAC, or security firm. They do not read software blogs, do not browse Product Hunt, and do not evaluate vendors on a comparison page.
- **Deal shape**: retainers of $28,000 to $96,000 over 6 to 12 months. A handful of closes makes the year, so channels are judged on qualified conversations, not on traffic.
- **Proof**: thin. We have doctrine, a working system, and no public case studies. Plays that manufacture proof are worth more right now than plays that spend it.

## Before any of this: fix the leak

The funnel says 513 replies produced 97 meetings. Four in five conversations end between a human answering and a meeting existing, and that is a routing problem inside the qualifier's queue. The codex already carries the standing rule: no new channel opens while an existing stage converts below half its niche benchmark.

Adding volume on top of a 19% reply-to-meeting rate wastes the volume. Plays 1 through 3 below start anyway, because they cost little and they compound slowly. Plays 4 through 7 wait for reply-to-meeting to clear 35%.

## The seven

### 1. Customer language (#139)

**What it is.** Mine the exact words the four buyer types use, and write every piece of copy from that vocabulary instead of ours.

**Why it fits.** It is the cheapest play available and every other play depends on it. Our channel doctrine already says the vocabulary is where the trust is, and the research pod is built to do this: crawling and structuring language is the same job as crawling and structuring companies. A roofing general manager says "crew capacity" and "supplement", not "operational efficiency". Getting that wrong costs the reply.

**How to start.** AG-RES-01 crawls trade forums, association discussion boards, subreddits, and public review text for each niche. AG-RES-03 pulls the objection and phrasing patterns out of our own reply corpus. AG-CNT-02 files a 100-phrase lexicon per niche into `/brain/niches/`, with a banned-word list beside it, and checks every draft against it.

**Success looks like.** Four lexicons live by day 21, and reply rate on the next sequence beats the prior one in the same niche. Decision date: 45 days after the first rewritten sequence ships.

**Resources.** Agent time only. About two hours of Joshua's review, once.

**Kill condition.** Reply rate does not move after two rewritten sequences per niche. The lexicons stay; the rewriting cadence stops.

### 2. Industry interviews (#101)

**What it is.** A standing interview series with owners and general managers in the four niches. Thirty minutes, recorded, published as a written teardown and a short clip.

**Why it fits.** This is the play that solves the proof problem without waiting for case studies. An interview request is the highest-acceptance cold ask available to a firm with no logos, it puts Joshua in front of the exact buyer, and one call produces research, a content asset, a relationship, and a qualification signal at the same time. It also feeds play 1 with language straight from the source.

**How to start.** AG-SALES-01 builds a list of 40 operators per niche who are not current prospects, so the ask stays clean. Joshua sends the invitation himself, in his own voice, offering the recording and the write-up to the guest first. AG-CNT-01 turns each call into a teardown for the newsletter and AG-CNT-03 cuts one clip.

**Success looks like.** Two interviews a week, one published piece a week, and at least one interviewee per month asking what we do. Decision date: 60 days.

**Resources.** Roughly two hours a week of Joshua's time, which is the largest ask in this plan and is deliberate.

**Kill condition.** Acceptance rate under 10% after 60 invitations, which would mean the ask is wrong rather than the play.

### 3. Founder-led LinkedIn (#39)

**What it is.** Joshua posts three times a week from his own account, and comments daily on posts by operators in the four niches.

**Why it fits.** The campaign data is blunt: LinkedIn booked 24 meetings from 960 touches, cold email booked 31 from 2,400. LinkedIn converts at roughly twice the rate per touch. It is also the one asset an agent-run company cannot fake, and it gives cold outbound a face to check. The voice profile is already documented, so drafting is cheap and editing is fast.

**How to start.** AG-CNT-01 drafts posts from real run data and interview material, never from generic advice. Joshua edits every post into his own voice before it goes out; nothing auto-posts under his name. AG-MKT-02 handles scheduling through Postiz and surfaces comment threads worth answering.

**Success looks like.** Ninety posts in the first quarter, and inbound replies that name a post. Decision date: 90 days, judged on booked meetings sourced to the account.

**Resources.** Twenty minutes a day of Joshua's time. Nothing else.

**Kill condition.** Fewer than three sourced conversations in 90 days. Drop to one post a week and reinvest the hours in play 2.

### 4. One calculator per niche (#18, framed by #15)

**What it is.** A single-purpose web calculator for each niche that prices a problem the buyer already argues about internally. Storm-season crew capacity for roofing. No-show cost for med spa. Work-order response time for HVAC. Post-coverage overtime for security.

**Why it fits.** These buyers make decisions on arithmetic they do in their heads badly. A calculator gives the partner channel something to distribute that is not a demo request, it earns links from association sites, and it captures intent at the moment the number surprises someone. The engineering cost is one day of agent work per tool, and the codex already proves we can ship a self-contained page.

**How to start.** AG-FIN-01 defines the arithmetic and the defaults for one niche, so the output survives an operator's scrutiny. AG-DEV-03 builds it as a single page with no signup gate, and an emailed copy of the result as the only capture. AG-MKT-03 instruments it and reports the completion rate weekly.

**Success looks like.** One tool live per niche, 200 completions a month across all four, and a fifth of completions leaving an email. Decision date: 60 days after the second tool ships.

**Resources.** Four to six agent-days total, plus Joshua signing off on each set of default numbers.

**Kill condition.** Under 50 completions a month once all four are live and distributed. Keep the best one, retire the rest.

### 5. Proprietary data content (#6)

**What it is.** Publish the numbers only we have: what an outbound program in each niche actually costs to run, which stages leak, what verification and enrichment cost per booked meeting, what an agent run costs.

**Why it fits.** Every agent-run firm claims efficiency and none of them show the ledger. We already record cost per run, per campaign, and per meeting in Postgres, so this is a query and an edit rather than a research project. It is the one content asset a competitor cannot copy, it earns links, and it is the honest form of proof while case studies are thin.

**How to start.** AG-FIN-03 defines a quarterly cost-and-conversion cut that can be published without exposing a client. AG-CNT-01 writes it and AG-CNT-02 checks every figure against the table it came from. Publish through the newsletter first, then break it into posts for play 3.

**Success looks like.** One quarterly report, cited or reshared by at least three people outside our list. Decision date: after the second report.

**Resources.** About three agent-days a quarter and one review pass by Joshua.

**Kill condition.** Two reports with no external citation and no sourced conversations.

### 6. Association sponsorship (#64)

**What it is.** Sponsor the newsletters, chapter meetings, and member briefings of trade associations in the four niches, with the calculator as the offer rather than a sales page.

**Why it fits.** The partner pipeline already runs through exactly these bodies: an adjusters network, a practice collective, a facilities consortium, a guard association. Their newsletters reach the buyer with borrowed trust, they cost hundreds rather than thousands, and the placement gives the alliance manager a reason to open a conversation that is not a revenue-share ask. It is the fastest path to credibility with people who ignore vendors.

**How to start.** AG-BD-01 scores every association per niche on member count, newsletter frequency, and sponsorship cost. AG-BD-02 books two placements in the strongest niche only, so we can read the result. AG-MKT-03 tracks each placement with its own destination so attribution is unambiguous.

**Success looks like.** Two placements produce enough calculator completions to price a third. Decision date: 30 days after the second placement runs.

**Resources.** A small budget, likely under $2,000 for a first round, plus agent time.

**Kill condition.** Two placements, fewer than 20 completions between them. Stop buying placements and keep the partner relationships.

### 7. Inbox placement (#50)

**What it is.** Treat deliverability as a growth channel: authentication, separate sending domains per niche, warmup schedules, seed-list monitoring, and verification at send time.

**Why it fits.** Outbound is the volume channel and the architecture already names sending reputation as the asset, with a bounce rate over 3% for two weeks stopping the domain. That guardrail protects us from disaster but does not improve placement. Every point of inbox placement multiplies every other play that touches email, including the newsletter and the interview invitations. It is unglamorous and it gates the rest.

**How to start.** AG-DEV-01 sets SPF, DKIM, and DMARC on every sending domain and separates the domains by niche so one burned reputation cannot take the others. AG-MKT-01 runs a warmup schedule before any new domain carries volume and holds the ramp. AG-FIN-02 keeps Hunter verification rationed to contacts about to be emailed, as the credit rules already require.

**Success looks like.** Bounce rate under 2%, spam-placement rate under 5% on a seeded test, and reply rate rising without volume rising. Decision date: 30 days.

**Resources.** Two agent-days to set up, then monitoring. No human time beyond approving the domain purchases.

**Kill condition.** None. This is maintenance, not an experiment.

## Sequence

- **Days 1 to 30**: play 1 and play 7 in parallel, play 2 invitations go out. Qualifier routing gets fixed alongside them.
- **Days 31 to 60**: play 3 starts on the back of interview material. First calculator ships if reply-to-meeting has cleared 35%.
- **Days 61 to 90**: remaining calculators, first association placements, first data report drafted.
- **Review at day 90**: keep the two plays that sourced conversations, cut the rest, and do not add a play to replace what was cut until the survivors are running without Joshua.

## What we are skipping, and why

- **Programmatic SEO (#4) and glossary marketing (#3)**: the search volume across four regional trades does not justify template pages, and a new domain will not rank in the window that matters. Revisit when one niche is profitable.
- **Paid ads, all of #23 to #34**: no budget to lose and no proven message to amplify. Ads multiply a working offer; they do not find one.
- **Product Hunt and launch plays (#77 to #86)**: the audience there does not buy retainers for roofing firms.
- **Comparison pages against 11x or Artisan (#11)**: our buyer has never heard of them. These belong in the sales deck, not on the site.
- **Community building (#35)**: it needs an audience before it needs a Slack. Play 2 builds the audience first.
- **Review sites and directories (#128, #129)**: G2 and Capterra rank software, not services firms.
- **Lifetime deals (#86) and giveaways (#83 to #85)**: wrong revenue model and wrong signal for a $50,000 retainer.
- **Engagement pods (#43)**: manufactured engagement, and it contradicts the evidence discipline in the architecture.
- **Open source as marketing (#123)**: the audience for it is developers, and no developer signs our retainer.

## If Godly the app is the priority instead

This plan is written for the services firm. If the community app becomes the growth object, almost none of it transfers. That plan would run on app store optimization (#124), church and small-group partnerships as the distribution channel (#64 in a different form), two-sided referrals (#137), short-form video from real testimonies (#42), and the newsletter already documented in the `godly-newsletter` skill (#49). The two plans share one play only: customer language.

Settle the question in `docs/BRAND.md` before spending on either.
