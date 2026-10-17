# What is NOT tested, and why it cannot be

The brief: *"Without real Odoo credentials, honestly report external end-to-end tests as BLOCKED, not PASSED.
Never write to my existing production Odoo during development."*

No Odoo server was reachable during this work and none was contacted. Everything below is **BLOCKED** — not
passing, not failing, not run. Each entry is one probe an operator can run from the Super Admin pages once
credentials exist, with the answer to expect.

---

## Blocked: the adapter against a real server

| # | Probe | Where to run it | Expected answer |
|---|---|---|---|
| B1 | `common.version` reaches the server unauthenticated | Diagnostics → Run connection test | the version and a transport |
| B2 | On Odoo Online, `server_version_info[0]` is a `saas~` string and is parsed | same, against an Online tenant | major read correctly; a spec covers the shape, the live call does not |
| B3 | JSON-2 `/json/2/<model>/<method>` exists and accepts a Bearer key on 19+ | same | transport `json2` |
| B4 | `/jsonrpc` still serves `common.authenticate` on 16–18 | same | transport `jsonrpc`, a positive uid |
| B5 | An API key authenticates where the user has 2FA enabled | same | authenticated |
| B6 | Whether `/json/2` exists at all before Odoo 19 | a real 17 or 18 server | expected absent; the adapter falls back on `ENDPOINT_MISSING` |

## Blocked: the accounting model on the customer's own chart of accounts

| # | Probe | Expected answer |
|---|---|---|
| B7 | `fields_get` returns all seven fields the adapter writes | present |
| B8 | `payment_state`'s selection on **this** server | includes `blocked` on 18+, not on 16/17 |
| B9 | A draft `out_invoice` is accepted in the configured journal | created |
| B10 | Reading it back shows the configured company and journal | matches, or `CONFLICT` |
| B11 | `unlink` on that draft succeeds and leaves no sequence gap | deleted |
| B12 | Whether the API user has `account.group_account_invoice` | only discoverable by posting; see B13 |
| B13 | **`action_post` on a real invoice** | posts; **this is the one that cannot be probed safely** |
| B14 | Whether posting moves `date` into the next open period (lock dates) | read back after posting |
| B15 | Whether Odoo's computed `amount_total` matches Stripe's total on a real invoice with tax | agreement, or `total_mismatch_with_stripe` |
| B16 | Whether explicit `tax_ids` would be respected or re-mapped by the partner's fiscal position | unknown; not sent today ([05-limitations.md](05-limitations.md) §2) |
| B17 | `account.payment.register` + `action_create_payments` returns a payment id in `res_id` | an id |
| B18 | `in_payment` is reachable at all on this install (needs the accountant module) | `paid` on Invoicing-only installs |
| B19 | `account.move.reversal` + `reverse_moves` returns ids in `new_move_ids` | an id |
| B20 | A future-dated reversal is created with `auto_post: 'at_date'` and is not yet posted | state `draft` |
| B21 | What `reverse_moves` does to an invoice that is already partially paid | unknown; not attempted — a full reversal is only issued for a full refund |
| B22 | Whether a write to `payment_state` raises or is silently overwritten | never written, so never discovered |
| B23 | Whether `ref` can still be stamped on a hash-protected posted move | stamped at create time instead, so not exercised |
| B24 | Rate limits, request-size limits or concurrency limits on the external API | none documented; unknown in practice |
| B25 | Whether the API user may create an `x_` custom field over RPC | not needed — the stamp lives in `ref` plus our own mapping table |

## Blocked: end to end

| # | Probe | Expected answer |
|---|---|---|
| B26 | A real `invoice.paid` webhook produces a draft in Odoo | one draft, one mapping, state `synchronized` |
| B27 | …then a posted invoice, once posting is on | a numbered invoice |
| B28 | …then a registered payment, once that is on | `payment_state` reads `paid` when read back |
| B29 | A real full refund produces a reversal | a credit note linked to the invoice |
| B30 | A real partial refund produces an `out_refund` needing reconciliation | `needs_review` with the stated reason |
| B31 | A redelivered webhook produces no second document | no change in counts |
| B32 | A lost answer (Odoo killed mid-create) is recovered by stamp search, not re-created | one document |
| B33 | A historical import over a period live sync covered queues nothing | zero queued |
| B34 | Two unrelated accounts sharing a billing email get two partners | two ids |
| B35 | An invoice is never matched against another company's in the same database | nothing matches |

### Project attribution inside the one shared company (B36–B44)

