# Payments and invoicing

Yes — and the first decision is not which processor. It is *whose money moves*.

Hero has two payment flows that look similar and are legally nothing alike.
Building them on one integration is the expensive mistake.

## The two flows

**Flow A — Hero gets paid.** Retainers, setup fees, overage. Hero is the
merchant of record. Money moves client → Hero. This is ordinary SaaS billing.

**Flow B — the client gets paid.** The `FO-06 Payment` capability we sell
(the customer, the job and the invoice all live in the tables added by
migration 0006, isolated per client):
the agent takes a deposit, sends the invoice, and chases the balance from *the
client's own customers*. Money moves homeowner → roofing company. Hero is not
in that chain and must not be.

|  | Flow A | Flow B |
|---|---|---|
| Merchant of record | Hero Capital | The client |
| Funds settle to | Hero's bank | The client's bank |
| Hero's role | seller | operator of the client's account |
| Hero's revenue | the retainer | the retainer — never a cut of the flow |
| If it breaks | we chase our own invoice | the client's customer is unhappy |

### Why Hero never touches Flow B money

The moment Hero receives, holds, or routes a customer's payment to a client,
that is money transmission. It brings licensing, KYC, AML monitoring, and
chargeback liability. Stripe's own guidance is explicit that a platform
handling other people's money is on the hook for risk, fraud and regulatory
compliance, and that Stripe's automated controls do not replace the platform's
own risk program.

For a firm of one human and twenty-one agents, that is not a cost problem. It is
an existential one. So the rule is structural, not aspirational:

> **The client is the merchant of record on every Flow B payment. Hero holds a
> delegated key, never the funds.**

This is enforced in the schema — `payment_accounts` carries a CHECK that a
client-owned account can never be marked as settling to Hero — not just written
down here where it can be forgotten under deadline.

## What to connect

### Flow A — billing Hero's clients
[Stripe Billing](https://stripe.com/billing) — subscriptions for the monthly
pod, one-off invoices for setup, metered usage for call minutes over plan. Our
`retainers` table maps to a subscription, `invoices` to a Stripe invoice, and
`price_book` to Stripe Prices. One provider, one webhook, done.

Alternative if accounting comes first: [QuickBooks](https://developer.intuit.com/)
or [Xero](https://developer.xero.com/) as the invoice system of record with a
payment processor attached. Slower to build, better if a bookkeeper already
lives there.

### Flow B — the agent operating a client's payments
[Stripe Connect **Standard** accounts](https://stripe.com/connect), connected by
OAuth. The client onboards to their own Stripe account, presses Connect, and
Hero receives a delegated key. The client stays merchant of record, owns the
dispute process, and can revoke us in one click. Hero's agent creates payment
links and invoices *on their account*.

Deliberately **not** Custom or Express accounts, and deliberately no application
fee on the flow — both pull Hero toward being the payment facilitator, which is
the thing the rule above exists to prevent.

Many trade clients already run [Square](https://developer.squareup.com/),
[ServiceTitan](https://developer.servicetitan.io/) or QuickBooks Payments. The
same shape applies: the client keeps the merchant relationship, Hero gets
scoped API access. `payment_accounts.provider` exists so a second and third
provider do not require a schema change.

## Card data: none of it

Hosted checkout and payment links only. No card number ever reaches Hero's
servers, our logs, or an agent's context window. That keeps PCI scope at
SAQ-A — the smallest questionnaire — and it is the reason the agent sends a
link rather than "reading the card number back to confirm."

An agent that is offered a card number over the phone does not write it down.
It sends the link.

## Idempotency, or how you double-charge someone

Webhooks arrive more than once. Retries happen. An agent that re-runs a step
after a timeout will happily create a second payment intent. The defence is a
ledger, not care:

- `payment_events` stores every webhook with `unique (provider, external_event_id)`.
  A replayed event hits the constraint and is ignored.
- Every write to a provider sends an idempotency key derived from our own row id,
  so a retried create returns the original object instead of a second charge.
- Payments reconcile to invoices by provider object id, never by amount and date.
  Two invoices for the same client in the same month at the same price is normal.

## The dunning ladder

Chasing money is a capability we sell, so we run it on ourselves the same way.
Escalation is by schedule, not by mood:

| Day | Step | Channel | Who |
|---|---|---|---|
| Due − 3 | Reminder | Email | agent |
| Due + 1 | First notice | Email | agent |
| Due + 7 | Second notice | Email + SMS | agent |
| Due + 14 | Call | Phone | agent |
| Due + 21 | Escalation | Call | **human** |
| Due + 30 | Service pause decision | — | CEO |

`dunning_attempts` records every step with its outcome, so "we chased them"
is a query rather than a memory. The ladder stops the moment a payment posts.
A human takes over at day 21 because the conversation stops being about an
invoice and starts being about the relationship.

## What goes wrong, and what we do about it

| Failure | Response |
|---|---|
| Webhook missed entirely | Nightly reconciliation sweep against the provider's list API; `unreconciled_payments` should always be empty |
| Card declines on renewal | Smart retries, then the ladder. Never silently drop service |
| Client revokes our Connect access | `payment_accounts.status` flips to `revoked`; FO-06 disables for that deployment and the supervisor is told |
| Chargeback on a client's customer | The client's dispute, on the client's account. Hero assists, never pays |
| Provider outage | Payments queue; the agent never tells a customer a payment succeeded until the webhook confirms it |

## What is built and what is not

**Built here:** the schema, the constraints, the reconciliation and dunning read
models, the OS surface, and the registry entries — everything that does not need
a live key.

**Not built:** the provider connection itself. No Stripe key exists yet, and the
Stripe connector was not available in the session that built this. When a key
exists, the work is the webhook endpoint, the OAuth callback for Connect, and
the nightly sweep. The tables are already the shape those three need.
