# Lynomia Commerce: order actions architecture (Phase 9–10)

How an agent changes an order in a connected store from a conversation, safely. What each provider supports is in
[29-provider-action-capabilities.md](29-provider-action-capabilities.md); permissions, idempotency, reconciliation and
the threat review in [32-actions-security.md](32-actions-security.md); the E2E in [33-phase9-10-e2e.md](33-phase9-10-e2e.md).

## 1. Principles

- **The store is the source of truth.** Lynomia never shows an order state it did not read from the store. After an
  action the order is read again; there is no optimistic status in the UI.
- **A write is sent at most once.** Every action has an idempotency key (`commerce-action:<uuid>`) and a row
  (`commerce_action_runs`). Jobs are never retried. A lost answer is settled by reading the store, never by sending the
  write again (§5).
- **Nothing runs from a click.** The order card's ••• menu opens a dialog: choose → fill in → review (store, provider,
  order, amount and currency, consequence) → Confirm. Enter never confirms; a double click is the same action.
- **Provider-neutral.** The UI, the service and the jobs never check a provider's name. A provider declares what it can
  do (`supports_actions?`, `write_access_problem`, `action_snapshot`, `perform_action`, `reconcile_action`), and its
  snapshot says, per action, whether the order allows it now.
- **Off unless asked for.** Installation kill switch, provider switches, providers held back until their real UAT, and a
  per-store opt-in by the store's administrator. Credentials are never upgraded silently.
- **Not a marketing or automation platform.** Actions are single, human-confirmed operations on one order.

## 2. Actions

| Action | Who (§32) | What it does | Providers (doc 29) |
|---|---|---|---|
| `update_order_status` | administrators, or a custom role with `commerce_order_manage` | one step from the provider's allow-list | WooCommerce, Zid |
| `resend_invoice` / `resend_payment_link` | same | the store's own order-details email | WooCommerce |
| `cancel_order` | administrators only | cancels an unpaid order; **never refunds** (the review says so) | WooCommerce, Shopify |
| `refund_partial` / `refund_full` | administrators only | an amount-only refund, up to what the store says is refundable now | WooCommerce, Shopify |
| `update_shipping` | — | not offered by any provider (it would mean editing an address) | none |

## 3. Gates, in order

`Commerce::OrderActions` (and again `Commerce::ActionExecutor` before sending) checks:

1. the provider implements actions (`supports_actions?`), else `unsupported`
2. `COMMERCE_ACTIONS_ENABLED` (kill switch), else `actions_disabled`
3. the provider's switch, the provider's **read** switch, and the pre-UAT hold (`Commerce::Switches`, §6), else
   `provider_actions_disabled`
4. the store's opt-in (`store.settings['order_actions']`, set by an administrator in Settings → Commerce), else
   `store_actions_off`
5. the store's credentials can write (`write_access_problem`: `read_only_key`, `missing_scope`,
   `write_access_unverified`)
