#!/usr/bin/env python3
"""Load db/seed.json into the godly schema, in one transaction.

The seed is a UI fixture, not a dump: it names things where the database needs
keys. This resolves those names to ids, in the order db/README.md documents.

    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0001_baseline.sql
    python scripts/load_seed.py                 # uses DATABASE_URL
    python scripts/load_seed.py --dsn "postgresql://..." --truncate
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / "db" / "seed.json"

slug = lambda s: re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")

# Tables truncated by --truncate, children first.
WIPE = ["reviews", "customer_invoices", "customer_interactions", "jobs", "customers",
        "dunning_attempts", "payments", "payment_events", "payment_accounts",
        "invoices", "retainers", "quote_lines", "quotes", "price_book",
        "deployment_capabilities", "deployments", "front_office_capabilities",
        "department_throughput", "funnel_snapshots", "agent_runs", "content_items",
        "campaigns", "partners", "deals", "contacts", "accounts", "sources",
        "integrations", "brain_map", "decisions", "agents", "supervisors",
        "departments", "niches", "deal_stages", "funnel_stages", "company_profile"]


def load(cur, seed):
    counts = {}
    def one(table, n=1):
        counts[table] = counts.get(table, 0) + n

    # 1. company_profile — the firm and the human seat
    meta, principal = seed["meta"], seed["org"]["principal"]
    cur.execute("""insert into godly.company_profile (company_name, founded_year, brain_uri,
                     principal_name, principal_role, principal_note)
                   values (%s,%s,%s,%s,%s,%s) on conflict (id) do nothing""",
                (meta["company"], int(meta["founded"]), meta["brain"],
                 principal["name"], principal["role"], principal["note"]))
    one("company_profile")

    # 2. niches — the four we serve, plus the cross-niche bucket partners use
    niche_id = {}
    for name in meta["niches"]:
        niche_id[name] = slug(name)
        cur.execute("""insert into godly.niches (id, name, playbook_path, is_focus)
                       values (%s,%s,%s,true) on conflict (id) do nothing""",
                    (slug(name), name, f"/brain/niches/{slug(name)}.md"))
        one("niches")
    niche_id["Cross-niche"] = "cross-niche"
    cur.execute("""insert into godly.niches (id, name, playbook_path, is_focus)
                   values ('cross-niche','Cross-niche',null,false) on conflict (id) do nothing""")
    one("niches")

    # 3-5. the roster: departments, their supervisors, then agents
    for order, c in enumerate(seed["org"]["chiefs"]):
        label = c["title"].replace("Chief ", "").replace(" Officer", "")
        cur.execute("""insert into godly.departments (code, name, title, chief_name, charter, sort_order)
                       values (%s,%s,%s,%s,%s,%s) on conflict (code) do nothing""",
                    (c["code"], label, c["title"], c["agentName"], c["charter"], order))
        one("departments")
        s = c["supervisor"]
        cur.execute("""insert into godly.supervisors (id, department_code, name, cadence)
                       values (%s,%s,%s,%s) on conflict (id) do nothing""",
                    (s["id"], c["code"], s["name"], s["cadence"]))
        one("supervisors")

    cur.execute("set constraints all deferred")   # duo_partner points forward
    for c in seed["org"]["chiefs"]:
        for u in c["units"]:
            cur.execute("""insert into godly.agents (id, name, department_code, reports_to,
                             duo_partner, charter, memory_path, status)
                           values (%s,%s,%s,%s,%s,%s,%s,%s) on conflict (id) do nothing""",
                        (u["id"], u["name"], c["code"], c["supervisor"]["id"], u["duo"], u["job"],
                         f"/brain/agents/{u['id'].lower()}.md",
                         "hot" if u["runs"] > 150 else "active" if u["runs"] > 50 else "idle"))
            one("agents")

    # 6. vocabularies that carry a display order
    for i, s in enumerate(["New","Qualified","Discovery","Proposal","Negotiation","Closed Won","Closed Lost"]):
        cur.execute("""insert into godly.deal_stages (stage, sort_order, is_closed, is_won)
                       values (%s,%s,%s,%s) on conflict (stage) do nothing""",
                    (s, i, s.startswith("Closed"), s == "Closed Won"))
        one("deal_stages")
    for i, f in enumerate(seed["funnel"]):
        cur.execute("""insert into godly.funnel_stages (stage, sort_order, description)
                       values (%s,%s,%s) on conflict (stage) do nothing""",
                    (f["stage"], i, f["note"]))
        one("funnel_stages")

    # 7. accounts, plus a stub for any account named only by a deal
    acct_id = {}
    for a in seed["accounts"]:
        cur.execute("""insert into godly.accounts (ref, name, niche_id, city, employees,
                         revenue_band, owner_verified, source, fit_score, vault_note)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) returning id""",
                    (a["id"], a["name"], niche_id.get(a["niche"]), a["city"], a["employees"],
                     a["revenue_band"], a["owner_verified"], a["source"], a["score"],
                     f"/brain/accounts/{slug(a['name'])}.md"))
        acct_id[a["name"]] = cur.fetchone()[0]; one("accounts")
    for d in seed["deals"]:
        if d["account"] not in acct_id:           # derived from the deal, not invented
            cur.execute("""insert into godly.accounts (name, niche_id, vault_note)
                           values (%s,%s,%s) returning id""",
                        (d["account"], niche_id.get(d["niche"]), f"/brain/accounts/{slug(d['account'])}.md"))
            acct_id[d["account"]] = cur.fetchone()[0]; one("accounts (stub)")

    # 8. contacts, plus a stub for any deal champion with no contact row
    con_id = {}
    for c in seed["contacts"]:
        src = next(a for a in seed["accounts"] if a["id"] == c["account_id"])
        cur.execute("""insert into godly.contacts (ref, account_id, name, title, email,
                         email_status, phone, linkedin, channel, last_touch_at)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) returning id""",
                    (c["id"], acct_id[src["name"]], c["name"], c["title"], c["email"],
                     c["email_status"], None if c["phone"] == "—" else c["phone"],
                     c["linkedin"], c["channel"], c["last_touch"]))
        con_id[c["name"]] = cur.fetchone()[0]; one("contacts")
    for d in seed["deals"]:
        if d["contact"] not in con_id:
            cur.execute("""insert into godly.contacts (account_id, name, email_status)
                           values (%s,%s,'unverified') returning id""",
                        (acct_id[d["account"]], d["contact"]))
            con_id[d["contact"]] = cur.fetchone()[0]; one("contacts (stub)")

    # 9. deals — names resolved to ids
    for d in seed["deals"]:
        cur.execute("""insert into godly.deals (ref, account_id, contact_id, stage, value_usd,
                         term, probability, owner_agent, next_action, opened_at)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (d["id"], acct_id[d["account"]], con_id[d["contact"]], d["stage"], d["value"],
                     None if d["term"] == "—" else d["term"], d["prob"], d["owner"],
                     d["next"], d["opened"]))
        one("deals")

    # 10. the rest of the business
    for p in seed["partners"]:
        share = None if p["rev_share"] == "—" else float(p["rev_share"].rstrip("%"))
        cur.execute("""insert into godly.partners (ref, name, partner_type, niche_id, stage,
                         intros_per_month, rev_share_pct, owner_agent, note)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (p["id"], p["name"], p["type"], niche_id.get(p["niche"]), p["stage"],
                     p["deal_flow_mo"], share, p["owner"], p["note"]))
        one("partners")
    for c in seed["campaigns"]:
        cur.execute("""insert into godly.campaigns (ref, name, channel, niche_id, owner_agent,
                         status, sent, replied, booked, won)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (c["id"], c["name"], c["channel"], niche_id.get(c["niche"]), c["owner"],
                     c["status"], c["sent"], c["replied"], c["booked"], c["won"]))
        one("campaigns")
    for c in seed["content"]:
        cur.execute("""insert into godly.content_items (ref, title, format, niche_id, channels,
                         status, publish_at, owner_agent)
                       values (%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (c["id"], c["title"], c["format"], niche_id.get(c["niche"]),
                     [x.strip() for x in c["channel"].split(",")], c["status"], c["date"], c["owner"]))
        one("content_items")

    # 11. measurements
    for f in seed["funnel"]:
        cur.execute("""insert into godly.funnel_snapshots (stage, stage_count, note)
                       values (%s,%s,%s) on conflict do nothing""", (f["stage"], f["count"], f["note"]))
        one("funnel_snapshots")
    dept_of = {"Sales":"CSO", "Marketing":"CMO", "Research":"CIO", "Content":"CCO"}
    for dept, series in seed["throughput"].items():
        for offset, runs in enumerate(reversed(series)):
            cur.execute("""insert into godly.department_throughput (department_code, captured_on, runs)
                           values (%s, current_date - %s, %s) on conflict do nothing""",
                        (dept_of[dept], offset, runs))
            one("department_throughput")

    # 12. agent_runs — dated relative to today so agent_load_7d has something to see
    for i, r in enumerate(seed["agent_runs"]):
        cur.execute("""insert into godly.agent_runs (run_ref, agent_id, task, started_at,
                         duration_s, rows_touched, status, cost_usd, note_path)
                       values (%s,%s,%s, now() - make_interval(hours => %s), %s,%s,%s,%s,%s)""",
                    (r["id"], r["agent"], r["task"], i * 3, r["dur_s"], r["rows"], r["status"],
                     float(r["cost"].lstrip("$")), f"/brain/agents/{r['agent'].lower()}.md"))
        one("agent_runs")

    # 13. the product: the capability catalogue and who is running it
    for order, f in enumerate(seed["front_office"]):
        cur.execute("""insert into godly.front_office_capabilities (id, capability, channel, does,
                         replaces, writes_to, status, sort_order)
                       values (%s,%s,%s,%s,%s,%s,%s,%s) on conflict (id) do nothing""",
                    (f["id"], f["capability"], f["channel"], f["does"], f["replaces"],
                     f["writes"], f["status"], order))
        one("front_office_capabilities")
    for d in seed["deployments"]:
        cur.execute("""insert into godly.deployments (account_id, client_name, niche_id, stage,
                         live_since, note, ended_on, ended_reason)
                       values (%s,%s,%s,%s,%s,%s,%s,%s) returning id""",
                    (acct_id.get(d["client"]), d["client"], niche_id.get(d["niche"]),
                     d["stage"], d["since"], d["note"], d.get("ended_on"), d.get("ended_reason")))
        dep = cur.fetchone()[0]; one("deployments")
        for cap in d["live"]:
            cur.execute("""insert into godly.deployment_capabilities (deployment_id, capability_id)
                           values (%s,%s) on conflict do nothing""", (dep, cap))
            one("deployment_capabilities")

    # 14. the money: price book, quotes, retainers, invoices
    for pb in seed["price_book"]:
        cur.execute("""insert into godly.price_book (code, name, capability_id, billing, list_price,
                         unit, cost_to_serve, floor_price, notes)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s) on conflict (code) do nothing""",
                    (pb["code"], pb["name"], pb["capability"], pb["billing"], pb["list"],
                     pb["unit"], pb["cost"], pb["floor"], pb["notes"]))
        one("price_book")

    deal_id = {}
    cur.execute("select ref, id from godly.deals where ref is not null")
    deal_id = dict(cur.fetchall())
    quote_id = {}
    for q in seed["quotes"]:
        cur.execute("""insert into godly.quotes (ref, deal_id, account_id, status, term_months,
                         sent_on, decided_on, prepared_by, priced_by, ceo_override, notes)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) returning id""",
                    (q["ref"], deal_id.get(q["deal"]), acct_id[q["account"]], q["status"], q["term_months"],
                     q["sent_on"], q["decided_on"], q["prepared_by"], q["priced_by"], q["ceo_override"], q["notes"]))
        quote_id[q["ref"]] = cur.fetchone()[0]; one("quotes")
        for ln in q["lines"]:
            cur.execute("""insert into godly.quote_lines (quote_id, code, quantity, unit_price)
                           values (%s,%s,%s,%s) on conflict do nothing""",
                        (quote_id[q["ref"]], ln["code"], ln["qty"], ln["price"]))
            one("quote_lines")

    cur.execute("select client_name, id from godly.deployments")
    dep_id = dict(cur.fetchall())
    retainer_id = {}
    for r in seed["retainers"]:
        cur.execute("""insert into godly.retainers (account_id, deployment_id, quote_id, mrr,
                         cost_to_serve, started_on, term_months, status, ended_on, churn_reason)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) returning id""",
                    (acct_id[r["account"]], dep_id.get(r["deployment"]), quote_id.get(r["quote"]),
                     r["mrr"], r["cost"], r["started_on"], r["term_months"], r["status"],
                     r["ended_on"], r["churn_reason"]))
        retainer_id[r["account"]] = cur.fetchone()[0]; one("retainers")

    for inv in seed["invoices"]:
        y, m = inv["period"].split("-")
        cur.execute("""insert into godly.invoices (ref, retainer_id, account_id, period_start, period_end,
                         amount, issued_on, due_on, paid_on, status)
                       values (%s,%s,%s, make_date(%s,%s,1),
                               (make_date(%s,%s,1) + interval '1 month - 1 day')::date,
                               %s,%s,%s,%s,%s)""",
                    (inv["ref"], retainer_id.get(inv["retainer"]), acct_id[inv["account"]],
                     int(y), int(m), int(y), int(m),
                     inv["amount"], inv["issued_on"], inv["due_on"], inv["paid_on"], inv["status"]))
        one("invoices")

    # 15. payments: accounts first, then what moved, then the ladder
    cur.execute("select ref, id from godly.invoices where ref is not null")
    inv_id = dict(cur.fetchall())
    pay_acct = {}
    for pa in seed["payment_accounts"]:
        cur.execute("""insert into godly.payment_accounts (provider, owner, account_id, external_id,
                         access, settles_to_hero, status, connected_on, note)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s) returning id""",
                    (pa["provider"], pa["owner"], acct_id.get(pa["account"]), pa["external_id"],
                     pa["access"], pa["settles_to_hero"], pa["status"], pa["connected_on"], pa["note"]))
        pay_acct[(pa["provider"], pa["owner"], pa["account"])] = cur.fetchone()[0]
        one("payment_accounts")

    for pm in seed["payments"]:
        key = (pm["provider"], pm["owner"], None if pm["owner"] == "hero" else pm["account"])
        cur.execute("""insert into godly.payments (payment_account_id, invoice_id, deployment_id,
                         external_id, amount, method, status, paid_at, failure_reason)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (pay_acct[key], inv_id.get(pm["invoice"]), None, pm["external_id"], pm["amount"],
                     pm["method"], pm["status"], pm["paid_at"], pm["failure_reason"]))
        one("payments")

    for d in seed["dunning_attempts"]:
        cur.execute("""insert into godly.dunning_attempts (invoice_id, step, channel, by_agent,
                         attempted_at, outcome, note)
                       values (%s,%s,%s,%s,%s,%s,%s) on conflict do nothing""",
                    (inv_id[d["invoice"]], d["step"], d["channel"], d["by_agent"],
                     d["attempted_at"], d["outcome"], d["note"]))
        one("dunning_attempts")

    # 16. the client's customers — the third party the pod actually serves.
    #     A pod agent reaches these through RLS; the loader runs as owner.
    cust_id = {}
    for c in seed["customers"]:
        cur.execute("""insert into godly.customers (deployment_id, name, phone, email, address,
                         arrived_via, consent_sms, consent_email, consent_recording,
                         do_not_contact, first_seen)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) returning id""",
                    (dep_id[c["deployment"]], c["name"], c["phone"], c["email"], c["address"],
                     c["arrived_via"], c["consent_sms"], c["consent_email"], c["consent_recording"],
                     c["do_not_contact"], c["first_seen"]))
        cust_id[(c["deployment"], c["name"])] = cur.fetchone()[0]; one("customers")
    for c in seed["customers"]:                       # referrals resolve after every row exists
        if c["referred_by"]:
            cur.execute("update godly.customers set referred_by = %s where id = %s",
                        (cust_id[(c["deployment"], c["referred_by"])], cust_id[(c["deployment"], c["name"])]))

    job_id = {}
    for j in seed["jobs"]:
        cur.execute("""insert into godly.jobs (deployment_id, customer_id, title, service_type,
                         status, value, scheduled_for, completed_on, booked_by, lost_reason)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) returning id""",
                    (dep_id[j["deployment"]], cust_id[(j["deployment"], j["customer"])], j["title"],
                     j["service_type"], j["status"], j["value"], j["scheduled_for"], j["completed_on"],
                     None if j["booked_by"] == "POD" else j["booked_by"], j["lost_reason"]))
        job_id[(j["deployment"], j["title"])] = cur.fetchone()[0]; one("jobs")

    for i in seed["customer_interactions"]:
        cur.execute("""insert into godly.customer_interactions (deployment_id, customer_id, job_id,
                         channel, direction, handled_by, occurred_at, duration_s, outcome, summary, escalated_to)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (dep_id[i["deployment"]], cust_id[(i["deployment"], i["customer"])],
                     job_id.get((i["deployment"], i["job"])), i["channel"], i["direction"],
                     None if i["handled_by"] == "POD" else i["handled_by"], i["occurred_at"],
                     i["duration_s"], i["outcome"], i["summary"], i["escalated_to"]))
        one("customer_interactions")

    for ci in seed["customer_invoices"]:
        cur.execute("""insert into godly.customer_invoices (deployment_id, job_id, external_id,
                         amount, deposit, issued_on, due_on, paid_on, status)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (dep_id[ci["deployment"]], job_id[(ci["deployment"], ci["job"])], ci["external_id"],
                     ci["amount"], ci["deposit"], ci["issued_on"], ci["due_on"], ci["paid_on"], ci["status"]))
        one("customer_invoices")

    for r in seed["reviews"]:
        cur.execute("""insert into godly.reviews (deployment_id, job_id, platform, requested_on,
                         left_on, rating, status)
                       values (%s,%s,%s,%s,%s,%s,%s) on conflict do nothing""",
                    (dep_id[r["deployment"]], job_id[(r["deployment"], r["job"])], r["platform"],
                     r["requested_on"], r["left_on"], r["rating"], r["status"]))
        one("reviews")

    # 17. the registry, the reading list, the brain map
    for k in seed["api_keys"]:
        cur.execute("""insert into godly.integrations (ref, service, purpose, env_var, host,
                         status, used, quota, unit)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (k["id"], k["service"], k["purpose"],
                     None if k["env"].startswith("—") else k["env"],
                     k["host"], k["status"], k["used"], k["limit"], k["unit"]))
        one("integrations")
    for s in seed["sources"]:
        cur.execute("""insert into godly.sources (name, category, url, kind, verdict, note)
                       values (%s,%s,%s,%s,%s,%s) on conflict do nothing""",
                    (s["name"], s["cat"], s["url"], s["kind"], s["verdict"], s["note"]))
        one("sources")
    for b in seed["brain"]:
        cur.execute("""insert into godly.brain_map (path, zone, holds, written_by, read_by)
                       values (%s,%s,%s,%s,%s) on conflict (path) do nothing""",
                    (b["path"], b["zone"], b["holds"], b["writer"], b["read_by"]))
        one("brain_map")
    return counts


def main():
    ap = argparse.ArgumentParser(description="Load db/seed.json into the godly schema.")
    ap.add_argument("--dsn", default=os.environ.get("DATABASE_URL"))
    ap.add_argument("--truncate", action="store_true", help="empty the schema first")
    args = ap.parse_args()
    if not args.dsn:
        sys.exit("set DATABASE_URL or pass --dsn")
    try:
        import psycopg
    except ImportError:
        sys.exit("psycopg is not installed — run `pip install 'psycopg[binary]'`")

    seed = json.loads(SEED.read_text())
    with psycopg.connect(args.dsn) as conn, conn.cursor() as cur:
        if args.truncate:
            cur.execute("truncate " + ", ".join(f"godly.{t}" for t in WIPE) + " restart identity cascade")
        counts = load(cur, seed)
        conn.commit()
    for table, n in counts.items():
        print(f"{n:>5}  {table}")
    print(f"{sum(counts.values()):>5}  rows total")


if __name__ == "__main__":
    main()
