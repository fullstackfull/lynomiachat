# 13 — Salla: end-to-end run, and why the real UAT is blocked

**Run date:** 2026-09-30.

## `REAL_SALLA_UAT = BLOCKED`

A real Salla UAT needs three things, and this environment has none of them:

1. **Network access to Salla.** The environment's egress proxy refuses every Salla host:

   ```text
   $ curl -sS https://accounts.salla.sa/
   curl: (56) CONNECT tunnel failed, response 403
   ```

   The same answer comes back for `api.salla.dev`, `accounts.salla.sa`, `s.salla.sa`, `docs.salla.dev`,
   `salla.partners`, `portal.salla.partners` and `partners.mcp.salla.dev`.
2. **A Salla Partner account** with the Lynomia app created in it: App ID, Client ID, Client Secret, Webhook Secret,
   Easy Mode, scopes, and the settings field from doc 10.
3. **A Salla demo store** to install the app on, with customers, orders and shipments, and a public HTTPS URL for
   `/webhooks/salla` that Salla can reach.

Nothing in this phase claims production readiness against live Salla. §4 is the checklist for the real run.

## 1. What ran instead: a simulated-Salla E2E

**Real parts:**

- the Lynomia app in production mode (the same image and Vite production build as doc 09);
- Postgres, Redis and the Sidekiq queue;
- the `/webhooks/salla` endpoint over HTTP, with signature checks, dedup and encrypted queueing;
- the settings UI, the conversation panel and the browser (Playwright + Chromium);
- the three real WooCommerce stores from doc 09, next to Salla.

**Simulated parts:**

- **Salla's events.** Built from Salla's documented payloads (`spec/fixtures/files/commerce/salla`) and signed exactly
  as Salla signs them: hex HMAC-SHA256 of the raw body with the installation's webhook secret.
- **Salla's HTTP answers** (`user/info`, token refresh, customers, orders, shipments). `docs/commerce/e2e/salla/sim.rb`
  answers them with WebMock, from the same documented shapes. That runner also runs the queued webhook jobs, since the
  test environment has no Sidekiq worker process; the job code is unchanged.

Nothing redirects or intercepts traffic to Salla's real hosts. When the panel's cache runs out, it does call Salla for
real, and this sandbox refuses the call (403). Check 22 uses exactly that.

## 2. Results

**Salla E2E (`e2e/salla/e2e_salla.js`): 47/47 passed** on the final build.

- Log: `e2e/results/salla_e2e_run.txt`
- Machine-readable: `e2e/results/salla_e2e_results.json`

The first run on this build passed 44 of 47. The three failures were diagnosed before the final run:

1. **Super Admin sign-in (harness).** The sign-in page's own URL already matched the harness's wait, so it never
   logged in. The harness now waits to leave the sign-in page.
2. **Not-found check (harness).** The "Link customer" button is uppercased by CSS, so the text match is now
   case-insensitive.
3. **Stale-data check (environment).** The run expected a network failure, but this sandbox's egress answers every
   request to `api.salla.dev` with `403 Host not in allowlist`. The panel treats that like any 403: it shows the
   error and presents no orders as current. The check now asserts exactly that.
   - The stale-data fallback is exercised through Salla's rate-limit path instead (check 23).
   - Serving stale data on network failures is provider-independent. It is covered by `cache_spec.rb` and by the
     WooCommerce store-down E2E.

   This run also showed that the panel's AUTH_INVALID and PERMISSION_DENIED messages said "API keys", which only
   WooCommerce has. Both are now provider-neutral (commit `fix(commerce): word store auth and permission errors for
   every provider`).

