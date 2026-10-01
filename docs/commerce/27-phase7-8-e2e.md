# Lynomia Commerce: Phase 7–8 E2E (Customer 360 and realtime)

How Customer 360 and live updates were tested end to end, what passed, what was measured, and what the runs found.
Architecture: [24](24-realtime-architecture.md). Product behavior: [25](25-customer-360.md). Security:
[26](26-realtime-security.md).

## 1. Environment

| | |
|---|---|
| Code | working tree at the Phase 7–8 head, production mode (`RAILS_ENV=production`, production Vite build) |
| Runtime | `lynomia/verify:base` (Ruby 3.4.4, Node 24), Postgres 16, Redis 7 |
| Processes | web server (Puma) plus a **Sidekiq worker**, as in production. ActionCable over Redis (the existing `cable.yml`) |
| Browser | Playwright + Chromium; agent A, administrator A, administrator B (another account), and a 390 px mobile agent |
| WooCommerce | **real** WooCommerce 10.9.4 (HPOS) in Docker: store A1 with a **Read/Write** key (live updates), store A2 with a **Read** key |
| Salla, Zid, Shopify | simulated in-process (WebMock) in the server, the worker and the control runner, from documented shapes. Their hosts are not reachable from this environment |

**Harness** (`docs/commerce/e2e/realtime/`):

- `sims.rb`: the Zid and Shopify simulators of the provider E2Es, plus a Salla simulator whose orders can change. Each
  can be switched to an outage (503).
- `server.rb`, `worker.rb`: the app and Sidekiq with the simulators installed.
- `ctl.rb`: store-side actions. It changes an order in a simulated store, then delivers the event **authenticated as
  that provider does**:
  - Salla: HMAC with the app's webhook secret;
  - Zid: the Basic Auth pair Lynomia registered with the simulated Zid;
  - Shopify: HMAC with the app's client secret.
  It also replays, bursts, outages, revokes access, flips the kill switch, and prints the run's credentials for the leak
  scan.
- `e2e_realtime.js`: the browser run. `run.sh` starts everything.

**WooCommerce deliveries are WooCommerce's own.** The store signs them with the secret Lynomia gave it and sends them
from its Action Scheduler queue. Two test-only aids, neither of which touches Lynomia:

- the queue is run with wp-cli (`action-scheduler run`) instead of waiting for WP-Cron;
- a must-use plugin in the test store (`woocommerce/lynomia-e2e-delivery.php`) points deliveries addressed to
  `http://localhost:3100` at the container network's gateway, and lets WordPress's safe HTTP call that private
  address. On a live site Lynomia's `FRONTEND_URL` is a public HTTPS URL and neither is needed.

## 2. Realtime + Customer 360 E2E: **41/41 passed**

Results: `e2e/results/phase7/realtime_e2e_results.json` and `realtime_e2e_run.txt`. Screenshots: `screenshots/phase7/`.

