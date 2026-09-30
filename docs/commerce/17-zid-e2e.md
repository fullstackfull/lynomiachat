# Lynomia Commerce: Zid E2E and regression (Phase 4)

**`REAL_ZID_UAT = BLOCKED`.** No real Zid store could be used:
- this environment's egress proxy refuses `oauth.zid.sa`, `api.zid.sa` and every Zid documentation host;
- there is no Zid Partner account or test store.

The E2E below runs the real Lynomia application against a **simulated Zid** built from Zid's documented shapes. It proves Lynomia's side of the contract. It does **not** prove Zid's side (§6), and nothing here claims production readiness.

## 1. What is real and what is simulated

| Real | Simulated |
|---|---|
| Lynomia production build (Rails 7 / Puma, Vite production assets), Postgres, Redis, Sidekiq queueing | Zid's hosts `oauth.zid.sa`, `api.zid.sa`: answered in-process by `docs/commerce/e2e/zid/zid_sim.rb` (WebMock) inside the Lynomia server and the job runner |
| OAuth start endpoint, state issue and consumption, cookie binding, callback, server-side code exchange, profile verification, encrypted storage | Zid's authorization page: Playwright answers `https://oauth.zid.sa/oauth/authorize` with Zid's redirect to the registered callback (`?code=…&state=…`, or `?error=access_denied`) |
| Token manager (lock, refresh, needs_reauth), provider, normalizer, matcher, cache, panel, settings UI, Super Admin | Zid's token, profile, orders and webhooks answers: shapes from Zid's official skill (token) and official SDK (profile, orders fixtures, webhooks), stateful in Redis (`E2E::ZIDSIM::*`: single-use codes, issued tokens, revocations, subscriptions and the Basic Auth pair Lynomia registered, request counters) |
| Webhook endpoint with Basic Auth over HTTP, deduplication, encrypted queueing, the webhook job | Zid delivering a webhook: sent from the E2E with the pair Lynomia registered at the simulated Zid, as Zid would |
| WooCommerce stores (real WooCommerce 10.9.4 in Docker) and Salla stores in the same account | |

