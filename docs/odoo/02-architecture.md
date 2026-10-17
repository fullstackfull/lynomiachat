# Odoo Accounting Integration — Architecture

What the integration is made of and why each piece is shaped the way it is. The code references this document
by section.

Stripe stays the payment and subscription authority. Odoo is the accounting **destination**. Nothing here is a
second billing system, a second checkout, or a second payment processor.

---

## 1. The shape of it

```
Stripe                     Lynomia Chat                                   Odoo
──────                     ────────────                                   ────
invoice.paid ─────────▶ Billing::WebhooksController
                        Billing::WebhookHandler
                          BillingWebhookEvent.claim!   (dedup, unchanged)
                          Odoo::EventRecorder          ← ONE INSERT, then return
                            odoo_sync_events
                                 │
                          Odoo::SyncJob (:low, retry: false)
                                 │
                          Odoo::SyncRunner
                            claim (one conditional UPDATE)
                            Odoo::SyncAttempt          ← written BEFORE the write goes out
                                 │
                          Odoo::CustomerResolver ──────────────────────▶ res.partner
                          Odoo::InvoiceExport   ──────────────────────▶ account.move (draft)
    Stripe::Invoice ◀────── re-read the authoritative object            action_post
                          Odoo::PaymentExport   ──────────────────────▶ account.payment.register
                          Odoo::RefundExport    ──────────────────────▶ account.move.reversal
                                 │                                        or out_refund
                            odoo_document_mappings
```

Everything between the webhook and Odoo is durable state an operator can read. That is the point: a sync that
fails has to be legible, and a sync that half-succeeded has to be recoverable.

---

## 2. The destination profile

`odoo_destination_profiles` is one configured destination: where documents go, under whose company and journal,
with which credential, in what state of readiness.

**Why a table and not installation configs.** `Billing::Settings` keeps the Stripe keys as locked
`installation_configs` rows, which is right for one global switch per key. A destination is not that: it
carries a company, two journals, an analytic account, a detected server version, three activation switches and
the evidence that a write actually worked. More importantly, `installation_configs.value` is **not encrypted** —
`locked` only hides the row from the generic config page — and the brief requires the Odoo credential to be
encrypted. So the profile follows `Commerce::Store`: a JSON `credentials` column with `encrypts` on it, and a
validation that refuses to persist without Active Record encryption keys.

**Exclusivity is a database guarantee.** `uniq_enabled_odoo_destination_per_environment` is a partial unique
index on `(source_app, environment) WHERE sync_enabled`. Two enabled destinations would post every invoice
twice, so the database refuses rather than a callback.

**The ten states are derived, never stored** (`CONFIGURATION_FUNNEL`). A stored status is a second source of
truth that drifts from the columns it summarises, and every input is already a column. The funnel is ordered so
the first check that fails names what an operator must do next:

| State | Means | What the operator does |
|---|---|---|
| `not_configured` | no profile row exists | create one |
| `credentials_missing` | profile exists, no API key | paste the key |
| `connection_untested` | key stored, never used | run the connection test |
| `connection_failed` | last test failed | read Diagnostics |
| `scope_incomplete` | company or journals not chosen | choose them |
| `capability_unproven` | no draft has ever been created and read back | run the capability probe |
| `ready_disabled` | everything checks out, sync is off | turn it on |
| `active` | exporting | nothing |
| `error` | enabled but refusing | read `blocked_reason` |

---

## 3. Isolation — the part that matters most

The destination Odoo holds the books of several unrelated businesses. Invoice numbers repeat across them,
customer names repeat, and emails repeat. So:

**A stamp.** `Odoo::SourceStamp` writes one string into Odoo's own `ref` on every record it creates:

```
LYNOMIA_CHAT/live/invoice/in_1A2b3C
```

**And a scope, always.** Odoo puts **no** uniqueness constraint on `account.move.ref` for customer invoices —
the only unique index is on `(name, journal_id)` for posted moves, and the `ref` index is restricted to vendor
bills. So the stamp narrows a search; it does not guarantee the answer. Every lookup therefore adds the
destination scope — company, journal, document type:

```ruby
domain = [['company_id', '=', 3], ['journal_id', '=', 11],
          ['move_type', '=', 'out_invoice'], ['ref', '=', stamp]]
```

**THE COMPANY IS NOT THE BOUNDARY, AND AN EARLIER VERSION OF THIS DOCUMENT SAID IT WAS.** It claimed that
"scope plus stamp cannot match another business's row, because another business's row is in another company."
That is false for this installation. The destination Odoo holds **one** legal company and **several**
unrelated projects run inside it: they share the company id, often the journal, and their customers share
names and emails. Odoo offers no record-level isolation between them either — the only record rule on an
analytic account is company-based, and `company_id` on one is not even required.

So the division of labour is:

| question | answered by | not answered by |
|---|---|---|
| is this record **ours**? | the exact stamp in `ref` | the company, the journal, a customer name, an email, an invoice number |
| where does it get **written**? | the company and journal | — |
| whose **revenue** is it, in Odoo's reports? | the analytic distribution on each revenue line ([08](08-project-attribution.md)) | the stamp, which Odoo's financial reports never read |