| # | Check | |
|---|---|---|
| 1 | Read/Write key: Lynomia registers its webhooks, settings say live updates are on | PASS |
| 2 | Read key: store connected and active, live updates off with the reason | PASS |
| 3 | WooCommerce holds one active "Lynomia Commerce" webhook per order topic, to this store's URL | PASS |
| 4 | WooCommerce's unsigned creation pings were refused | PASS |
| 5 | Salla, Zid and Shopify stores connected to account A | PASS |
| 6 | First visit, contact not linked anywhere yet: the store view opens | PASS |
| 7 | Overview opens first for a contact linked in several stores | PASS |
| 8 | Customer 360: linked in one store of each provider; the store without the customer says "Customer not linked" | PASS |
| 9 | Figures: 5 connected · 4 linked, visible orders (not lifetime), last purchase, no partial banner | PASS |
| 10 | Spend per currency, never converted into one figure | PASS |
| 11 | Latest orders across stores: at most 10, each naming its store and provider | PASS |
| 12 | No LTV, average order value or predictions | PASS |
| 13–15 | **WooCommerce (real)**: order #23 pending → processing in the store; the open store view shows it live, without a reload; delivery signed by the store, accepted, applied | PASS |
| 16 | Zid: order status and payment change shown live | PASS |
| 17 | Shopify: payment and fulfillment change shown live | PASS |
| 18 | Salla: order status change shown live | PASS |
| 19 | WooCommerce (real): a new order of the same guest appears live | PASS |
| 20 | A replayed Zid delivery is acknowledged and not applied again | PASS |
| 21 | A replayed Shopify delivery (same `X-Shopify-Webhook-Id`) is acknowledged once | PASS |
| 22 | A burst of 10 Zid events for one customer: all applied, **2** store reads, 9 coalesced | PASS |
| 23 | An out-of-order Shopify event claiming an older state changes nothing: the store is read again | PASS |
| 24 | Salla outage during an event: the last orders stay, marked stale with their time | PASS |
| 25 | Shopify access revoked: live "needs re-authorization", none of its orders remain | PASS |
| 26 | `COMMERCE_REALTIME_ENABLED=false`: no live update | PASS |
| 27 | Manual Refresh reads the store again even though its cache was fresh | PASS |
| 28 | A second Refresh within the cooldown is refused with the wait ("Try again in 30 s") | PASS |
| 29 | WooCommerce (real) `order.deleted` names no customer: store-level invalidation, nobody refreshed | PASS |
| 30 | After it, the next read no longer shows the trashed order | PASS |
| 31 | Order search across stores: WooCommerce #24 found, Salla "not searchable", no Send tracking | PASS |
| 32 | Unlinked store stays unlinked: the verified match is offered, not linked again | PASS |
| 33 | The agent can link the customer again by hand | PASS |
| 34 | Arabic: Customer 360 in Arabic, right to left | PASS |
| 35 | Mobile (390 px): the conversation and its Commerce section render | PASS |
| 36 | Agents of account A received `commerce.customer.updated` over the existing ActionCable connection (11 frames) | PASS |
| 37 | Each event carries ids only: account, contact, store, time | PASS |
| 38 | Account B received no commerce event of account A (0 frames) | PASS |
| 39 | Disconnecting removes Lynomia's webhooks from WooCommerce | PASS |
| 40 | No credential, webhook secret or token in logs, API responses or socket frames (20 secrets scanned) | PASS |
| 41 | No page errors | PASS |

### 2.1 WooCommerce real realtime chain (point 45)

Every step was observed on the real store and app:

1. **Webhook.** WooCommerce queues the delivery.
2. **Signature.** `X-WC-Webhook-Signature` is verified with the store's secret (accepted).
3. **Dedup.** The delivery id is new.
4. **Invalidate.** The guest's orders are marked outdated (`webhook.applied customers=2`: the order's email and phone
   identities).
5. **Refresh.** `RefreshJob` reads the orders.
6. **Realtime.** `commerce.customer.updated` is sent to `account_1`.
7. **Panel.** It refetches, and the card changes from "Pending payment · Unpaid" to "Processing · Paid".

The page is the same document throughout (a marker set before the change survives).

### 2.2 Simulated providers (point 46): coverage

| Scenario | Salla | Zid | Shopify | Where else |
|---|---|---|---|---|
| Order status change, live | E2E 18 | E2E 16 | — | provider job specs |
| Payment change, live | — | E2E 16 (paid) | E2E 17 (PAID) | |
| Shipment / fulfillment change, live | — | — | E2E 17 (FULFILLED → Shipped) | |
| Duplicate delivery | RSpec (security spec) | E2E 20 | E2E 21 | security spec, all four |
| Out-of-order event | — | — | E2E 23 | provider-neutral: a refresh always reads the store (`realtime_spec`) |
| Provider outage | E2E 24 | — | — | `overviews_controller_spec`, `realtime_spec` (stale fallback) |
| Access revoked | — | RSpec (security spec) | E2E 25 | `overviews_controller_spec` (Zid) |
| Coalesced burst | — | E2E 22 | — | `realtime_spec` |
| Live refresh in the browser | E2E 18 | E2E 16 | E2E 17 | |

