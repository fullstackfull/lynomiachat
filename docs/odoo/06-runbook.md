# Odoo Accounting — operator runbook

Everything an operator does, in the order they do it. Nothing here requires a deploy, a console or a developer.

Super Admin → **Odoo Accounting** (the lower operator block in the sidebar, beside Operations).

---

## A. Before you start: what to prepare in Odoo

1. **A dedicated user.** Create one rather than reusing a person's login: it keeps the audit trail in Odoo
   readable and lets you revoke access without locking anyone out. Give it Invoicing (or Accounting) rights —
   posting requires the `account.group_account_invoice` group, and the capability probe will tell you if it is
   missing.
2. **An API key** for that user: *Preferences → Account Security → New API Key*, scope `rpc`. The value is
   shown **once**. A manually created key lasts at most three months, so put its expiry in your calendar —
   see §G.
   If the user has two-factor authentication enabled, an API key is the only way it can be used over RPC.
3. **Write down four ids**, from *Accounting → Configuration*:
   - the **company** id (`res.company`) these books belong to;
   - the **sales journal** id (`account.journal`, type `sale`) — the one Lynomia Chat invoices should land in,
     which should be its own journal and not shared with another business;
   - a **bank or cash journal** id for registering payments;
   - optionally an **analytic account** id, if you track this project analytically.
4. **If you are on Odoo Online:** external API access is restricted to Custom plans, and the user needs a local
   password set before it can authenticate at all.

> **Use a test database first if you have one.** Set the destination's environment to `test`, and nothing
> production touches it: in production the integration only ever looks for the `live` destination.

## B. Configure the destination

**Connection & Settings** tab.

1. Name it something an operator will recognise in an audit entry (`Lynomia Chat — live`).
2. Environment: `live` for the real books, `test` for a sandbox.
3. Odoo URL — **https only**. The form refuses plain HTTP and refuses a URL carrying a username or password.
4. Database, Odoo user login, API key. Save.
5. Fill in the four ids from §A.3. Leave **Post invoices automatically** and **Register payments
   automatically** switched **off**. They are off by default and you should leave them off until §D.

Leaving the API key field empty on a later edit keeps the stored key — you never have to re-paste it to change
a journal.

## C. Prove it works

**Diagnostics** tab. Read [04-diagnostics.md](04-diagnostics.md) once; it explains what each step does and does
not prove.

1. **Run connection test.** It should report the Odoo version and the transport it chose. If it fails, the page
   names the stage (`version` means unreachable or wrong URL; `authenticate` means the key, database or user is
   wrong).
2. **Run capability probe.** Six probes, each reported separately. **Every one must be green or skipped**
   before you go further. The one to look hardest at is `sale_journal`: if it reports `journal_company`, the
   journal id you entered belongs to a **different company** — stop and find the right one, because that is
   exactly the isolation failure this integration exists to prevent.
3. The probe creates one draft invoice in your journal, reads it back, and deletes it. A draft has no number,
   so nothing is left behind and no sequence gap is created.

## D. Go live, in this order

The order matters. Each step is reversible until the one after it.

1. **Overview → Turn synchronisation on.** From now on, new Stripe invoices are exported as **drafts**. Posting
   is still off.
2. **Wait for two or three real invoices.** Check the **Invoices** tab: each should show an Odoo id, state
   `draft`, and sync state `synchronized`. Open one in Odoo and check the partner, the lines, the currency and
   the total against the Stripe invoice.
3. **Post one yourself in Odoo.** This is the real test of posting, and there is no way to simulate it —
   see [04-diagnostics.md](04-diagnostics.md) §3. If it posts cleanly, your journal and rights are right.
4. **Settings → Post invoices automatically → Save.** New invoices now post themselves. A posted invoice takes
   a number from your journal sequence and can only be reversed, not deleted.
5. **Wait for one posted invoice to look right.** Then **Register payments automatically**.
6. **Schedule the sweep.** The queue is drained by `Odoo::SyncSweepJob`, which is deliberately **not**
   registered as a recurring job by the deploy — a cron entry that drained a queue nobody had switched on would
   be exactly the "synchronise on deployment" the brief forbids. Add it once you are live, the same way the
   installation's other sweeps are scheduled:
   ```
   Odoo::SyncSweepJob.set(cron: '*/5 * * * *')     # or your scheduler's equivalent
   ```
   Live synchronisation works without it — a webhook enqueues its own job. The sweep is what picks up a
   **retry** whose backoff has expired and releases a claim a dead worker left behind.

## E. The daily check

**Overview** answers it: is it on, is anything stuck, when did it last export anything.

**Errors** is the only page that matters when something is wrong. It lists `failed`, `blocked` and
`needs_review` only — work that is `retrying` is self-healing and deliberately absent, so the page is never
noise.