`Odoo::SourceStamp#ownership_domain` is the only way to build a lookup, and it raises without a reference —
so a scope-only search, which in one shared company returns every project's documents, cannot be written.

**`allowed_company_ids` on every call.** It is the Odoo context key that decides which company a write lands
in, and its first element is the active one. Passed together with an explicit `journal_id`, which pins
`company_id` through Odoo's own `check_company`.

**A read by id is scoped by nothing.** `search_read` carries the domain; `read` returns whatever that id is in
any company the API user can see — and in a shared Odoo that is usually several. So `Odoo::Accounting#read_move`
checks the row it gets back against the profile and raises `CONFLICT` on a mismatch. In a shared company that
check has two halves: the **destination** (is it in the configured company and journal?) and the **ownership**
(does its `ref` equal the stamp we expect?). Callers that know the stamp pass it, because a move in the right
company and the right journal may still be a sibling project's.

**`res.partner` is the one model whose scope admits `company_id = false`**, deliberately: a partner with no
company is shared across every company in that database, which is how most installations hold their customers.
Refusing shared partners would leave the integration unable to find any of them. Partners this integration
*creates* carry our company explicitly, so they are invisible to the owner's other businesses.

---

## 4. Customer identity

`odoo_customer_mappings` closes the chain Account → BillingSubscription → Stripe customer → `res.partner`.

Nothing searches by email or name. Three unique indexes make a merge impossible rather than unlikely:

| Index | Prevents |
|---|---|
| `(profile, account_id)` | two partners for one account, splitting its ledger |
| `(profile, odoo_partner_id)` | **two accounts on one partner** — the merge the brief forbids |
| `(profile, stripe_customer_id)` | our side disagreeing with Stripe about who pays |

A conflict is never resolved by picking one. `Odoo::CustomerResolver` clears the partner id, marks the mapping
`needs_review` with the reason, and the Customers tab shows it.

---

## 5. Documents

`odoo_document_mappings` is one row per Stripe money object and the Odoo document it became, keyed on the
brief's own idempotency key:

```
LYNOMIA_CHAT:live:stripe:customer_invoice:in_1A2b3C:profile_7
```

with a unique index on it. **Odoo offers no server-side idempotency of any kind** — there is no such parameter
on `create()` and no such header on either RPC endpoint — so this index is the whole mechanism.

One Stripe invoice becomes several documents over its life (the invoice, the payment, possibly a credit note),
so `document_kind` is part of the key: registering a payment can never be mistaken for re-creating the invoice.

**The total comparison is the gate.** This integration writes into somebody else's chart of accounts, with
their fiscal positions, their tax mapping and their rounding. It cannot predict what Odoo will compute, so it
does not try: it creates the draft, asks Odoo for the total, and compares that against Stripe's. A draft whose
total disagrees with Stripe stays a draft marked `needs_review`. Nothing posts on a number the integration
cannot account for.

**`payment_state` is read, never written.** It is a stored computed field with no inverse, derived from
reconciliation rows. Odoo's ORM would most likely accept a write and then overwrite it at the next recompute,
so the ledger would claim to be paid and then stop.

---

## 6. The queue

`odoo_sync_events` holds the work; `odoo_sync_attempts` holds what each attempt did.

**The webhook's whole contribution is an insert.** Stripe expects an answer in milliseconds and retries
anything that is not a 2xx, so an endpoint that waited on the owner's Odoo would turn one slow accounting
server into a storm of redeliveries.

**The attempt is recorded before the write goes out.** If it were recorded after, a worker killed mid-write
would leave no evidence the write was sent — and a crash mid-write is then indistinguishable from a write that
never happened, while the correct recovery for the two is opposite:

| Outcome | Means | Recovery |
|---|---|---|
| `not_sent` | DNS, refused connection, connect timeout — the server never saw it | repeat it |
| `unknown_outcome` | it went out, no readable answer — Odoo **may have acted** | search Odoo for the stamp |

**Seven states.** `pending → processing → synchronized`, with `retrying` (self-healing, a `run_after` in the
future), `failed` (attempts exhausted or a permanent error), `blocked` (refusing to run — not an error, the
answer is "not yet") and `needs_review` (Odoo and Lynomia disagree about something only a person can settle).
`Odoo::SyncState::UNHEALTHY` is `failed, blocked, needs_review`, and the integers 4, 5, 6 are what the Errors
screen's partial index selects — a spec compares the two.

**`Odoo::SyncJob` is `retry: false` on `:low`.** The retry schedule lives in `run_after`, where an operator can
read it and bring it forward. A second, invisible Sidekiq schedule would make that column a lie.

**The claim is one conditional UPDATE** with the state in its WHERE clause. Two workers racing on one row:
exactly one update affects a row and the loser returns. No lock, no Redis — the database decides, the same
mechanism as `BillingWebhookEvent`'s unique index.