- **How the server runs.** `bundle exec rails runner docs/commerce/e2e/zid/server.rb` boots the app in production mode, installs `ZidSim` (WebMock, only Zid's two hosts; every other host untouched) and serves it with Puma on port 3100.
- **Nothing in the app is changed for the E2E.** No DNS or TLS interception is used, and the browser never talks to a fake Zid host except Playwright's answer for the authorization page.

Files:
- `docs/commerce/e2e/zid/zid_sim.rb` (the simulated Zid);
- `server.rb` (E2E server);
- `sim.rb` (runner controls: configure, reset, jobs, Zid-side view, refresh mode, revoke, order change, cache age, state);
- `e2e_zid.js` (Playwright, 49 checks).
- Results: `docs/commerce/e2e/results/zid_e2e_results.json`, `zid_e2e_run.txt`.
- Screenshots: `docs/commerce/screenshots/zid/`.

## 2. Result: 49/49 passed

| # | Check | Result |
|---|---|---|
| 1 | Super Admin: Enable Zid, Client ID, masked empty Client Secret, no merchant-token field | PASS |
| 2–3 | Add store offers WooCommerce, Salla and Zid; Connect with Zid asks for nothing secret | PASS |
| 4 | Browser sent to `oauth.zid.sa/oauth/authorize` with client_id, the registered callback, `response_type=code`, a state; no secret in the URL | PASS |
| 5–8 | Back in Settings → Commerce (`zid=connected`): store connected to account A with Zid store id, name, URL, time zone; one server-side code exchange; credentials exactly `authorization, access_token, refresh_token, token_type, expires_at`; list shows name, Zid, Active | PASS |
| 9–11 | Registration queued; Zid holds 3 order subscriptions to `/webhooks/zid/318001` with a 32-char username and 64-char password; pair stored encrypted, 3 subscription ids in metadata | PASS |
| 12–17 | **State security**: replayed callback, forged state, valid state from another (agent's) browser → nothing exchanged or saved; agent cannot start (401); merchant declines → `zid_error=AUTH_INVALID`; account B authorizing A's store → `zid_error=STORE_ALREADY_CONNECTED`, store stays with A | PASS |
| 18–19 | **Multi-store**: a second Zid store in the same account; one conversation lists WooCommerce, Salla and both Zid stores | PASS |
| 20–24 | **Panel**: verified-WhatsApp-phone auto-link, newest first; in-delivery order Shipped + Paid + courier + In transit + Track shipment + Send tracking; new → Processing + Unpaid, reversed → Other + Payment not confirmed; https tracking link; Send tracking fills the reply box | PASS |
| 25 | **Marketplace**: an order found by Layla's phone comes back masked → never matched, never linked | PASS |
| 26–29 | **Webhooks**: no credentials, wrong username, wrong password, another store's pair, Bearer → 401 and nothing queued; correct pair → 200; replay acknowledged but queued once; the job drops the cached orders and the panel shows Zid's new status at once | PASS |
| 30 | 10 concurrent readers of expiring tokens → one refresh request, one set of new tokens | PASS |
| 31–33 | Zid refuses the refresh token → needs_reauth, tokens removed, nothing stale shown; settings explain and offer Reconnect; store not offered in conversations | PASS |
| 34–35 | Reconnect re-authorizes the same store in place; re-registration keeps 3 subscriptions, rotates the pair, old pair refused | PASS |
| 36 | Authorization revoked in Zid (uninstall) → needs_reauth, nothing stale shown | PASS |
| 37–38 | **Disconnect**: Zid subscriptions deleted, tokens, webhook pair, links and cache removed; contacts and conversations unchanged; deliveries refused afterwards | PASS |
| 39–41 | Zid off: stores kept and explained, no Zid in Add store, `PROVIDER_DISABLED` | PASS |
| 42 | Commerce off for the account: no Commerce in settings, no Zid authorization (401) | PASS |
| 43–44 | Arabic picker and dialog (زد, الربط مع زد); mobile dialog fits the screen | PASS |
| 45–46 | Audit: `commerce.zid.connected`, `token_refreshed`, `needs_reauth`, `reauthorized`, `commerce.store_disconnected`; no token, code or secret in audit entries | PASS |
| 47–49 | No Zid token, code, client secret or webhook password in any of the 654 app and API responses; none of them, nor any OAuth state, in the server or job logs; no uncaught page errors | PASS |

The first run ended 46/49. None of the three failures touched security or tenancy, and all were fixed before the passing run:
1. **Order card and courier.** The card showed Zid's delivery-option name but not the courier. The shipping line now names the courier when there is one, as Salla's names its carriers.
2. **Leak scan.** It also scanned the built JavaScript bundle, which contains the word `"credentials"`. It now scans app and API responses, like the Salla E2E.
3. **Unhandled 401.** Opening Settings → Commerce directly while the account's Commerce is off left the stores request's 401 unhandled. It is now caught and shown.

## 3. Screenshots (`docs/commerce/screenshots/zid/`)

| File | Shows |
|---|---|
| `zid-01-super-admin.png` | Super Admin → Zid |
| `zid-02-provider-picker.png` | Add store: WooCommerce, Salla, Zid |
| `zid-03-connect-dialog.png` | Connect with Zid |
| `zid-04-connected.png` | Store connected |
| `zid-05-already-connected.png` | Account B: store already connected |
| `zid-06-settings-all-providers.png` | WooCommerce, Salla and two Zid stores in one account |
| `zid-07-panel-orders.png` | Panel: linked customer, orders, courier, tracking |
| `zid-08-marketplace-not-linked.png` | Marketplace buyer not linked |
| `zid-09-after-webhook.png` | Status updated right after the order webhook |
| `zid-10-needs-reauth.png` | Needs re-authorization + Reconnect |
| `zid-11-disconnect-confirm.png` | Disconnect confirmation |
| `zid-12-provider-off.png` | Zid switched off |
| `zid-13-picker-arabic.png`, `zid-14-connect-dialog-arabic.png` | Arabic |
| `zid-15-mobile-connect-dialog.png` | Mobile |

## 4. Regression

**End-to-end** (production build of HEAD `3f25d97e2`, all three run in sequence; results in `docs/commerce/e2e/results/`):

| E2E | Result | Notes |
|---|---|---|
| Zid (simulated Zid) | **49/49** | `zid_e2e_results.json` |
| WooCommerce (real WooCommerce 10.9.4 stores) | **41/41** | `woocommerce_regression_phase4.json`; plain `rails s` server, Zid switched off |
| Salla (simulated Salla) | **47/47** | `salla_regression_phase4.json`; same server, Zid switched off |

- **Why Zid is switched off for them.** The WooCommerce and Salla E2Es were written for installations without Zid: Add store goes straight to WooCommerce's form, and Salla's "provider off" check expects WooCommerce alone. With Zid on, Add store opens the provider picker instead, which the Zid E2E covers.
- **Sessions cleared between runs.** An earlier Salla run on `26adfba0e` stopped after 32 passing checks at a mobile login, answered by upstream 4.18's concurrent-session limit (`MAX_USER_SESSIONS`, the session picker, `409`). `agent_a` had 25 live sessions from the day's E2E logins. The final runs end the E2E users' sessions before each E2E (§5 step 7), and all three passed on the first attempt. This is test-environment state, not a product change.
- WhatsApp and واتساب بزنس are unchanged: the Zid work touches no channel code, and the full suites below include the WhatsApp specs.
- With Commerce off for an account there is no Commerce UI (Zid E2E check 42; WooCommerce E2E "feature off" checks).

**Full suites.**
- RSpec ran on HEAD `822680830`. Its code is identical to `26adfba0e`; `3f25d97e2` changes only Vue text lookups, covered by Vitest and ESLint below.
- Test assets were built once per tree before any spec ran (`bin/vite build --force`):
  - Enterprise 16:44:10, Community 16:45:18, both digest `ed0e519c`;
  - both timestamps were unchanged after the run;
  - every shard ran with `VITE_RUBY_AUTO_BUILD=false`, 4 shards per tree.

| Suite | Examples | Failures | Pending | Phase 3 |
|---|---|---|---|---|
| Enterprise | 9957 | 1 | 67 | 9868 / 1 / 67 |
| Community | 7256 | 1 | 69 | 7167 / 2 / 69 |
| Vitest | 456 files, 4709 tests | 0 | | 455 files, 4704 tests |
| ESLint (`app/**/*.{js,vue}`) | | 0 errors | | no Commerce warnings (after `3f25d97e2`) |

- The two suites grew by the Phase 4 specs (89 examples each). **No failure comes from Commerce, Salla, Zid or Lynomia.** The two failures are the specs classified UPSTREAM in doc 13 §5, with the same evidence:
  - `spec/enterprise/services/voice/call_transcription_service_spec.rb:77`: `Message` gains `reindex` only with `OPENSEARCH_URL`; it fails identically on clean `v4.18.0`.
  - `spec/models/conversation_spec.rb:1144`: a 1-second tolerance across inline jobs; it fails intermittently on clean `v4.18.0`. `:1172`, its twin, passed this time.
- The Phase 4 specs are:
  - Zid: config, OAuth state, tokens, token manager, provider, webhooks, webhook job, connection API, callback, webhook controller, panel, Super Admin, HTTP client;
  - Salla and WooCommerce specs: unchanged and green, including after the shared `StoreLock` and `Backoff` extraction.

## 5. How to run

1. `docs/commerce/e2e/e2e.env` (from `e2e.env.example`, with `E2E_ZID_CLIENT_SECRET`).
2. Seed data: `docs/commerce/e2e/rails/seed.rb`.
3. Production assets: `erun.sh "bin/vite build --force"`.
4. Server: `bundle exec rails runner docs/commerce/e2e/zid/server.rb` on port 3100.
5. `ERUN=… CHROMIUM_PATH=… node docs/commerce/e2e/zid/e2e_zid.js <out>`.
6. The WooCommerce and Salla E2Es run on the plain `rails s` server with Zid switched off (`sim.rb configure off`), since they were written for installations where Add store goes straight to the only provider's form.
7. Before each E2E, end the E2E users' sessions (`User#tokens` and `user_sessions`). Upstream's concurrent-session limit otherwise answers logins with its session picker after many runs.

## 6. `REAL_ZID_UAT = BLOCKED`: what the real UAT must confirm

- **Blocker:** no network path to Zid from this environment, and no Zid Partner account or test store.
- **Needed:**
  1. a Zid Partner app with the scopes of doc 14 §6 and the callback `<FRONTEND_URL>/commerce/zid/callback`;
  2. `ZID_CLIENT_ID` and `ZID_CLIENT_SECRET` in Super Admin;
  3. a Zid test store;
  4. a Lynomia staging URL reachable from Zid (webhooks).

Run in order. Stop at the first mismatch and report it; do not work around it in code without re-review.

1. **State round-trip.** Zid returns `state` unchanged on the callback (doc 14 §8.1). If it does not, every callback is refused (fail-closed) → STOP condition 1.
2. **Token response.** Field names and `expires_in` type (doc 14 §8.2). Check that the stored credential keys equal E2E check 7.
3. **Profile.** `user.store.id/title/url/timezone` (doc 14 §8.4).
4. **Webhook Basic Auth field.** Subscribe, then confirm Zid delivers `Authorization: Basic` with the registered pair (doc 15 §8.1). If Zid rejects `authentication`, find the documented field and change `Commerce::Zid::Webhooks#subscription` only. If Zid cannot send per-webhook credentials at all → STOP condition 4.
5. **`order.payment_status.update`** is accepted as an event (doc 15 §8.2).
6. **Orders.**
   - `search_term` with a national number finds a customer stored as `9665…` (doc 16 §11.1).
   - `customer_id` filter and `sort_by=desc` behave as documented.
   - Order times are in the store's time zone.
7. **Marketplace order.** Masked fields as documented; Lynomia shows "Customer not found" for its buyer.
8. **Refresh.** Force a refresh (set `expires_at` within 60 days); confirm new tokens work. Reuse the old refresh token once, from a console, and record Zid's answer (doc 14 §8.3). Single-use → the design already handles it (never sent twice); no code change expected.
9. **Uninstall** the app in Zid → next panel read shows "needs re-authorization", Reconnect works.
10. **Disconnect** in Lynomia → `GET /managers/webhooks` in Zid shows no Lynomia subscription.

## 7. Known limitations

- **Real Zid unverified.** The items of §6 have not been checked against a live store.
- **No lifecycle webhook.** The app lifecycle webhook (`app.market.application.uninstall`) is not subscribed. An uninstall is detected on the next read (401 → refresh refused → needs_reauth), not pushed.
- **No background refresh sweep.** Tokens are refreshed on use, 60 days before expiry. A store unused for about 10 months can lapse, and then asks for Reconnect.
- **No Zid admin link.** Zid documents no merchant-dashboard order URL, so the order card has no "View order".
- **Coarse shipment status.** A shipment's status comes only from the order's delivery statuses (in delivery / delivered); Zid's own shipment status text is kept but has no documented vocabulary.
- **Customers come from orders.** A Zid customer with no orders is not found automatically. They have nothing to show either, and manual search reads the same orders.
- **App Market installs.** An install started from the Zid App Market, not from Lynomia, cannot be attached to an account and is refused (doc 14 §2).
- **Webhooks are optional.** If Zid rejects the subscription or the Basic Auth field, the store still works: cached orders refresh after 120 s.