| Reading | Means | What to do |
|---|---|---|
| `blocked` / `destination_not_enabled` | synchronisation is off | turn it on, or leave it |
| `blocked` / `zero_amount_not_exported` | a trial or 100%-discounted invoice | nothing; it is correct |
| `blocked` / `unknown_stripe_customer` | a Stripe customer this installation never created | check whether it belongs to another project |
| `blocked` / `payment_registration_disabled` | you have not enabled it yet | §D.6, or leave it |
| `needs_review` / `total_mismatch_with_stripe` | Odoo computed a different total | usually tax ([05-limitations.md](05-limitations.md) §2) |
| `needs_review` / `partial_credit_note_awaiting_reconciliation` | the credit note exists and is posted | reconcile it in Odoo |
| `needs_review` / `payment_may_already_exist` | Odoo already shows the invoice paid | check whether a payment is there, then retry or leave it |
| `needs_review` / `partner_claimed_by_another_account` | two Lynomia accounts resolved to one Odoo partner | decide which is right; fix the partner in Odoo |
| `needs_review` / `dispute_requires_manual_accounting` | a chargeback | book it your way |
| `failed` / `AUTH_INVALID` | the API key expired or was revoked | §G |
| `failed` / `PERMISSION_DENIED` | the Odoo user lost a right | re-grant it, then **Retry now** |
| `failed` / `SERVER_ERROR` after 5 attempts | Odoo was down longer than the backoff | fix Odoo, then **Retry now** |

**Retry now** brings one row's next attempt forward. It does not reset the attempt count: an operator retrying
something five times should still be able to see that it has been tried five times.

A failure also raises an `accounting_sync` signal in the **Operations** console, so it appears where you
already look.

## F. Importing past invoices

**Historical import** tab. Two steps, and the first writes nothing.

1. Pick a window and press **Preview**. It reads your Stripe invoices and reports what an import *would* do:
   how many, in which currencies, how many are already exported, how many are zero-amount, how many have no
   matching customer. If the window holds more invoices than one preview reads, it says so — narrow it.
2. Press **Queue N invoices for import**. That enqueues them; it does not import inside the request.

Running it twice over the same window is harmless: it reuses the same idempotency keys, so the second run
queues nothing. An import covering a period live synchronisation already handled produces no second document.

Nothing imports on deploy, and there is no code path by which it could — only this form queues a backfill.

## G. Rotating the API key

Odoo's manually created keys last at most three months, so this is routine rather than an incident.

1. Create a new key in Odoo for the same user (do not revoke the old one yet).
2. Settings → paste the new key → Save.
3. Diagnostics → **Run connection test**. It should pass.
4. Revoke the old key in Odoo.

If a key is revoked before it is replaced, work fails with `AUTH_INVALID` and **stays queued** — fix the key
and press **Retry now**. Nothing is lost.

## H. Turning it off

**Overview → Turn synchronisation off.** Immediate, never gated, and the queue keeps its rows: they sit
`blocked` until it is switched back on. Clearing the API key (Settings) stops it just as surely.

Neither touches anything already in Odoo. A posted invoice you want gone is **reversed in Odoo**, not deleted —
that is Odoo's rule, not ours.

## I. Deployment

1. `bundle exec rails db:migrate` — five additive tables (`odoo_destination_profiles`,
   `odoo_customer_mappings`, `odoo_document_mappings`, `odoo_sync_events`, `odoo_sync_attempts`). No existing
   table is altered. All five roll back cleanly.
2. **Active Record encryption keys must be set** — `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`,
   `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`. Without them
   a destination **cannot be saved at all**, by design: the credential is never stored in plaintext.
3. Add these Stripe event types to the webhook endpoint in your Stripe dashboard: `invoice.paid`,
   `invoice.finalized`, `invoice.payment_failed`, `invoice.voided`, `invoice.marked_uncollectible`,
   `charge.refunded`, `charge.dispute.created`. The endpoint is unchanged
   (`POST /billing/webhooks/stripe`); it simply accepts more types now.
4. Nothing else. No destination exists until an operator creates one, and an installation with no destination
   behaves exactly as it did before this feature shipped — including taking Stripe webhooks.

### Rollback

| Situation | Action |
|---|---|
| Exports look wrong | **Turn synchronisation off.** Nothing further is written. Queued rows wait. |
| Something was posted in error | Reverse it **in Odoo**. Do not delete a posted move. |
| The code needs to come out | Turn synchronisation off, then deploy the previous revision. The five tables are inert — nothing else reads them. |
| The tables need to come out | `rails db:rollback STEP=5`, after the previous revision is deployed. Mappings are lost, so a later re-install would re-export; prefer leaving the tables in place. |

## J. Go-live checklist

- [ ] A dedicated Odoo user with Invoicing/Accounting rights
- [ ] An API key for it, with its expiry diarised
- [ ] Encryption keys set in the environment
- [ ] Company, sales journal, payment journal ids confirmed in Odoo
- [ ] The sales journal is Lynomia Chat's own, not shared with another business
- [ ] Connection test green
- [ ] Capability probe green, with `sale_journal` reporting the right company
- [ ] Synchronisation on, posting off
- [ ] Two or three real invoices checked in Odoo against Stripe
- [ ] One invoice posted by hand, successfully
- [ ] Posting switched on; one posted invoice checked
- [ ] Payment registration switched on; one payment checked
- [ ] The sweep scheduled
- [ ] Errors tab read once and understood
