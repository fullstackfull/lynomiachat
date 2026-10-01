# Lynomia Commerce: Phase 9–10 E2E (order actions, abandoned carts, sales recovery)

How order actions, abandoned carts and recovery messages were tested end to end, what passed, and what the runs found.
Architecture: [28](28-commerce-actions-architecture.md). Providers: [29](29-provider-action-capabilities.md). Carts:
[30](30-abandoned-carts.md). Recovery: [31](31-sales-recovery.md). Security: [32](32-actions-security.md).

## 1. Environment

| | |
|---|---|
| Code | working tree at the Phase 9–10 head, production mode (`RAILS_ENV=production`, production Vite build of that tree). The only later code change: the review's order number goes through the existing `COMMERCE.PANEL.ORDER_NUMBER` key (same text, an ESLint warning removed) |
| Runtime | `lynomia/verify:base` (Ruby 3.4.4, Node 24), Postgres 16, Redis 7 |
| Processes | web server (Puma) and a **Sidekiq worker**, as in production: action, reconciliation, refresh, webhook and reply jobs all run in the worker |
| Browser | Playwright + Chromium: administrator A, agent A (no order permission), administrator B (another account), 390 px mobile |
| WooCommerce | **real** WooCommerce 10.9.4 (HPOS) in Docker, store A1 with a **Read/Write** key, store A2 with a **Read** key |
| Salla, Zid, Shopify | simulated in-process (WebMock) in the server, the worker and the control runner, from documented shapes; their hosts are not reachable from this environment |
| WhatsApp | the conversation is in the seeded WhatsApp Cloud inbox; the Cloud API's send-message answer is simulated, so an agent's reply is "delivered" without reaching Meta |

**Never a merchant's order.** Every WooCommerce order the run acts on is created by the run in the disposable test
store (the store's guest customer Omar), and deleted with its refunds at the end. The run also removes Lynomia's webhooks
and the test gateway, so the other E2Es find the store as seeded.

**Test-only gateway** (`woocommerce/lynomia-e2e-gateway.php`, a must-use plugin of the test store only): a payment
gateway that supports refunds through WooCommerce's real refund flow without moving money. 13.13 is declined (WooCommerce
deletes the refund it created and answers an error); 7.77 answers after 35 s, longer than Lynomia's 25 s write timeout,
and is then made: the lost-answer case on a real store. Every gateway call and every email WordPress would send are
recorded in options instead.

**Two phases, one app** (`docs/commerce/e2e/actions/`):

1. **gate**: the production configuration. WooCommerce for real. Salla, Zid and Shopify are connected and Super Admin
   switches their actions and carts on: they must still offer nothing, since they have not passed a real UAT.
2. **sim**: the same database, the server and worker restarted with `COMMERCE_ALLOW_PRE_UAT_PROVIDERS=true` (staging
   and simulations only). Zid and Shopify actions, the Shopify write-scope reconnect, Salla/Zid/Shopify carts, recovery
   messages, cart events and the administrator queue.

Harness: `sims.rb` (the Phase 7–8 simulators plus Zid `view`/`change-order-status`/`abandoned-carts`, Shopify order
action fields, `orderCancel` with a Job, `refundCreate` with `@idempotent`, `abandonedCheckouts`, `primaryDomain`,
Salla `/carts/abandoned`, the WhatsApp Cloud answer), `server.rb`, `worker.rb`, `ctl.rb` (switches, store-side
changes, carts, cart events, the messaging window, and read-outs of runs, audit and the simulators),
`e2e_actions.js` and `run.sh`.

## 2. Phase 9–10 E2E: **94/94 passed**

Results: `e2e/results/phase9/actions_e2e_gate.{json,txt}` and `actions_e2e_sim.{json,txt}`. Screenshots:
`screenshots/phase9/` (§5). One recorded run of both phases on the final build.

### Production configuration (gate): **51/51**

