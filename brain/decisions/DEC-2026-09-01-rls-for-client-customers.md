---
id: DEC-2026-09-01-rls-for-client-customers
owner: SUP-DEV
question: Does the godly schema need row-level security?
numbers: 7 client customers across 2 pods today; 4 deployments; 1 database
decision: Yes, on the five client-customer tables only. RLS enabled and FORCED, keyed on deployment_id, with the tenant read through a scalar subquery so it is evaluated once per query.
rejected: >
  Application-level filtering. Every read would have to remember a WHERE clause,
  and one forgotten clause in one agent's query leaks another client's customer
  list. Also rejected: RLS across the whole schema — Hero's own pipeline and
  finance tables have exactly one tenant, and policies there would cost a
  per-row filter to protect nothing.
reverses_if: >
  The client-customer tables move to a database per client, at which point the
  policy is redundant and should be removed rather than left as decoration.
links: [godly.customers, godly.jobs, godly.customer_interactions, godly.customer_invoices, godly.reviews, db/migrations/0006_client_customers.sql]
---

## Why this reverses an earlier decision

Migration 0002 deliberately did not add RLS, and the reasoning was sound at the
time: the database held one tenant — Hero's own pipeline, roster and finances —
and `using (true)` policies read as security while granting everything.

The shape changed. Migration 0006 introduced data belonging to *other people*:
each client's customers, their phone numbers, their jobs and their invoices, all
in one database. Ridgeway's pod and Bluecrest's pod are separate tenants whose
data must never meet. That is the exact condition RLS exists for, so the earlier
decision reverses under its own terms rather than being contradicted.

## What was verified, not assumed

The owner and superuser bypass RLS, so a test run as `postgres` would have
passed while proving nothing. The check was run as `godly_pod`:

- Ridgeway's tenant sees 4 customers, its own.
- Bluecrest's tenant sees 3, its own.
- **No tenant set returns 0 rows.** It fails closed; a connection that forgets
  to set `app.deployment_id` sees nothing rather than everything.
- A read of a Bluecrest row by primary key from Ridgeway's tenant returns nothing.
- An insert naming another tenant's `deployment_id` is rejected by `WITH CHECK`.

`FORCE ROW LEVEL SECURITY` is on every one of the five tables. Without it the
table owner — which is what a migration or a careless maintenance session runs
as — reads straight across every client.

## The consent trigger, decided at the same time

An agent that dials and texts consumers sits inside TCPA, and in two-party
states recording needs consent. A rule in a prompt is not a control: an agent
can be argued out of a prompt, including by a customer or by injected text in an
email it is reading. So do-not-contact and channel consent are enforced by a
trigger on `customer_interactions`. Verified: outbound SMS to a do-not-contact
customer is refused, outbound email without email consent is refused, and
inbound contact from the same customer is still allowed — because answering
someone who calls you is not solicitation.
