# Lynomia Commerce: actions and recovery security (Phase 9–10)

Threat review of order actions (doc 28), abandoned carts (doc 30) and recovery messages (doc 31), with the control and the
test for each. Read with [04-security-and-tenancy.md](04-security-and-tenancy.md) and
[26-realtime-security.md](26-realtime-security.md), which still apply.

## 1. Permissions

| Operation | Who | Where enforced |
|---|---|---|
| See what is possible (`GET …/actions`) | anyone who can see the conversation | conversation authorization; returns `permission_denied` per action |
| Status change, resend emails | administrators; agents whose **custom role** grants `commerce_order_manage` (Enterprise) | `Commerce::ActionPolicy#manage_orders?` at request and again before sending |
| Cancel, refund | **administrators only** (pilot); no custom role can grant them | `ActionPolicy#cancel?` / `#refund?` |
| Opt a store in/out of actions | administrators (store policy) | `PATCH /commerce/stores/:id { order_actions: true|false }` |
| Reconnect Shopify for `write_orders` | administrators (existing connection policy) | Shopify connection controller + callback |
| See carts, prepare a recovery message | anyone who can see the conversation | conversation authorization |
| Override the recovery cooldown | administrators | `RecoveryMessages#check_cooldown!` |
| Cart queue | administrators | `Commerce::StorePolicy#index?` |

Agents get no destructive operation automatically: a fresh agent sees no ••• menu at all.

## 2. Threats and controls

