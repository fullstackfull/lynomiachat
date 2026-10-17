# Limitations, and why each one is deliberate

Everything this integration refuses to do, with the reason. Each of these is a decision, not an unfinished
edge: in every case the alternative was to guess at an accounting treatment on behalf of a ledger this
integration does not own.

---

## 1. A partial refund's credit note is not reconciled automatically

**What happens:** a partial Stripe refund creates and posts an `out_refund` move for the credited amount,
linked to the original invoice through `reversed_entry_id` so Odoo's own UI shows the relationship. The
document mapping is then left `needs_review` with the reason
`partial_credit_note_awaiting_reconciliation`, and the operator reconciles it in Odoo.

**Why:** reconciling a partial credit note against an invoice's receivable line is what decides whether the
invoice reads `partial` or `paid`. It needs a judgement about which journal items to match, and a wrong guess
silently misstates a ledger. A full refund has no such ambiguity, so it is fully automatic through
`account.move.reversal`.

## 2. Tax is not mapped

**What happens:** invoice lines are sent at Stripe's own per-line amounts with no `tax_ids`, so Odoo computes
whatever its own configuration says. The draft's total is then compared against Stripe's, and a mismatch
leaves the invoice a draft marked `total_mismatch_with_stripe`.

**Why:** the destination's fiscal positions, tax mapping and rounding are the customer's, and no amount of
guessing from Stripe's side can predict them. If your Stripe invoices carry tax, configure the matching tax on
the Odoo journal or fiscal position; until Odoo's computed total matches Stripe's, nothing posts. That is the
intended behaviour — a visible, blocking, actionable failure instead of an invoice that is quietly short.

## 3. Stripe's processing fees are not exported

**Why:** a Stripe fee lives on the balance transaction, not on the invoice, and it is an **expense** rather
than negative revenue. Booking it automatically would misclassify it. The brief asks for exactly this
restraint. Record fees in Odoo the way your accountant already records bank charges.

## 4. A dispute (chargeback) writes nothing

**What happens:** `charge.dispute.created` is recorded as a `needs_review` sync event. Nothing goes to Odoo.

**Why:** a chargeback's treatment differs by jurisdiction and by the owner's own policy — a provision, a
write-off, a bank fee, or all three. Guessing one would misstate the ledger.

## 5. A zero-amount invoice is not exported

**What happens:** the mapping is kept, marked `blocked` with `zero_amount_not_exported`, and listed in the
Invoices tab so an operator can see that it was seen.

**Why:** Stripe issues zero-amount invoices for trials and fully discounted periods. There is no revenue to
record. The brief: *"A trial or manual grant must not generate fabricated revenue."*

## 6. A second partial payment on one invoice needs a person

**What happens:** the payment document is keyed on the invoice, so a later `invoice.paid` reporting a higher
`amount_paid` lands on the same key and is marked `needs_review` with
`amount_paid_changed_from_X_to_Y`.

**Why:** keying on the invoice rather than the charge is what makes the integration robust against Stripe
moving the invoice→payment link, which it has done more than once. The cost is that genuinely more money on one
invoice cannot be told apart from a redelivery without a human. Stripe subscriptions rarely pay one invoice in
instalments, so the trade is worth it — and the failure is visible rather than silent.

## 7. Merchant commerce revenue is never exported

Not a limitation so much as the boundary: `commerce_carts.visible_total` and `commerce_contact_metrics.spend`
are a **tenant's** sales to **their** customers. Lynomia is not a party to them. The integration reads no
`commerce_*` table at all, and `spec/security/odoo_accounting_boundary_spec.rb` fails if a future change adds
one.

## 8. Super Admin is English only

The page bodies on this surface are English, which is the convention of every other Super Admin page in this
codebase (`spec/.../operations` views contain no `t(` calls, and `ar.yml` carries no `super_admin` tree). What
**does** go through i18n — the flash messages and the model validation messages — has a full Arabic sibling in
`config/locales/odoo.ar.yml`. Odoo's model, field and method names are machine-readable identifiers and are
never translated in either locale.