Each provider runs every scenario through the same provider-neutral path (doc 24). The browser run exercises each
scenario on at least one provider, and the RSpec suites cover the rest per provider.

### 2.3 Cross-provider Customer 360 (point 47)

One WhatsApp contact (Omar) is linked in a WooCommerce, a Salla, a Zid and a Shopify store, and has no customer in a
second WooCommerce store. Checks 7–12 show:

- 5 stores, 4 linked;
- 16 visible orders, 9 active · 3 shipped;
- spend SAR 843.56, paid orders only, one currency;
- the 10 newest orders from all four providers, each card naming its store;
- per-store identity (guest or registered, match source) and freshness.

The RSpec gate (`overviews_controller_spec.rb`, 10 examples) checks the same aggregate exactly, plus mixed currencies
(SAR + USD kept apart), partial outage, timeout and provider switch.

### 2.4 Multi-tenant (point 49)

- **E2E.** Administrator B's dashboard (account 2) stayed open for the whole run and received **0**
  `commerce.customer.updated` frames, while account A's agent received 11.
- **RSpec.**
  - Another account's agent cannot subscribe to account A's stream (`room_channel_commerce_spec.rb`).
  - A delivery authenticated for one store cannot act on another store, in either account.
  - Another account linking the same store customer id is never refreshed or told
    (`commerce_realtime_security_spec.rb`).
  - Every conversation endpoint refuses other accounts (`overviews`, `refreshes`, `orders` controller specs).

## 3. Measurements (points 37–39)

From the final run (`e2e/results/phase7/realtime_measurements.json`, `panel_api_calls.txt`):