| # | Threat | Control | Tests |
|---|---|---|---|
| T1 | A double click, a retried request or two tabs issue two refunds | one key per review (`commerce-action:<uuid>`), unique index; request under a store/order lock; same key + same values → the same run; jobs claim `pending → running` under a row lock; no job retries | `order_actions_spec` double submit; `action_executor_spec` "never sends a run twice"; `woocommerce_actions_spec` "refunds once however often…"; E2E double-click and simultaneous requests (doc 33) |
| T2 | A key reused with other values (replay, tampering) | `request_digest` compared: `IDEMPOTENCY_CONFLICT`; a key from another account conflicts, never returns that run | `order_actions_spec`, `actions_security_spec` |
| T3 | The order changed between review and send (stale action) | the confirmed `version` (hash of status, totals, payment, refunds) must equal the order read again before sending: `ORDER_CHANGED`, nothing sent | specs + E2E (status changed in the store after review) |
| T4 | Refund more than paid, in another currency, or a "full" refund of a different amount | amount validated at request (format) and before sending against the store's refundable amount now (WooCommerce: total − refunds; Shopify: suggested maximum), same currency, same precision; `refund_full` must equal the maximum | `action_executor_spec`, `woocommerce_actions_spec`, E2E over-refund |
| T5 | A lost answer is retried and the write happens twice | `not_sent` vs `unknown_outcome` from the HTTP client; unknown → reconcile by reading only; a run is failed (`NOT_APPLIED`) only when the store provably shows nothing after `SETTLED_AFTER`; after the last attempt it stays unknown (`exhausted`) and the agent is told to check the store | `action_executor_spec` "a lost answer…"; provider reconcile specs; E2E gateway timeout (WooCommerce, real) and lost answer (Shopify) |
| T6 | A worker dies mid-send; a job is lost | stall check 2 min after each send; `ActionSweepJob` fails never-started runs (`NOT_SENT`) and re-queues reconciliation; never sends | `actions_security_spec` sweep |
| T7 | Acting on another customer's or another store's order | the order must be among the linked customer's latest 25 orders in that store, read now; any other id is `NOT_FOUND` and the store is not asked to change it; the run is scoped to store and conversation | `woocommerce_actions_spec` cross-order, `actions_security_spec` cross-store |
| T8 | Cross-tenant access | every endpoint scopes stores, conversations and runs to `Current.account`; runs are read through the conversation | `order_actions_controller_spec` "not reachable from another account", carts specs, E2E account B |
| T9 | Privilege escalation through the browser | the browser's availability is never trusted: permission, switches, opt-in, credentials, capability and amount are all checked server-side at request and again before sending | `order_actions_controller_spec` "forged availability" |
| T10 | Silent scope or key upgrade | WooCommerce keys are never replaced by Lynomia; Shopify `write_orders` only through an explicit reconnect, with exact-scope checking; less granted → refused, previous connection kept | callbacks spec, `woocommerce_actions_spec` opt-in, E2E scope upgrade |
| T11 | A provider before UAT acting in production | `PRE_UAT` list in code; only the ENV `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` lifts it (never set in production); provider actions never on while its read switch is off | `switches_spec`, E2E gate phase |
| T12 | Raw provider errors or secrets reaching agents | provider answers are mapped to Lynomia codes (`PROVIDER_REJECTED`, `REFUND_DECLINED`, …); no response body, gateway message or token is stored, logged or returned | E2E scan of every API response, log and socket frame |
| T13 | Status abuse (trash, plugin statuses, re-opening) | WooCommerce allow-list only; documented target values only (`TARGET_STATUSES`) | `woocommerce/actions_spec`, `order_actions_spec` "only documented values" |
| T14 | "Cancel" read as "refund" | cancellation is offered only for unpaid orders, sent with `refund: false` where the API has it, and the review says "Cancelling does not refund any payment." | specs + E2E |
| T15 | Flooding a store with writes | rate limits: 10 requests/min per user, 30/min per store, 5 per order per 10 min (429 + `Retry-After`); an unresolved action blocks the order | `order_actions_spec`, controller spec, E2E |
| T16 | Wrong cart matched to a contact (privacy) | only linked customer, verified channel phone, verified channel email; no names, editable fields or masked values; ambiguous identities match nothing; suppressed links never match | `abandoned_carts_spec` |
| T17 | A malicious recovery link sent by an agent | link taken only from the store's cart; `https` on the store's or provider's hosts only; never from a request | `recovery_url_spec`, `recovery_messages_spec`, E2E unsafe link |
| T18 | Messaging outside the channel's window or without consent | `can_reply?` before preparing; nothing is ever sent by Lynomia; no template is sent automatically | `recovery_messages_spec`, E2E window |
| T19 | Spam / bulk | no bulk or broadcast endpoint; one cart per preparation; cooldown per cart; 30 preparations per agent per hour | specs, E2E queue |
| T20 | Sensitive data at rest | runs keep ids, amounts and codes only (doc 28 §8); carts only in the cache, without contact details or links; recovery runs deleted after 90 days | E2E run/audit content checks |

## 3. Mandatory security tests (brief item 56–57)

Actions (56): idempotent double submit; replayed key; stale version; over-refund; cross-order; cross-store; cross-account;
agent refund refused; forged availability; kill switch; provider read switch; pre-UAT hold; re-authorization needed;
write credentials missing; lost answer reconciled; dead worker; lost job swept; rate limits; documented values only.
Carts (57): matching by verified identities only; masked, suppressed and ambiguous identities; recovered/expired carts;
cross-store and cross-account carts; unsafe links; reply window; cooldown and override; queue admin-only without contact
details; WooCommerce unsupported; recovery sent only from an outgoing message carrying the link.

All are in the RSpec suites listed above and, end to end, in doc 33.

## 4. Residual risks

- **WooCommerce gateway refunds** are only as reliable as the store's gateway plugin. A gateway that refunds but answers
  an error would show `REFUND_DECLINED` while money moved; WooCommerce itself deletes the refund record in that case.
  Mitigation: administrators only, the review names the gateway, and the store's order notes are the reference.
- **Resend emails** cannot be reconciled (no state); a lost answer stays unknown and the agent checks the order notes.
- **Shopify `@idempotent`** is VERIFY on a live store; Lynomia does not rely on it (single send + note reconciliation).
- **Zid** has no idempotency and no readable scopes; one status step is low impact and reconciled by status.
