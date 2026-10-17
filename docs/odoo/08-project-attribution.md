# 08 — Project attribution inside one shared Odoo company

This document records a **correction to the architecture of this integration**, not an addition to it. The
original design rested on an assumption about the destination Odoo that turned out to be wrong, and the wrong
assumption was load-bearing: it was what the isolation guarantee was built on.

---

## 1. What was assumed, and what is actually true

| | assumed | actually true |
|---|---|---|
| Odoo companies | one company per business project | **ONE legal company**, shared |
| projects inside it | one | **several**, unrelated to each other |
| what `company_id` tells you | whose record it is | only **where** it is written |
| isolation mechanism | the company id | the **source stamp** (identity) + an **analytic account** (reporting) |

The consequence of the wrong assumption was specific rather than theoretical. A lookup scoped by company and
journal would have matched a sibling project's invoice, because a sibling project's invoice *is* in the same
company and often the same journal, and its customers share names and billing emails with ours. And revenue
written without an analytic distribution would have been indistinguishable, in the owner's own profit-and-loss
report, from every other project's revenue in that company — because Odoo's financial reports do not read
`ref`.

**No separate Odoo company is created, and none is required.** The operator enters the id of the company they
already use.

---

## 2. Two questions, two mechanisms

Conflating these is how a shared ledger gets mixed, so the code keeps them apart by construction:

| question | mechanism | where |
|---|---|---|
| Is this record **ours**? | the stamp `LYNOMIA_CHAT/live/invoice/in_1A2b3C` in Odoo's own `ref`, matched with `=` and never with `like` | `Odoo::SourceStamp#ownership_domain` |
| Whose **revenue** is it, as Odoo reports it? | an analytic distribution of 100% to this project's analytic account on every revenue line | `Odoo::Attribution` |

`#ownership_domain` **raises without a reference**. That is the structural half of requirement 11: there is no
API on this class for a scope-only search, so a future call site cannot accidentally write one.

A read **by id** is checked on both axes: the destination (company and journal) and, where the caller knows
it, the stamp. `Odoo::Accounting#read_move(id, reference:)` raises `CONFLICT/move_stamp_mismatch` on a move
that is in the right company and the right journal but is not ours.

---

## 3. Where the attribution goes, and where it must not

Odoo will **not** stop us getting this wrong. `_compute_analytic_distribution` assigns only for
`display_type == 'product'` lines and otherwise leaves whatever is stored alone; there is no `@api.constrains`
and no SQL constraint on `analytic_distribution` anywhere on `account.move.line`. So this code is the only
guard.

| line | `display_type` | attribution | why |
|---|---|---|---|
| the revenue | `product` | **100% to this project** | this is the income being recognised |
| the receivable | `payment_term` | **never** | posting one here creates a real `account.analytic.line` with the **opposite sign**, silently cancelling the revenue line's attribution. Odoo never puts one here itself — the values `_compute_needed_terms` builds contain no analytic key at all |
| the tax | `tax` | **not ours to set** | Odoo fills it from the base line whenever the tax carries the `analytic` flag ("Include in Analytic Cost"), and sets it to false otherwise. An externally written one does not even survive: `analytic_distribution` is part of the key Odoo matches tax lines on, so a hand-edited tax line is deleted and re-added with Odoo's own value |

This integration authors only `invoice_line_ids`, which Odoo computes as `product` lines, and never passes an
`account_id` that would convert one into a payment term. So the rule holds structurally as well as by
checking.

**The value's shape matters.** Odoo's own sanitiser divides the percentage, so a string value raises
server-side; and it casts the key with `int()`, so a non-numeric key blows up at posting. The payload is
therefore always `{"41": 100.0}` — a numeric string key, a numeric value. A comma-joined key (`"41,88"`) is
valid only from Odoo 17 and means one allocation charged to one account **per plan**; this integration never
writes one, but it reads one correctly, because our account inside a composite key still attributes the line
to us while a *separate* entry naming other accounts is a genuine split of our revenue.

---

## 4. Sending is not landing

Every exported document is **read back** and checked, and a document whose attribution did not land is handed
to a person rather than posted. Three things make this necessary rather than belt-and-braces:

1. Odoo **computes** `analytic_distribution` on lines where none was supplied.
2. An `account.analytic.distribution.model` record in the destination database can **replace** the one we
   sent: the compute depends on `account_id`, `partner_id` and `product_id` and the model's dict wins.