## 9. One destination at a time

Several destination rows may exist, but only one may be enabled per app and environment — enforced by a partial
unique index, because two enabled destinations would post every invoice twice. In production the integration
looks for the `live` destination; a `test` destination configured in production is never used, which is
deliberate.

## 10. Amounts

`Odoo::Money` handles Stripe's zero-decimal (JPY and fifteen others) and three-decimal (KWD, BHD, JOD, OMR,
TND) currencies from Stripe's own published lists, in `BigDecimal`. A currency on neither list has two
decimals. The comparison tolerance is one minor unit, scaled per currency.

## 11. One partner per project, not one per customer

`res.partner` has no analytic distribution — attribution is a journal-item concept — so a partner cannot be
"a Lynomia Chat partner" in Odoo's own data model. It is ours because its `ref` carries our stamp. The
consequence: if a sibling project in the same company invoices the same real customer, that customer will
exist twice in the company, once per project. That is **duplication, not leakage**, and the alternative is
worse: matching an existing partner by name or email would merge a sibling project's customer ledger with
ours, which is exactly what requirement 11 forbids. Merging the duplicates is an accounting decision for a
person, in Odoo.

## 12. An analytic tax line inflates this project's analytic total

When a sales tax in the destination carries Odoo's `analytic` flag ("Include in Analytic Cost"), Odoo copies
the base line's distribution onto the **tax** line itself. The project's analytic total then includes the tax
as well as the revenue. This integration does not set that, cannot prevent it, and does not refuse the
document for it: an externally written tax-line distribution does not even survive, because
`analytic_distribution` is part of the key Odoo matches tax lines on, so a hand-edited tax line is deleted and
re-added with Odoo's own value. The verification **reports** it (`tax_lines_carry_attribution`) and the
Diagnostics page shows it. Whether a sales tax should be analytic is a configuration decision in the owner's
own Odoo.

## 13. The dedicated-income-account fallback is a narrower guarantee

`attribution_mode = income_account` exists so that an Odoo which cannot do analytic accounting **blocks**
rather than exporting unattributed revenue. It segregates this project's revenue onto its own line in the
**general** ledger, which a profit-and-loss report separates by account. It does **not** give analytic
reporting: no `account.analytic.line` rows are produced, so Odoo's analytic P&L, budgets and analytic
dashboards will not see this project at all. And exclusivity of that account to this project is the operator's
assertion — this integration validates that the account exists, is usable by the configured company and is an
**income** account, and that every revenue line it writes carries it. It cannot validate that nothing else in
the company posts to the same account. Prefer the analytic mode wherever the server supports it.

## 14. A reversal Odoo auto-posted without attribution is reported, not corrected

`reverse_moves` copies the source invoice's analytic distribution, because the field is `copy=True`. If it
somehow does not, and the reversal is still a **draft**, this integration writes the distribution onto the
reversal's revenue lines. If Odoo already auto-posted it — which it does for a reversal dated in the future,
with `auto_post` `at_date` — the credit note is left as it is and the mapping goes to `needs_review`. A posted
journal item is a legal record: it is reversed, never edited. Correcting it is an accounting decision for a
person.

## 15. Two Odoo preconditions this integration cannot check for you

- **`analytic.project_plan`** (Odoo 17 and later). Posting any journal item that carries an analytic
  distribution requires this system parameter to name a valid root analytic plan, or Odoo raises a `UserError`.
  Reading `ir.config_parameter` usually needs rights the integration's API user does not have, so no probe is
  attempted: the go-live sequence in [06-runbook.md](06-runbook.md) has the operator confirm it, and the first
  invoice posted by hand would surface it anyway.
- **External API availability on Odoo Online.** Odoo's own documentation states that External API access is
  not available on the One App Free and Standard plans. A destination on one of those plans cannot be reached
  at all, and the connection test will say so at the `authenticate` stage.