These are the probes the architecture correction added. Every one of them needs the owner's real Odoo, because
every one is a question about how **that** server behaves, not about this code.

| # | Probe | Expected answer |
|---|---|---|
| B36 | `account.move.line` on this server has `analytic_distribution` | the field is present (Odoo 16+) |
| B37 | The configured analytic account exists and is usable by the configured company | `attribution_setup` green, naming the account and its plan |
| B38 | A draft invoice's revenue line comes back carrying 100% to that account | `attribution` green |
| B39 | The receivable line comes back **without** that account | no `attribution_on_receivable_line` |
| B40 | Whether the destination's sales tax carries Odoo's `analytic` flag | `tax_lines_carry_attribution` present or absent — either is valid, and it tells the owner whether the project's analytic total includes tax |
| B41 | `analytic.project_plan` names a valid root plan (Odoo 17+) | posting a distribution-bearing line succeeds rather than raising `UserError`. **Check this before enabling posting**: `ir.config_parameter` is usually unreadable by an API user, so no probe attempts it. A lead for whoever runs this on the real server: `account.analytic.plan.get_relevant_plans` is RPC-callable and is reported to raise a `UserError` when the parameter is unset — called with named args `{"business_domain": "invoice", "company_id": C}` and context `{"allowed_company_ids": [C]}`. That signature was read in the source, **not executed**, which is why it is a blocked probe rather than a shipped one |
| B42 | `validate_analytic: true` on `action_post` surfaces as an error to an API caller | a refused posting rather than a silently unattributed one. Odoo raises `RedirectWarning` instead of `ValidationError` when the validation spans more than one move, which cannot happen here — posting is one move per call — but the API-visible shape was read in the source, not executed |
| B43 | A posted invoice produced `account.analytic.line` rows against this project's account, and only this project's | analytic lines equal to the revenue, nothing on another project's account. The integration now **checks for their existence itself** after posting and marks `analytic_lines_not_created` when there are none — what is blocked is confirming the amounts and the account column on a real server |
| B45 | An **archived** analytic account is refused by the probe rather than silently dropping attribution | `attribution_setup` → `analytic_account_archived`. Archive the account in Odoo, re-run the probe, then un-archive it |
| B46 | A distribution model matching one of the owner's **other** projects does not survive our read-back | the document stops at `needs_review` with `attribution_foreign_analytic_account`, un-posted |
| B47 | Which reporting isolation the owner actually sees on **their** edition | Enterprise: an analytic filter in the financial reports. Community: the analytic items list and pivot, because Community ships no P&L report (limitation 16) |
| B44 | The owner's own analytic profit-and-loss report shows Lynomia Chat separately from the sibling projects | **this is the whole point of the integration's reporting side, and it is the one answer only the owner's Odoo can give** |

## What IS tested, without a server

295 examples, 0 failures (the Odoo suite plus the schedule and credential gates it touches). In particular:

- the ten configuration states as an ordered funnel, and the DB-enforced one-enabled-destination rule;
- the credential encrypted at rest, excluded from serialization, never rendered into the settings form, and
  preserved when the field is submitted empty;
- the exact payloads the adapter sends — `move_type` set, no `name`, no `state`, no `account_id` on a product
  line, literal x2many triples, `allowed_company_ids` on every call, `payment_state` in no write;
- the destination-scope AND stamp checks refusing a sibling project's move by id, in the same company and the
  same journal (spec/security/odoo_project_isolation_spec.rb);
- the analytic distribution on every authored revenue line, its string key and numeric value, and its absence
  from the move header, the receivable and every payment payload;
- the read-back verification refusing a document attributed to another project, attributed in part, or not
  attributed at all, and accepting an analytic tax line Odoo filled itself;
- a credit note carrying the same project attribution as the invoice it credits, repaired while draft and
  reported when already posted;
- activation refused when the attribution probe has not passed or no analytic account names this project;
- the total comparison refusing to post a mismatch, with the tolerance scaled for KWD;
- the idempotency key, the stamp-search recovery, and the two-matches conflict;
- the unknown-outcome guard refusing a second payment against an invoice Odoo already reads as paid;
- full versus partial refund choosing the right Odoo operation;
- the queue's seven states, the atomic claim under two concurrent runners, the backoff, and
  attempt-before-write;
- the Stripe webhook enqueueing and provably touching no Odoo transport;
- `Odoo::Money` for every zero-decimal and three-decimal currency Stripe publishes;
- the Odoo Online `saas~19` version string;
- all sixteen Super Admin routes refusing a tenant administrator and a tenant agent;
- the commerce boundary, structurally and behaviourally.