| # | Check | |
|---|---|---|
| 1 | production defaults: WooCommerce read on, order actions switch on (each store still opts in), Salla/Zid/Shopify off | PASS |
| 2 | production defaults: recovery off everywhere (WooCommerce has no abandoned-cart API), no pre-UAT override | PASS |
| 3 | disposable WooCommerce orders created for this run (never a merchant order) | PASS |
| 4 | Read/Write key: Read-only Commerce, live updates and order actions shown separately; actions off until opted in | PASS |
| 5 | Read key: "Order actions require a Read/Write WooCommerce API key." and nothing to turn on; the key is not upgraded | PASS |
| 6 | switches on for Salla/Zid/Shopify, yet their actions and carts stay off: providers before UAT are held back | PASS |
| 7 | settings: Zid and Shopify say order actions are switched off on this installation; Salla offers none | PASS |
| 8 | no abandoned-cart queue while no store offers carts | PASS |
| 9 | the administrator turns order actions on for the Read/Write store | PASS |
| 10 | the administrator sees the order actions menu on the opted-in store's orders | PASS |
| 11 | an agent without the order permission sees no actions menu at all | PASS |
| 12 | menu of a paid processing order: status, resend, refunds; cancel explained as "refund it first"; never trash | PASS |
| 13 | status change: the review names store, provider, order and the change; done after the store confirms | PASS |
| 14 | WooCommerce has the order completed, written once | PASS |
| 15 | another agent's open panel shows the new status live, without a reload | PASS |
| 16 | resend invoice: WooCommerce emails the order details once, to the order's billing email | PASS |
| 17 | cancel an unpaid order: the review says cancelling refunds nothing; WooCommerce cancels it, no refund, no gateway call | PASS |
| 18 | refund form: an amount above the refundable maximum is refused before review | PASS |
| 19 | Enter submits nothing: not in the amount field, not on the review | PASS |
| 20 | refund review: store, order, amount and currency, the gateway and "can’t be undone" | PASS |
| 21 | a double-clicked Confirm makes one run and one refund of 10.00 through the gateway | PASS |
| 22 | the refund carries the run's idempotency key in WooCommerce (how a lost answer is reconciled) | PASS |
| 23 | the same key again answers the same run; with other values it is refused (IDEMPOTENCY_CONFLICT) | PASS |
| 24 | two simultaneous requests with one key: one run, one refund in WooCommerce | PASS |
| 25 | the order changed in the store after review: the action stops, nothing is sent (ORDER_CHANGED) | PASS |
| 26 | the gateway declines: the dialog says so and no refund exists | PASS |
| 27 | no answer within the timeout: the run is unknown and the dialog says not to try again | PASS |
| 28 | while unknown, no other action on the order is possible | PASS |
| 29 | reconciled by reading WooCommerce: the refund made after the timeout is found by its key; nothing was sent again | PASS |
| 30 | refund in full: the remaining refundable amount, fixed; WooCommerce marks the order refunded | PASS |
| 31 | nothing is left to refund afterwards | PASS |
| 32 | cash on delivery in processing is not paid yet (WooCommerce sets no payment date): no refund offered | PASS |
| 33 | a gateway without refunds: the review says the refund is recorded only; WooCommerce records it, no money moves | PASS |
| 34 | more than the provider-confirmed refundable amount is never sent (INVALID_AMOUNT) | PASS |
| 35 | …and WooCommerce has no new refund | PASS |
| 36 | an agent cannot refund through the API either | PASS |
| 37 | the Read-key store refuses actions (and does not know the other store's order) | PASS |
| 38 | rate limit: the sixth request on one order within 10 minutes gets 429 with Retry-After; refused runs wrote nothing | PASS |
| 39 | COMMERCE_ACTIONS_ENABLED=false: no actions menu, requests refused (ACTIONS_DISABLED), orders still shown read-only | PASS |
| 40 | WooCommerce refuses the write (the key became read-only): the dialog says the credentials can't change orders | PASS |
| 41 | settings now ask for a Read/Write key; nothing was upgraded or retried silently | PASS |
| 42 | the administrator replaces the key with a Read/Write one: order actions on again (the opt-in was kept) | PASS |
| 43 | WooCommerce: no abandoned carts (no merchant-wide API in WooCommerce core); none shown, nothing else asked of the store | PASS |
| 44 | audit trail: requested, succeeded, failed, reconciled, order actions changed | PASS |
| 45 | action runs keep no addresses, contact details, tokens, payment data or order JSON | PASS |
| 46 | audit entries carry no contact details or credentials | PASS |
| 47 | Arabic: the review in Arabic, right to left | PASS |
| 48 | mobile: the conversation renders at 390 px | PASS |
| 49 | no credential, token or secret in logs, API responses or socket frames | PASS |
| 50 | no raw provider error reached the browser | PASS |
| 51 | no page errors | PASS |

### Pre-UAT override, simulated providers (sim): **43/43**

| # | Check | |
|---|---|---|
| 1 | staging override set: Zid and Shopify actions, Salla/Zid/Shopify carts available for this run only | PASS |
| 2 | Zid: order actions available to opt in | PASS |
| 3 | Shopify connected read-only: "Additional Shopify permissions are required. Reconnect Shopify to enable order actions." | PASS |
| 4 | read-only until now: the connection never held write_orders | PASS |
| 5 | Reconnect for order actions asks Shopify for write_orders explicitly | PASS |
| 6 | the merchant approves fewer permissions than asked: refused, the read-only connection is kept as it was | PASS |
| 7 | approved: the same store now holds write_orders and can be opted in (still off until the administrator turns it on) | PASS |
| 8 | Zid and Shopify opted in | PASS |
| 9 | Zid: ready → shipped through change-order-status, once | PASS |
| 10 | Zid: in delivery → delivered | PASS |
| 11 | Zid offers nothing else (no refunds, no cancellation through Lynomia) | PASS |
| 12 | Zid refuses the write (403): Lynomia learns the authorization lacks the permission and asks for a reconnect | PASS |
| 13 | after the administrator authorizes Zid again, order actions are back on | PASS |
| 14 | Shopify paid order: refunds through its payment, no cancellation ("refund it first") | PASS |
| 15 | Shopify refund: refundCreate once, with @idempotent and the run's key, through Shopify Payments, notify off | PASS |
| 16 | Shopify: two simultaneous requests with one key send one refundCreate | PASS |
| 17 | Shopify userErrors: the store refused, nothing refunded | PASS |
| 18 | Shopify lost answer: unknown, then found by its note when reconciling; refundCreate was sent once | PASS |
| 19 | Shopify cancel of an unpaid order: orderCancel (refund false, customer not notified), followed through its Job until the order shows it | PASS |
| 20 | the cancelled order reads back as cancelled | PASS |
| 21 | Salla: no order actions (no verified write contract) | PASS |
| 22 | only Omar's carts: Zid by his linked customer, Shopify by customer id, Salla by linked customer | PASS |
| 23 | never another customer's cart (same phone), a masked one, a recovered or an expired one, or a guest checkout | PASS |
| 24 | the cart list carries no email, phone or recovery link | PASS |
| 25 | the Customer 360 section shows them with store, provider, total and items | PASS |
| 26 | prepare: the message lands in the reply box with the store's own link; nothing is sent | PASS |
| 27 | the cart says the message is prepared, not sent | PASS |
| 28 | sent by the agent: the outgoing message with the link marks it sent | PASS |
| 29 | the cart shows it sent, and the cooldown; the agent has no Prepare (and no override) | PASS |
| 30 | cooldown: an agent is refused (RECOVERY_COOLDOWN), and cannot override | PASS |
| 31 | an administrator can override the cooldown for one message (recorded) | PASS |
| 32 | a recovery link outside the store's hosts is refused: nothing prepared | PASS |
| 33 | outside the 24-hour window nothing is prepared and the reason is shown (a template is needed) | PASS |
| 34 | back inside the window, the Shopify checkout's myshopify.com link is prepared | PASS |
| 35 | Shopify protected customer data refused: no checkout shown, the store is reported unreadable | PASS |
| 36 | Salla abandoned.cart event: the new cart appears live, without a reload | PASS |
| 37 | admin queue: the stores' recent carts, linked contacts first, deterministic | PASS |
| 38 | the queue shows no contact details or recovery links, and has no bulk send | PASS |
| 39 | Arabic: the abandoned carts section in Arabic | PASS |
| 40 | another account cannot read this account's cart queue or runs | PASS |
| 41 | no credential, token or secret in logs, API responses or socket frames | PASS |
| 42 | no raw provider error reached the browser | PASS |
| 43 | no page errors | PASS |

## 3. Regressions

Every earlier E2E ran unchanged on the same build after the Phase 9–10 run (`e2e/results/phase9/*_regression.*`), in
the Phase 7–8 order, starting from the installation defaults:

| Suite | Before (Phase 7–8) | Now |
|---|---|---|
| Realtime + Customer 360 (real WooCommerce deliveries) | 41/41 | **41/41** |
| Shopify (simulated) | 64/64 | **64/64** |
| Zid (simulated) | 49/49 | **49/49** |
| WooCommerce (real, Phase 2) | 41/41 | **41/41** |
| Salla (simulated) | 47/47 | **47/47** |
| WhatsApp harnesses on the migrated rehearsal database: existing numbers / WhatsApp Business coexistence / Lynomia (billing, mobile auth, branding) | 41/41, 54/54, 17/17 | **41/41, 54/54, 17/17** |
| Enterprise RSpec (4 shards, `rspec_enterprise.txt`) | 10,165 examples, 1 failure | **10,293 examples, 1 failure**: the same OpenSearch-dependent voice transcription example (`Message#reindex` needs OpenSearch), unrelated |
| Community RSpec (no `enterprise/`, `rspec_community.txt`) | 7,464, 0 failures | **7,589, 0 failures** |
| Vitest (`vitest.txt`) | 4,733 | **4,745 passed** |
| ESLint (`eslint.txt`) | 0 errors, 444 warnings | **0 errors, 444 warnings** (a 445th, a bare `#` in the new review, was fixed) |
| RuboCop (`rubocop.txt`) | 54 offenses, all in files identical to v4.18.0 | **54**, the same files; none in Commerce code |

**Migration down/up** (throwaway database, `migration_rollback_rehearsal.txt`): `db:migrate:down VERSION=20261001100000`
drops only `commerce_action_runs` (107 → 106 tables); `db:migrate` restores it. The rollback itself does not use it
(doc 28 §11).

**Performance** (`actions_performance.txt`, the recorded run's server and worker logs; WooCommerce real, the others
in-process):

| Request | n | p50 | p95 |
|---|---|---|---|
| Open the actions dialog (reads the order from the store now) | 31 | 333 ms | 408 ms |
| Confirm an action (validate, record, queue) | 31 | 33 ms | 134 ms |
| Dialog polling of the run | 58 | 15 ms | 21 ms |
| Conversation abandoned carts (all stores, concurrently) | 41 | 89 ms | 232 ms |
| Prepare a recovery message (reads the cart again) | 6 | 51 ms | 83 ms |
| Administrators' cart queue | 10 | 94 ms | 299 ms |
| `Commerce::ActionJob` (re-read, version check, one write, read back) | 21 | 0.50 s | 0.76 s (max 25.5 s: the timeout case) |

## 4. What the runs found

Five full runs before the recorded one. Product changes they led to (both in this commit series, both covered by specs):

- **Lynomia's own rate limit was worded as the store's.** A sixth request on one order within 10 minutes is refused with
  429; the dialog said "The store is limiting requests", which is wrong: nothing reached the store. It now says "Too many
  actions were requested on this order. Try again in {seconds} s." (`CommerceOrderActions.vue`, Vitest case added).
- **Arabic double period.** The Arabic SAR symbol "ر.س." ends with a period, so two sentences ending with an amount
  rendered "ر.س..". Both Arabic strings were rephrased.

Behavior confirmed rather than changed:

- **Cash on delivery.** WooCommerce leaves a cash-on-delivery order in processing without a payment date (the cash is
  collected on delivery), so Lynomia offers no refund for it: "The order isn’t paid." Recorded-only refunds are therefore
  tested on a paid bank-transfer order (doc 29 §2).
- **Idempotent replays count toward the per-order limit.** Replaying a key answers the same run, but the request still
  counts (5 per order per 10 minutes). Deliberately conservative; the dialog never replays on its own.
- **A second request while one is unresolved** is refused with `ACTION_IN_PROGRESS` before any rate-limit slot matters:
  the rate-limit check shows 202, then 422 ×4, then 429.

Harness corrections (not product): orders checked in the dialog are created last (the panel shows a customer's latest 5
orders); the reply box's "Send (Ctrl + ↵)" button is targeted precisely (the panel has a "Send tracking" button); the
simulated WhatsApp send log is cleared by `ctl.rb reset`; the dialog is closed with Escape where it has no Close button.

## 5. Screenshots

`screenshots/phase9/`:

| File | |
|---|---|
| `a01-settings-capabilities-en` | Read/Write store: Read-only Commerce, live updates, order actions off; Read-key store: "Order actions require a Read/Write WooCommerce API key." |
| `a02-settings-actions-on-en` | after the administrator opts in; Zid and Shopify held back ("switched off on this installation") |
| `a03-actions-menu-en` | the ••• dialog of a paid WooCommerce order: what is possible and why the rest is not |
| `a04-status-review-en` | status change review: store, provider, order, change |
| `a05-refund-review-en` | refund review: amount and currency, the gateway, "This can’t be undone" |
| `a06-refund-unknown-en` | the gateway's answer lost: "The store didn’t answer in time … don’t try again" |
| `a07-refund-review-ar` | the refund review in Arabic (recorded-only refund), right to left |
| `a08-mobile-ar`, `a09-mobile-en` | the conversation at 390 px |
| `s01-settings-pre-uat-override-en` | staging override: Zid opt-in, Shopify "Additional Shopify permissions are required …" with Reconnect for order actions |
| `s02-carts-en` | Customer 360 abandoned carts (Salla, Zid, Shopify) |
| `s03-recovery-prepared-en` | the prepared message in the reply box, "prepared …, not sent yet" |
| `s04-recovery-sent-cooldown-en` | the message sent by the agent |
| `s05-window-closed-en` | outside the 24-hour window: nothing prepared, the reason shown |
| `s06-cart-queue-en` | the administrators' queue: linked contacts first, sent state, no contact details |
| `s07-carts-ar`, `s08-carts-mobile-ar` | carts in Arabic, desktop and 390 px |

## 6. Reproduce

```
bin/vite build --force                       # production assets (erun.sh, RAILS_ENV=production)
docs/commerce/e2e/actions/run.sh <out_dir> <scratch_dir>
```

`run.sh` installs the test-only plugins in the test store, creates the Read/Write key, runs the gate phase, restarts the
server and worker with the pre-UAT override for the sim phase, copies the logs and restores the test store (orders,
webhooks, gateway).
