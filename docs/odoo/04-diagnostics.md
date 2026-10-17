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

Six independent probes. Each is reported separately, because an operator fixing a misconfiguration wants the
whole list rather than the first line of it.

| Probe | Asks | Fails when |
|---|---|---|
| `model_shape` | `fields_get` on `account.move` for seven fields | a field the adapter writes is absent |
| `company` | the configured `res.company` exists | the id is wrong |
| `sale_journal` | the journal is `type = sale` **and in the configured company** | either is wrong |
| `payment_journal` | the journal is bank, cash or credit, in the same company | either is wrong |
| `analytic_account` | the account exists — **skipped** when none is configured | the id is wrong |
| `draft_create` | **one draft invoice created in the configured journal, read back, and deleted** | the write is refused |

The journal-company check is the one that matters most: a journal in the wrong company would post Lynomia's
revenue into another business's books, which is the exact failure this integration exists to prevent.

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
| `sale_journal` → `journal_company` | the journal belongs to another company | **stop**; this is the isolation failure |
| `draft_create` → `PERMISSION_DENIED` | the user may not write `account.move` | grant Billing or Accountant rights |
| `draft_create` → `BUSINESS_RULE` | Odoo refused the payload; `detail` says why | usually a journal or currency setting |
| every probe green, `posting: unproven` | as good as it gets before going live | follow the go-live sequence |
