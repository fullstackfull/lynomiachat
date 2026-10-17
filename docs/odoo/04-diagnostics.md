# Diagnostics: what is proven, and what is not

Super Admin → Odoo Accounting → **Diagnostics**.

The brief's hardest requirement: *"A successful login or 'Test Connection' is NOT sufficient proof that invoice
creation and posting work."* It is not, and this page exists to say so rather than imply otherwise.

---

## Step 1 — Connection test

Reads the server version **without credentials**, then makes one authenticated read (`fields_get` on
`account.move`).

**Proves:** the server is reachable over https, which Odoo it is, which transport to use, that the API key
authenticates, and that the user can see `account.move`.

**Proves nothing about:** the journal, the company, posting rights, tax configuration, or whether this
server's chart of accounts accepts the line shape the adapter sends.

Stored in `last_connection_result` as a boolean, a version string, a transport name, and on failure a code and
reason from our own vocabulary. Never a credential, never Odoo's traceback.

## Step 2 — Capability probe

Seven independent probes. Each is reported separately, because an operator fixing a misconfiguration wants the
whole list rather than the first line of it.

| Probe | Asks | Fails when |
|---|---|---|
| `model_shape` | `fields_get` on `account.move` for seven fields | a field the adapter writes is absent |
| `company` | the configured `res.company` exists | the id is wrong |
| `sale_journal` | the journal is `type = sale` **and in the configured company** | either is wrong |
| `payment_journal` | the journal is bank, cash or credit, in the same company | either is wrong |
| `attribution_setup` | this server **has** `analytic_distribution` on `account.move.line`, and the configured analytic account exists and is usable by this company — or, in the fallback mode, that the income account exists and is an **income** account | attribution is unconfigured, unsupported, or points somewhere unusable |
| `draft_create` | **one draft invoice created in the configured journal, read back, and deleted** | the write is refused |
| `attribution` | whether the attribution we **sent** came back on that draft's revenue line, at 100%, to this project's account and nowhere it should not be | it did not land, landed in part, or landed on another project's account |

**`attribution` is the probe that matters most, and it is never skipped.** The destination company hosts
several unrelated projects, so an invoice that posts perfectly but carries no analytic distribution has put
this project's revenue somewhere the owner's own reports cannot separate.
`Odoo::DestinationProfile#capability_proven?` requires this probe **by name** — not merely counted in the
proof's `ok`, because a skipped probe counts as passing — so synchronisation cannot be switched on until it
has passed. See [08-project-attribution.md](08-project-attribution.md).

`sale_journal` → `journal_company` still matters: a journal in another company would write the invoice into
the wrong legal entity. It is not, however, what separates this project from its siblings — nothing about a
company is.

**One write, read twice.** `draft_create` and `attribution` share a single draft: the round trip is memoised
including its failure, so a server that refuses the write is not written to twice and both probes report on
the same document.

`model_shape` also reports the `payment_state` selection this server actually has. Odoo 18 added `blocked` to
it, so that selection **is** the version branch — read from the server rather than inferred from a number.

**The one write, and its undoing.** The only honest proof that invoice creation works is to create an invoice.
So the probe creates a **draft**, reads it back to confirm which company and journal it landed in, and deletes
it. A draft has no sequence number — Odoo assigns the number when the move leaves draft — so deleting one
leaves no accounting trace and no gap in your numbering. The probe uses no partner (`partner_id` is not
required to create an `account.move`; Odoo enforces it at posting time), so it does not invent a customer in
your database either.

## Step 3 — Posting is unproven, and is not claimed to be

Posting gives an invoice a permanent number from your journal's sequence and cannot be undone — a posted
invoice is reversed, never deleted. There is therefore **no way to probe posting without leaving a real
document in your books**, so this integration does not try and does not pretend the probe covers it.
`probe_capability` reports `posting: 'unproven'` and the page says it in those words.

What that means in practice is the go-live sequence in [06-runbook.md](06-runbook.md): leave **Post invoices
automatically** off, export a few real invoices as drafts, post one yourself in Odoo, and only then turn it on.
The first invoice that posts successfully is the real test. Until then every export is a draft, which is
reversible by deleting it.

## What an operator sees, and what they do

| Reading | Meaning | Next step |
|---|---|---|
| connection test never run | nothing has been tried | run it |
| connection failed at `version` | wrong URL, wrong network, or https refused | check the URL and the firewall |
| connection failed at `authenticate` | key, database or user is wrong | re-create the key in Odoo |
| `sale_journal` → `journal_type` | the id names something that is not a sales journal | find the right id |
| `sale_journal` → `journal_company` | the journal belongs to a company other than the one configured | **stop**; the invoice would be written into the wrong legal entity |
| `attribution_setup` → `attribution_not_configured` | no analytic account (or dedicated income account) names this project | name it on the Settings tab; nothing is exported until it is set |
| `attribution_setup` → `PERMISSION_DENIED` | the API user lacks the Analytic Accounting group, which is a real ACL on `account.analytic.account` and friends | enable **Analytic Accounting** in Odoo's Settings and grant the group to this user. Without it, posting raises too — Odoo creates the analytic items as the calling user, with no `sudo` |
| `attribution_setup` → `analytic_distribution_unsupported` | this Odoo's `account.move.line` has no `analytic_distribution` field | configure the dedicated-income-account fallback, or use an Odoo that supports analytic accounting |
| `attribution_setup` → `analytic_account_company` | the analytic account belongs to a different company | find the right id; a shared account (`company_id` false) is fine |
| `attribution_setup` → `income_account_type` | the account named for the fallback is not an income account | find an income account; a receivable one would silently turn every revenue line into a payment term |
| `attribution` → `attribution_missing` | the draft's revenue line came back with no distribution | a distribution model in your Odoo is probably clearing it; check `account.analytic.distribution.model` |
| `attribution` → `attribution_foreign_analytic_account` | the draft came back attributed to an account that is not this project's | **stop**; this is the isolation failure. Check the analytic account id and your distribution models |
| `attribution` → `attribution_on_receivable_line` | the distribution landed on the receivable as well | **stop**; posting it would create an opposite-signed analytic line that cancels the revenue |
| `attribution_setup` ok with `distribution_models` above zero | your Odoo has rules that can add or replace an attribution this integration did not write — including on a **payment's** receivable line, because a payment is not an invoice and Odoo's compute guard falls through | not a failure. Check those rules against your receivable and revenue accounts; see limitation 17 |
| `attribution` ok with `tax_lines_carry_attribution` | your sales tax carries Odoo's `analytic` flag, so the tax is in the project's analytic total too | a configuration decision in your Odoo; see limitation 12 |
| `draft_create` → `PERMISSION_DENIED` | the user may not write `account.move` | grant Billing or Accountant rights |
| `draft_create` → `BUSINESS_RULE` | Odoo refused the payload; `detail` says why | usually a journal or currency setting |
| every probe green, `posting: unproven` | as good as it gets before going live | follow the go-live sequence |