| # | Check | Result |
|---|---|---|
| 1 | Super Admin shows the Salla fields with the secrets masked and empty | pass |
| 2 | Add store offers WooCommerce and Salla | pass |
| 3 | one-time code shown with the official install link, nothing secret asked | pass |
| 4 | unsigned, badly signed, wrong-secret, token-strategy and modified deliveries get 401 | pass |
| 5 | nothing was queued for refused deliveries | pass |
| 6 | a signed authorization is accepted, and its redelivery is queued once | pass |
| 7 | an authorization alone connects nothing (no account is ever guessed) | pass |
| 8 | signed app.settings.updated accepted | pass |
| 9 | store connected to account A by the code: merchant id, Salla name, credentials stored | pass |
| 10 | settings list shows the Salla store as active, without key actions | pass |
| 11 | a later authorization for the same merchant creates no second store | pass |
| 12 | a code from account B for A's store is a conflict; the store stays with A | pass |
| 13 | the conversation lists WooCommerce and Salla stores | pass |
| 14 | Salla customer linked by the verified WhatsApp phone, latest orders newest first | pass |
| 15 | shipped order: carriers, shipment status, Track shipment and Send tracking | pass |
| 16 | payment: unpaid only when Salla says so, otherwise "Payment not confirmed" | pass |
| 17 | an order whose shipment is not trackable shows no tracking actions | pass |
| 18 | tracking and admin links are Salla's https links | pass |
| 19 | Send tracking puts the tracking message in the reply box (nothing sent) | pass |
| 20 | two Salla customers share the phone: both offered, nothing linked | pass |
| 21 | no Salla customer for the contact: not found + Link customer | pass |
| 22 | Salla refuses access (sandbox 403): the error is shown and no orders are presented as current | pass |
| 23 | rate limited by Salla: the last orders shown as stale with their age, no request | pass |
| 24 | refresh token rejected: needs re-authorization, refresh token removed, one token request | pass |
| 25 | settings explain re-authorization in Salla | pass |
| 26 | a store needing re-authorization is not offered in conversations | pass |
| 27 | Salla re-authorizes (app updated): same store active again | pass |
| 28 | 10 concurrent readers of an expiring token: one refresh request, old refresh token sent once, new one saved | pass |
| 29 | a second Salla store connects to the same account | pass |
| 30 | store selector lists WooCommerce and both Salla stores | pass |
| 31 | Arabic panel: shipped status, shipment status and tracking actions | pass |
| 32 | Arabic Connect with Salla dialog | pass |
| 33 | mobile (Arabic): Salla orders render inside the viewport | pass |
| 34 | mobile: the Connect with Salla dialog fits the screen | pass |
| 35 | Salla off: stores kept and explained | pass |
| 36 | Salla off: Add store goes straight to WooCommerce keys (no Salla option) | pass |
| 37 | Salla off: Salla stores are not offered in conversations | pass |
| 38 | Salla off: no connection code can be created | pass |
| 39 | signed app.uninstalled accepted | pass |
| 40 | uninstall disconnects the store: credentials and links removed, contacts kept | pass |
| 41 | settings show the uninstalled store as disconnected with Reconnect | pass |
| 42 | an agent cannot start a Salla connection | pass |
| 43 | audit trail: connect_started, connected, reauthorized, token_refreshed, needs_reauth, disconnected | pass |
| 44 | audit entries carry no token or secret | pass |
| 45 | no Salla token, refresh token or secret in any browser response | pass |
| 46 | no token, secret or connection code in the server or job logs | pass |
| 47 | no uncaught page errors | pass |

**47/47 passed.**

**What some checks exercise:**

- **Webhook signatures (checks 4 to 6).** Real HTTP deliveries. Refused deliveries return 401 and queue nothing. A
  signed redelivery of the same bytes is queued once.
- **Tenant correlation (checks 7, 9, 12).** An authorization alone creates nothing. The store is connected only when
  the code the administrator created arrives through the signed settings event. Another account's code for the same
  merchant is a conflict, and the store stays where it is.
- **Tokens (checks 24, 28).** These run `Commerce::Salla::TokenManager` in the harness process against Salla's
  documented token endpoint answers.
  - A rejected refresh token marks the store `needs_reauth` and deletes the refresh token, after exactly one token
    request.
  - Ten threads reading an expiring token make one refresh request, send the old refresh token once, and all get the
    new token.
- **Secrets (checks 44 to 46).**
  - 488 browser API responses were scanned.
  - The server log and the job log were scanned.
  - Every audit row was scanned.

  None contains a Salla access token, refresh token, client secret, webhook secret or connection code.

## 3. WooCommerce regression

The Phase 2 WooCommerce E2E (doc 09) was rerun unchanged, against the same three real WooCommerce 10.9.4 stores, on
the final build with Salla switched off. That is the "WooCommerce only" experience: Add store opens the key dialog
directly.

**Result: 41/41 passed** (`e2e/results/woocommerce_regression_phase3.txt` / `.json`). The only change to that script
is the AUTH_INVALID wording above.

## Screenshots (`screenshots/salla/`)

| File | Shows |
| --- | --- |
| `salla-01-super-admin.png` | Super Admin → Salla: switch, App ID, Client ID, masked write-only secrets |
| `salla-02-provider-picker.png` | Add store → WooCommerce / Salla |
| `salla-03-connection-code.png` | Connect with Salla: steps, one-time code, install link, waiting |
| `salla-04-connected-list.png` | the store connected, next to WooCommerce stores |
| `salla-05-conflict.png` | account B's code for account A's store: conflict |
| `salla-06-panel-orders-en.png` | conversation panel: auto-linked by WhatsApp phone, orders, shipment status, tracking actions |
| `salla-07-multiple-matches.png` | two Salla customers share the phone: manual choice |
| `salla-08-not-found.png` | no Salla customer for the contact |
| `salla-09-access-refused.png` | Salla refusing access: error shown, nothing passed off as current |
| `salla-09b-stale-rate-limited.png` | rate limited: last orders shown as stale with their age |
| `salla-10-needs-reauth.png` | settings: re-authorization needed, with instructions |
| `salla-11-multi-store.png` | store selector with WooCommerce and two Salla stores |
| `salla-12-panel-arabic.png`, `salla-13-settings-arabic.png`, `salla-14-connect-dialog-arabic.png` | Arabic (RTL) |
| `salla-15-mobile-arabic.png`, `salla-16-mobile-connect-dialog.png` | 390×844 |
| `salla-17-provider-off.png` | Salla switched off in Super Admin: stores kept and explained |
| `salla-18-after-uninstall.png` | after `app.uninstalled`: disconnected, Reconnect |