6. the user's permission (`Commerce::ActionPolicy`)
7. no earlier action on the same order is unresolved (pending, running, or unknown and still being reconciled)
8. the order, read from the store now: it must be one of the conversation's linked customer's latest 25 orders in that
   store (`ensure_owned!`), and its state must allow the action (the provider's capability)

Steps 1–5 decide whether the store offers the ••• menu at all (`offered?`), and settings show them as one line per store
(§7). Any other order id answers `NOT_FOUND`.

## 4. Flow

```
••• on the order card ──GET …/stores/:store/orders/:order/actions──▶ OrderActions#availability
                                                  reads the order now: version + per-action capability + last run
dialog: choose → form → review (Confirm only; one key per review)
       ──POST …/actions { action_type, version, idempotency_key, params }──▶ OrderActions#request
          validate (documented values only) → rate limits → store lock "commerce_action:<store>:<order>"
          ├─ key already used: same values → the same run (202); other values → IDEMPOTENCY_CONFLICT
          ├─ an unresolved action on the order → ACTION_IN_PROGRESS
          └─ create the run (pending), audit commerce.action.requested, queue Commerce::ActionJob → 202 + run
                                                  │
Commerce::ActionJob (queue high, retry: false) ──▶ ActionExecutor#call
          claim: pending → running under a row lock (two workers never both send)
          gates 1–6 again, as the requester is now
          read the order again (ownership included): version ≠ confirmed version → ORDER_CHANGED (nothing sent)
          capability now; refund amount ≤ refundable now, same currency, same precision → else INVALID_AMOUNT
          provider.perform_action(…, idempotency_key) — once
          ├─ succeeded → read the order back (status), mark the customer's cache outdated, Realtime.schedule_refresh
          ├─ failed    → error code (PROVIDER_REJECTED, REFUND_DECLINED, WRITE_ACCESS_DENIED, …)
          ├─ running   → the store works asynchronously (Shopify Job): reconcile
          └─ lost answer (timeout, 5xx, connection reset after sending) → unknown: reconcile (§5)
dialog polls GET …/action_runs/:id (1.5 s × 40) and shows only what the run says
```

The panel never edits the card itself: a success refreshes the customer through the Phase 7 realtime core
(`commerce.customer.updated`), so every agent's open panel reads the order from the store again.

## 5. Unknown outcomes and reconciliation

A write whose answer is lost may or may not have taken effect. Lynomia never repeats it. Instead:

- `Commerce::HttpClient#write_json` sends once with a 25 s read timeout. A failure before the request was written
  (`OpenTimeout`, connection refused, DNS) is `not_sent` (safe: nothing reached the store). Anything after is
  `unknown_outcome`.
- The run becomes `unknown` and `Commerce::ActionReconcileJob` reads the store at 30 s, 2 min and 10 min
  (`reconcile_action`, read-only): WooCommerce finds its refund by the `lynomia_action_key` meta and statuses by the
  order's status; Shopify finds its refund by the note `Lynomia <key>` and a cancellation by its Job and `cancelledAt`;
  Zid by the order's status.
- A run is `failed` with `NOT_APPLIED` only when the store provably does not show it and enough time has passed for any
  request still running in the store to finish (`SETTLED_AFTER` = 5 min).
- After the last attempt the run stays `unknown` with `reconcile: exhausted`: it stops blocking the order, the dialog says
  "check the order in the store before trying again", and the audit records `reconciled` with outcome `unresolved`.
- A worker that dies mid-send is caught by a stall check 2 minutes after each send. `Commerce::ActionSweepJob` (every
  10 minutes) fails runs whose job never started (`NOT_SENT`, nothing was sent) and re-queues reconciliation of runs
  left unresolved for 15 minutes. It never sends a write.

## 6. Switches and production defaults

| Switch (Super Admin → Settings → Lynomia Commerce, else ENV) | Default | Effect |
|---|---|---|
| `COMMERCE_ACTIONS_ENABLED` | `true` | kill switch: off stops new actions at once (already sent ones are still reconciled) |
| `WOOCOMMERCE_ACTIONS_ENABLED` | `true` | WooCommerce actions, still per store: the administrator opts in with a Read/Write key |
| `SALLA_ACTIONS_ENABLED`, `ZID_ACTIONS_ENABLED`, `SHOPIFY_COMMERCE_ACTIONS_ENABLED` | `false` | and held back regardless until each provider passes its real UAT |
| `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` (ENV only) | unset | staging and simulated E2E runs only; never set in production |

A provider's actions are never on while its read switch (`SALLA_ENABLED`, `ZID_ENABLED`, `SHOPIFY_COMMERCE_ENABLED`) is
off. The pre-UAT list (`Commerce::Switches::PRE_UAT`) is code: a provider leaves it through a reviewed change after its
UAT, not through a setting.

## 7. Settings → Commerce

Each active store shows three lines, separately: **Read-only Commerce: on**, the live-updates state (Phase 7), and the
order actions state with what to do about it:

| State | Line | Control |
|---|---|---|
| available, not opted in | Order actions: off | Turn on order actions |
| available, opted in | Order actions: on | Turn off order actions |
| `read_only_key` | Order actions require a Read/Write WooCommerce API key. | Replace keys (the existing key is never upgraded) |
| `missing_scope` | Additional {provider} permissions are required. Reconnect {provider} to enable order actions. | Reconnect for order actions (Shopify) |
| switched off / held back | Order actions are switched off on this installation. | — |

Opting in or out is audited (`commerce.order_actions_changed`). A hint reminds that refunds and cancellations stay
limited to administrators.

## 8. Data: `commerce_action_runs`

| Column | |
|---|---|
| `account_id`, `commerce_store_id`, `contact_id`, `conversation_id`, `requested_by_id` | tenancy and who asked (account cascade, user nullified) |
| `provider`, `action_type`, `external_resource_id` | the store order (or cart, §31) id only |
| `idempotency_key` (unique), `request_digest` | the confirmation and a digest of its values |
| `status` | pending, running, succeeded, failed, unknown |
| `provider_request_id` | the store's reference (refund id, Shopify Job) |
| `started_at`, `completed_at`, `error_code` | |
| `metadata` (jsonb) | the confirmed values (target status, reason, amount, currency, restock), the order's version, number and status before, the refund mode, the status read back afterwards, reconciliation attempts |

Never stored: tokens, keys, addresses, names, emails, phones, the order's JSON, items or payment data. Order action runs
are kept as the audit record; recovery runs (doc 31) are deleted after 90 days.

Indexes: unique `idempotency_key`; `[commerce_store_id, external_resource_id, status]` (the in-progress check);
`[status, updated_at]` (the sweep).

## 9. Audit and metrics

- Audit (Enterprise audit log, `Commerce::AuditTrail`): `commerce.action.requested`, `commerce.action.succeeded`,
  `commerce.action.failed`, `commerce.action.reconciled` (with its outcome), `commerce.order_actions_changed`. Fields:
  store, provider, action, order id and number, amount/currency, status, error code. No contact details.
- Metrics (`Commerce::Metrics`, tagged log lines): `commerce.action.requested`, `commerce.action.success`,
  `commerce.action.failure`, `commerce.action.unknown`, `commerce.action.reconciled`; with provider, store, action, run and
  error code.

## 10. Extension points

- A provider adds actions by implementing the five methods of `Commerce::Providers::Base` for the actions its API
  supports for certain; everything else is reported unsupported and never shown.
- The UI reads `availability.actions[type]` (`available`, `reason`, `targets`, `max_amount`, `currency`, `mode`,
  `gateway`, `restocks`) and labels; it has no provider branches.
- Enterprise: `commerce_order_manage` is a custom-role permission (status and resend only). Refunds and cancellations are
  not delegable to agents in this phase.

## 11. Rollback

The phase adds one table (`20261001100000_create_commerce_action_runs`). Rolling the code back leaves it unused; older
code ignores it, the `order_actions` store setting and the `write_access` store metadata key. To remove it:
`bundle exec rails db:migrate:down VERSION=20261001100000` (drops `commerce_action_runs`; no other table changes). Set
`COMMERCE_ACTIONS_ENABLED=false` first to stop new actions; let unresolved runs finish reconciling (at most ~13 min) before
dropping the table if their audit matters.