| Measure | Result |
|---|---|
| Live update, delivery → agent's screen (simulated stores) | Zid **665 ms**, Shopify **690 ms**, Salla **951 ms** |
| Live update, store change → agent's screen (real WooCommerce) | 7.6 s, of which ≈ 6–7 s is WooCommerce's queue and wp-cli runs; Lynomia's part is under 1 s as above |
| Customer 360 server time (5 stores) | p50 **41 ms**, p95 **365 ms** (the cold first open) |
| Overview, browser reload to panel rendered | p50 2.1 s, p95 2.2 s (whole dashboard reload) |
| Provider calls per open | first (cold) overview: 12 for 5 stores (customer discovery + orders); warm overview: **0**; after the 120 s freshness: ≤ 7; store views: 28 of 34 opens made 0 calls |
| Cache hit ratio over the run | **0.80** (76 hits / 19 misses) |
| Webhooks | 21 accepted, 7 rejected (WooCommerce's 3 creation pings + simulated failures), 2 duplicates |
| Coalescing | 10 coalesced events in the run; a burst of 10 → 2 reads |
| Provider errors | 1 (the revoked Shopify token, by design) |

**Before vs after (found by these runs).**

- **Latency.** Delaying every refresh by 2 s through Sidekiq's scheduled set gave 5.5–7 s. Refreshing at once on the
  first event gives 0.7–1 s (same coalescing).
- **Outage.** Deleting the cache on an event left nothing to show during an outage. Marking it outdated keeps the stale
  fallback (check 24).

## 4. Regression (point 51)

| Suite | Result |
|---|---|
| WooCommerce E2E (real stores) | **41/41** |
| Salla E2E (simulated) | **47/47** |
| Zid E2E (simulated) | **49/49** |
| Shopify E2E (simulated) | **64/64** |
| Realtime + Customer 360 E2E | **41/41** |
| WhatsApp harnesses on this code (rehearsal database, doc 23 §8) | existing numbers **41/41**, WhatsApp Business coexistence **54/54**, Lynomia **17/17** |
| Commerce and Shopify specs within the Enterprise run (74 files) | **715 examples, 0 failures** |
| Backend RSpec, Enterprise (how Lynomia runs), 4 shards | **10,165 examples, 1 failure, 67 pending**: `call_transcription_service_spec.rb:77`, the known OpenSearch-dependent spec that fails identically on clean upstream `v4.18.0` (doc 23 §8.1) |
| Backend RSpec, Community (`enterprise/` removed), 4 shards | **7,464 examples, 0 failures, 70 pending** |
| Frontend Vitest | **459 files, 4,733 tests, all passed** |
| ESLint | **0 errors**, 444 warnings (same count as Phase 6; none in Commerce files) |
| RuboCop (repo config) | 3,242 files, 54 offenses, all in the same 9 upstream files byte-identical to `v4.18.0` as in Phase 6; 0 in Lynomia files |

**One harness change in the provider E2Es.** The Commerce section now opens on Customer 360 for a contact linked in
several stores (doc 25 §11). The four provider E2Es check the store view, so each now saves "store" as the agent's view
choice in the browser before loading pages (one init script in `newPage`). Nothing else in them changed. The first
rerun showed that the script threw on documents without storage (`about:blank`, the OAuth pages), which those E2Es
report as page errors: Shopify 63/64 and Zid 48/49, the failing check being "no uncaught page errors" in both. With
the script guarded (try/catch), the reruns passed 64/64 and 49/49. Results: `e2e/results/phase7/*_regression.*`.

Raw summaries: `e2e/results/phase7/` (`rspec_enterprise.txt`, `rspec_community.txt`, `vitest.txt`, `eslint.txt`,
`rubocop.txt`, `whatsapp_harnesses.txt`).

These existing paths have no code change in Phase 7–8 and are covered by the full suites above:

- WhatsApp and WhatsApp Business: inbox, webhooks and coexistence specs;
- conversations and contacts: the core suites; the conversation panel only gained a prop;
- legacy Shopify: untouched, its specs pass;
- billing: no new feature; `lynomia_commerce` unchanged.

## 5. Screenshots (`screenshots/phase7/`)

| File | Shows |
|---|---|
| `01-settings-realtime-status.png` | Settings: "Live order updates on" (Read/Write key) and the read-only explanation |
| `02-customer360-en.png` | Customer 360 in English: figures, recent orders with stores, stores with identity and freshness |
| `03-live-woocommerce-real.png`, `03-live-zid.png` | Store view right after a live update |
| `04-outage-stale-salla.png` | Outage: last orders kept, "Couldn't refresh store data right now. Last updated …" |
| `06-overview-shopify-revoked.png` | Revoked store: "Store needs re-authorization", no orders from it |
| `07-refresh-cooldown.png` | Refresh cooldown notice |
| `08-order-search.png` | Order search across stores |
| `09-customer360-ar.png` | Customer 360 in Arabic (RTL) |
| `10-customer360-mobile-ar.png`, `11-customer360-mobile-en.png` | Mobile, 390 px |

## 6. Known limitations

- **Salla, Zid and Shopify realtime are simulated.** Their hosts are unreachable here. The Salla store-event payload
  shape stays **KEEP VERIFY** (doc 23). All three stay **off in production**.
- **WooCommerce needs a Read/Write key for live updates.** WooCommerce has no read-only way to create webhooks. With a
  Read key the store works as before (cache + Refresh) and says so in Settings.
- **WooCommerce delivery timing is WooCommerce's.** It delivers from Action Scheduler: on a low-traffic store, WP-Cron
  can delay a delivery by up to about a minute.
- **WooCommerce `order.deleted` fires on trash only**, and its body is `{id}` only. A permanent delete without trashing
  sends nothing, and a trashed order is caught at store level (no live push; the next read or Refresh shows it).
- **Order search by number.**
  - WooCommerce stores that renumber orders with a plugin are not found by number.
  - Zid's number is its order id (Z15 still VERIFY).
  - Salla has no search.
- **Within-account event audience.** Within an account, every agent's browser gets the ids-only event, even for
  conversations they cannot open. The refetch is refused (doc 26 §6).