## Reproduce

```bash
# Environment as in doc 09 §8. e2e.env also needs E2E_SALLA_WEBHOOK_SECRET and E2E_SALLA_CLIENT_SECRET (any random values).
node docs/commerce/e2e/e2e.js <out> '<woo keys json>'        # WooCommerce first: it resets Commerce state
cd docs/commerce/e2e/salla && ERUN=../erun.sh CHROMIUM_PATH=… E2E_SALLA_WEBHOOK_SECRET=… E2E_SALLA_CLIENT_SECRET=… node e2e_salla.js <out>
```


## 4. Checklist for the real Salla UAT (when unblocked)

**Prerequisites:**

- The environment's network access must allow `api.salla.dev`, `accounts.salla.sa`, `s.salla.sa`, and `docs.salla.dev`
  for reading the docs.
- A Salla Partner account and a demo store.
- A public HTTPS URL for Lynomia.

**Steps:**

1. **Partner portal:** create a public app in **Easy Mode**.
   - Webhook URL `https://<lynomia>/webhooks/salla`, security strategy **Signature**.
   - Scopes `customers.read orders.read shipping.read offline_access`.
   - The settings field from doc 10.
2. **Super Admin → Settings → Salla:** enter the App ID, Client ID, Client Secret and Webhook Secret, then enable.
3. **Settings → Commerce → Add store → Salla:** create a code, install the app on the demo store with the install link,
   and paste the code into the app's settings. Record:
   - that `app.store.authorize` and `app.settings.updated` both arrive, with their order and headers
     (`X-Salla-Security-Strategy`, `X-Salla-Signature`);
   - that the store connects;
   - the `user/info` shape (`merchant.id`, `domain`).
4. **Demo store data:** create customers, including two sharing one mobile, and orders.
   - Include one awaiting payment, one shipped with a trackable shipment, and one with several shipments.
   - Confirm the keyword search matches the national number, and the default order of `GET /orders`.
   - Confirm the order list's `items` and `date`, and the shipment `status` and `tracking_link`.
5. **Tokens:** move `access_token_expires_at` to within a day and confirm exactly one refresh.
   - Capture the refresh response's fields (`expires` vs `expires_in`, `scope`).
   - Then update the app in Salla, and confirm the store stays connected (`commerce.salla.reauthorized`).
6. **Uninstall** the app and confirm the store is disconnected in Lynomia.
7. **Re-check** every VERIFY item in docs 10 and 11, and record the results here.


## 5. Full regression closure

**Test assets.** They were built once per tree, sequentially, before any spec ran (`bin/vite build --force`):

| Tree | Build | Digest |
| --- | --- | --- |
| Enterprise | 14:12:17 | `d9252bb5` |
| Community | 14:13:54 | `d9252bb5` |

Every shard then ran with `VITE_RUBY_AUTO_BUILD=false`, and both timestamps were unchanged afterwards. The first full
run's 58 HTML-page failures (500s, 140–300 s each) came from all eight shards rebuilding stale assets at the same
time.

**Rerun of the first run's 59 failures:**

- Community: 28/28 passed.
- Enterprise: 30/31 passed. The one left is the voice spec below.

**Final full RSpec** (4 shards per tree, HEAD `87923e3ee` code):

| Suite | Examples | Failures | Pending |
| --- | --- | --- | --- |
| Enterprise | 9868 | 1 | 67 |
| Community | 7167 | 2 | 69 |

Vitest: 455 files, 4704 tests passed. ESLint on Commerce and Salla code: no warnings.

**Remaining failures: none is caused by Commerce, Salla or Lynomia.**

| Spec | Suite | Class | Evidence |
| --- | --- | --- | --- |
| `spec/enterprise/services/voice/call_transcription_service_spec.rb:77` | Enterprise | UPSTREAM | See below |
| `spec/models/conversation_spec.rb:1144`, `:1172` | Community | UPSTREAM | See below |

- **`call_transcription_service_spec.rb:77`.** It fails with `Message … does not implement: reindex`.
  - The spec stubs `reindex`, which `Message` gains only when the process boots with `OPENSEARCH_URL` (the model
    declares `searchkick … if ChatwootApp.advanced_search_allowed?`).
  - Clean upstream `v4.18.0` fails identically.
  - It passes on HEAD with `OPENSEARCH_URL` set.
  - It also failed in the Phase 2 baseline.
  - The spec, the service, `Message` and `ChatwootApp` are unchanged from `v4.18.0`.
- **`conversation_spec.rb:1144`, `:1172`.** They fail with `expected 3602.0 to be within 1 of 1 hour`.
  - The spec compares `N.hours.ago` values taken at different moments, with 1 second of tolerance. Here each example
    takes about 3 s, because it runs jobs inline.
  - Clean upstream `v4.18.0` fails the same way: 2 of 5 isolated runs failed, as on HEAD (2 of 5).
  - The spec and `Conversation` are unchanged from `v4.18.0`, and both examples passed in the Phase 2 baseline and in
    the first Phase 3 run.