3. A mistyped analytic account id is a real possibility, and in one shared company it would attribute our
   revenue to a sibling project — whose analytic accounts our API user can read and write, because Odoo gives
   projects inside one company no record-level isolation at all.

So the invoice sequence gained a fifth step:

```
1 claim the mapping            the unique index decides whether this is ours to do
2 recover, if a write may have happened   search Odoo by our own stamp
3 create the DRAFT
4 read it back, COMPARE TOTALS            against Stripe's own total
5 read its LINES, VERIFY ATTRIBUTION      <-- new
6 post, only if posting is enabled AND both gates passed
```

**And one more check, after posting.** A stored distribution is still not an attributed ledger: if it names an
analytic account that has since been archived or deleted, Odoo stores it, posts the invoice, creates **no**
`account.analytic.line` and raises nothing — the revenue is posted attributed to nobody. So after a successful
post the analytic ledger is read (`Odoo::Accounting#read_analytic_lines`) and a document with none is marked
`analytic_lines_not_created`. The invoice stays posted, because a posted document is reversed and never
withdrawn; what changes is that the integration does not call it synchronized, and the reason tells an operator
what to fix. Only existence is asked for, not which column holds the account: each root plan owns a distinct
column on the analytic line (`account_id` for the plan named by the `analytic.project_plan` parameter,
`x_plan<id>_id` for the rest), and the distribution has already been verified to name this project and nothing
else. The probe also reads the configured analytic account with `active_test: false`, so an **archived**
account is found and refused by name (`analytic_account_archived`) instead of being reported as missing.

`odoo_document_mappings.attribution_verified_at` is stamped only on a pass, and a partial index lists exactly
the documents that reached Odoo without it. The mapping also records `attribution_mode` and
`odoo_analytic_account_id` **per document**, so an operator who later repoints the profile at a different
analytic account does not silently rewrite the history of everything already exported.

### Credit notes

Both cases end up attributed to the same project as the invoice they credit, by different routes:

- a **partial** credit note's lines are authored here, so they carry the attribution the way an invoice's do,
  and it is verified **before** the credit note is posted — an unattributed posted document cannot be
  corrected;
- a **full reversal**'s lines are authored by Odoo, which copies the source line's distribution because the
  mixin field is `copy=True`. It is still read back; if it did not come across and the reversal is still a
  **draft**, the distribution is written onto its revenue lines. A reversal Odoo already auto-posted is
  reported rather than rewritten, because a posted journal item is a legal record that is reversed, never
  edited.

A reversal is tied to our invoice by **`reversed_entry_id`**, not by its company: Odoo writes its own
"Reversal of: …" into the credit note's `ref`, so our stamp is not there to match exactly.

### This integration writes no attribution on a payment — but Odoo may

A customer payment's journal items are the **receivable** and the bank or outstanding-receipts account: the
customer's debt being settled and the cash arriving. Neither is this project's income — the income was
recognised on the invoice, which is where the distribution sits. Attributing the receivable as well would book
the same money into the project's analytic accounts twice, with the opposite sign.

**And Odoo can still stamp one, which this integration cannot prevent.** `account.payment` and
`account.payment.register` contain no analytic code at all — but `_compute_analytic_distribution` lives on
`account.move.line`, and its guard is `display_type == 'product'` **OR NOT** `move.is_invoice(...)`. A
payment's move is created with `move_type: 'entry'`, so `is_invoice?` is false, the **second** disjunct fires,
and the compute runs for **every** line of a payment move, consulting
`account.analytic.distribution.model`. A destination whose distribution model matches the receivable or
outstanding account prefix will therefore attribute the payment's receivable line by itself, understating this
project's analytic total.

That is the owner's own configuration, it is not reachable from here, and refusing every payment over it would
be noise rather than safety. So it is **reported rather than guarded**: `attribution_setup` counts the
distribution models in the company, and [05-limitations.md](05-limitations.md) §17 says where to look. This is
a decision, recorded as one — not an oversight.

---

## 5. Activation is blocked until attribution is proven

The capability probe gained two checks and the funnel gained a state:

| probe | what it establishes |
|---|---|
| `attribution_setup` | this server **has** `analytic_distribution` on `account.move.line`; the configured analytic account exists, is **active** and is usable by this company (`company_id` false = shared, which is fine; another company's is not); which plan it belongs to; and **how many `account.analytic.distribution.model` rules** in the company could add or replace an attribution we did not write |
| `attribution` | the attribution we **sent** came back on the draft's revenue line at 100%, nowhere it should not be, and not pointing at another project |

`attribution` **never reports `skipped`**, and `Odoo::DestinationProfile#capability_proven?` requires it **by
name** — not merely counted in the proof's own `ok`, because `probe_capability` treats a skipped probe as
passing. So a stored proof that predates this probe, or in which it was skipped, is not proof. Without it
`Odoo::AdminSettings#enable!` raises and synchronisation cannot start.

`attribution_incomplete` sits between `scope_incomplete` and `capability_unproven` in the funnel, because an
operator who has not yet said which project inside the shared company this destination is for cannot usefully
run a probe that checks it.

### Posting asks Odoo to validate analytics

Odoo's own mandatory-100%-distribution check sits inside `if not self.env.context.get('validate_analytic')`,
and the **only** caller that sets it is the web UI's Confirm button. So `action_post` over the External API
would post an invoice that breaches a mandatory analytic plan **silently**. `Odoo::Accounting#post_move`
passes the key, so a destination whose analytic plans demand more than this integration knows how to supply
refuses the posting and leaves the draft for a person.

### The configured alternative, for an Odoo that cannot do this

If `analytic_distribution` is not available, the answer is **not** to export unattributed revenue. The
operator configures `attribution_mode = income_account` with a **dedicated income account**, the probe
validates that the account exists, is usable by the company and has an **income** `account_type` — a
receivable or payable account would be accepted by `create` and then silently turn every revenue line into a
payment term — and every revenue line carries it. It segregates this project's revenue on its own line in the
**general** ledger rather than analytically, which is a real but narrower guarantee; it is recorded as such in
[05-limitations.md](05-limitations.md). Neither mode can be left unconfigured, and neither is skipped.

---

## 6. Two queue fixes that shipped with this correction

**Every recorded row is enqueued.** One `charge.refunded` notification carries every refund the charge has
ever had, so `Odoo::EventRecorder` returns one row per refund — and `Billing::WebhookHandler` enqueued only
`events.first`. A customer refunded twice had the second refund **recorded and never exported**: its row sat
`pending` with nothing scheduled to pick it up.

**The sweep is scheduled.** `Odoo::SyncSweepJob` was deliberately left out of `config/schedule.yml` so that
nothing could begin synchronising on deployment. The effect was that the retry schedule became a record of
intent rather than something that happens: `Odoo::SyncRunner` wrote `run_after` on a transient failure and
nothing ever came back to read it, and a claim abandoned by a dead worker stayed `processing` for ever. It now
runs every five minutes on `scheduled_jobs`, and the deployment concern it was protecting against does not
arise:

- it **creates no work** — rows exist only because `Odoo::EventRecorder` recorded one, and that returns `[]`
  unless `Odoo::DestinationProfile.active` finds an **enabled** destination, so on a fresh installation its
  query matches nothing on every run;
- it **decides nothing** — each row it finds goes to `Odoo::SyncJob`, and `Odoo::SyncRunner` blocks the row
  with `destination_not_enabled` if synchronisation has since been switched off.

---

## 7. The evidence

`spec/security/odoo_project_isolation_spec.rb` runs the integration against a fake Odoo
(`spec/support/odoo_shared_company.rb`) holding **two projects' rows in one company**: same company id, same
journal, a partner with the same name and email as one of ours, and an invoice number that collides. The fake
is deliberately permissive — it answers a `search_read` by applying the domain, and returns only the fields
that were requested, the way the real server does — so anything that leaks, leaks in the spec.

It proves, among others:

- a sibling project's invoice is **not** found although company, journal and move type all match;
- a sibling project's partner is **not** found by the name or email it shares with ours, and neither `name`
  nor `email` ever appears as a domain clause;
- `ownership_domain` **raises** without a stamp;
- a read by id lands on a sibling's move → `CONFLICT/move_stamp_mismatch`;
- an authored line carries `{"41": 100.0}` with a string key and a numeric value;
- a revenue line that came back on another project's analytic account → refused, document not posted;
- our account on a `payment_term` line → refused;
- an analytic **tax** line Odoo filled itself → accepted, and reported;
- a destination whose attribution probe has not passed, or that names no analytic account, **cannot be
  enabled**.

What remains **BLOCKED** without a real Odoo server is listed in
[07-blocked-tests.md](07-blocked-tests.md) — including whether `validate_analytic: true` surfaces as an error
to an API caller, and the Odoo 17+ requirement that the `analytic.project_plan` system parameter name a valid
root plan before any line carrying a distribution can post.
