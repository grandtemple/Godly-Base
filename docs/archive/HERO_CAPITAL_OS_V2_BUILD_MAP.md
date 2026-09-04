# Hero Capital OS v2 Build Map

> **Archived — out of scope.** This document describes a 3-company umbrella
> (agency + Trading & Investments + Real Estate). Only the agency —
> what this repo actually builds as **Hero Capital OS** — is in scope; Trading
> & Investments and Real Estate have no schema, agents, or code anywhere and
> are not planned. Kept here for provenance only. See `docs/ROADMAP.md` for
> the actual chronological build plan.

## Umbrella

Hero Capital
- NIT Digital Agency
- Trading & Investments
- Real Estate

No Auto Basic Care domain is included.

Healthcare/FHIR remains an installed future capability only. It is not created as an operating company.

## Shared Hero Capital platform

1. Hero Capital Command Center
   - parent-level governance
   - portfolio KPIs
   - approvals
   - audit visibility
   - AI activity

2. Supabase/Postgres
   - identity
   - company-scoped records
   - RLS
   - migrations
   - pgvector for semantic memory

3. AI Orchestrator
   - Claude
   - OpenAI
   - ChatGPT-facing workflows
   - local llama.cpp brain
   - company/context routing

4. Hero Capital MCP
   - narrow tools
   - company-aware permissions
   - document access
   - reporting
   - workflow requests
   - no unrestricted production shell/database access

5. Policy and Risk
   - deterministic authorization
   - approval thresholds
   - trading limits
   - money-movement controls
   - kill switches

6. Audit
   - actor
   - agent/model
   - company
   - tool/action
   - approval
   - trace
   - result

## Company build domains

### NIT Digital Agency
- CRM
- marketing operations
- client onboarding
- proposals
- software delivery
- automation
- analytics
- billing integrations

### Trading & Investments
- research
- equity analysis
- market data
- backtesting
- portfolio analytics
- risk engine
- broker adapters
- approvals
- journal/audit

### Real Estate
- sourcing
- acquisition pipeline
- underwriting
- due diligence
- comparable analysis
- document room
- vendor management
- asset management
- portfolio valuation

## Installed skill groups

Architecture and governance:
- architecture
- risk-assessment

Engineering:
- setup-matt-pocock-skills
- domain-modeling
- to-prd
- improve-codebase-architecture
- tdd
- git-guardrails-claude-code

Data:
- supabase
- supabase-postgres-best-practices

AI and MCP:
- mcp-builder
- claude-api
- skill-creator
- openai-docs
- chatgpt-apps 
- Google Gemeni

Security:
- agent-security-audit

Portfolio and investing:
- portfolio-monitoring
- equity-research
- ai-readiness

Future healthcare capability:
- fhir
- fhir-developer-skill

Liquid Assets 
**- Products we can package and sell within 7 days **
- Products we can package and sell within 14 days 

## Control flow

User or scheduled workflow
-> Hero Capital AI Orchestrator
-> domain agent
-> approved MCP tool
-> policy/risk engine
-> human approval when required
-> service/database/API action
-> audit event

For trading:
AI thesis
-> deterministic risk check
-> approval
-> broker adapter
-> execution
-> audit and portfolio update

The model never becomes the risk engine.
