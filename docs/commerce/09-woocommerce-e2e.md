# Lynomia Commerce: real WooCommerce E2E

**Run date:** 2026-09-30.

**What ran:**
- the Lynomia app in production mode (Ruby 3.4.4 / Node 24 image `lynomia/verify:base`, Vite production build, Postgres 16, Redis);
- **three real WooCommerce 10.9.4 stores** in Docker;
- a real browser (Playwright + Chromium).

No mocks: every order, customer and error below came from WooCommerce's REST API.

## 1. Environment

| Part | Detail |
|---|---|
| WordPress | `wordpress:php8.3-apache` (via `mirror.gcr.io`), MariaDB 11 |
| WooCommerce | 10.9.4, built from the official source tag (`e2e/woocommerce/build_woocommerce.sh`; wordpress.org is not reachable from this environment). **HPOS on** (the default for new stores). |
| Store 1 "Syria Cosmetics" | `http://localhost:8081`, connected by account A |
| Store 2 "Damascus Perfumes" | `http://localhost:8082`, connected by account A |
| Store 3 "Aleppo Soap" | `http://localhost:8083`, connected by account B |
| Keys | created with **`permissions = read`** (`e2e/woocommerce/apikey.php`) |
| Transport | The stores are plain-http local sites. WooCommerce only accepts Basic auth over TLS, so the test sites treat `/wp-json/` requests as HTTPS (`WORDPRESS_CONFIG_EXTRA`). Lynomia reaches them through the explicit `COMMERCE_TRUSTED_STORE_HOSTS=localhost` policy. |
| Production-path coverage | The https + SsrfFilter path is covered by specs (`08` §2) and by the real-DNS `localtest.me` case below. |

**Lynomia data (`e2e/rails/seed.rb`):**

| Account | Contents |
|---|---|
| A "Lynomia Demo A" | admin, agent (member of both inboxes), agent **without** inbox access; inboxes "واتساب بزنس" (WhatsApp Cloud) and "Website" (widget) |
| B "Lynomia Demo B" | admin, WhatsApp inbox |

`lynomia_commerce` is enabled on both accounts; no plan limit is set.

## 2. Store data (`e2e/woocommerce/seed.php`, `seed_extra.php`)

**Store 1:**

| Customer | Kind | Phone as stored | Orders (id, status, payment evidence) |
|---|---|---|---|
| ليلى حداد (id 2) | registered | `+966501234567` | 14 completed, card, paid, **2 items**, Aramex Express, plugin tracking meta; 15 processing, card, paid; 16 cancelled; 17 on-hold, bank transfer; 18 refunded; 20 completed + partial refund; 22 processing, **cash on delivery** (7 orders) |
| Omar Khalil | **guest** | `0551112233` (local format), email `Omar.Khalil@Example.com` | 23 pending; 24 completed, **virtual (no shipping)**; 25 failed |
| Sara Ali (3) / Noor Ali (4) | registered | `+966550000111` / `0550000111` (**same number**) | 26 processing / 27 completed |
| Hana (5) / Rami (6) | registered | different phones, **same billing email** `family@example.com` | 28 / 29 |
| منى صالح (7) | registered | `+966509998877` | **no orders** |

**Stores 2 and 3:** the same shopper (Layla, `0501234567`) with the stores' own orders.
- Store 2: 11 completed, 12 processing, SMSA Express.
- Store 3: 11 completed.

## 3. Results

**Browser E2E (`e2e/e2e.js`): 41/41 passed.**
- Full log: `e2e/results/e2e_run.txt`
- Machine-readable: `e2e/results/e2e_results.json`

| # | Check | Result |
|---|---|---|
| 1 | Settings with no stores | pass |
| 2 | Connect with a wrong secret → `AUTH_INVALID`, nothing saved | pass |
| 3 | `https://10.0.0.5` → "not an IP address" | pass |
| 4 | `http://shop.example.com` (untrusted) → "must use https" | pass |
| 5 | `https://localtest.me` (real DNS → 127.0.0.1) → "private network" | pass |
| 6 | A1 and A2 connected through the UI (health check with Read keys) | pass |
| 7 | Account B cannot connect A1 → "already connected" | pass |
| 8 | Account B connects B1 | pass |
| 9 | WhatsApp conversation (source `966551112233`) auto-links the **guest** whose phone is stored as `0551112233` | pass |
| 10 | Failed / paid (virtual, no shipping) / unpaid shown correctly | pass |
| 11 | Registered customer: latest 5 of 7 orders. COD processing and on-hold are **"Payment not confirmed"**; refunded and partially refunded shown | pass |
| 12 | Store selector with 2 stores | pass |
| 13 | View order = stored URL + numeric id (`/wp-admin/admin.php?action=edit&id=22&page=wc-orders`) | pass |
| 14 | No tracking controls (core has none; plugin tracking meta on order 14 ignored) | pass |
| 15 | Switching to A2 shows only A2 orders (#12, #11) | pass |
| 16 | Duplicate phone: Sara and Noor offered, masked (`+966*******11`), nothing linked | pass |
| 17 | Agent picks Sara → "Linked by Agent A", order #26 | pass |
| 18 | Widget contact email → suggestion only | pass |
| 19 | Linked customer without orders → "No orders yet." | pass |
| 20 | Duplicate billing email: Hana and Rami offered | pass |
| 21 | Not found + Link customer | pass |
| 22 | Search by name refused | pass |
| 23 | Search `+966551112233` finds the guest | pass |
| 24 | **Store 1 stopped:** Layla's orders shown from cache with "Couldn't refresh store data right now · Last updated 3 minutes ago" | pass |
| 25 | Store stopped and nothing cached: safe message only (no exception text) | pass |
| 26 | Arabic panel (المتجر, العميل المربوط, مسترد جزئيًا) | pass |
| 27 | Arabic not found (لم يتم العثور على العميل في هذا المتجر, ربط العميل) | pass |
| 28 | Mobile 390×844, Arabic: panel inside the viewport | pass |
| 29 | Mobile, English: panel inside the viewport, no page overflow | pass |
| 30 | Agent without inbox access sees no store data | pass |
| 31 | Feature off: no Commerce section | pass |
| 32 | Feature off: no Settings → Commerce entry | pass |
| 33 | Admin disables A2 | pass |
| 34 | A disabled store leaves the agent's store list | pass |
| 35 | Admin re-enables A2 (fresh health check) | pass |
| 36 | Admin replaces A2 keys (health-checked) | pass |
| 37 | Admin disconnects A2 (confirmation) → "Disconnected", "Reconnect" | pass |
| 38 | Agent changes Sara's link to Noor (order #27) | pass |
| 39 | Agent unlinks Mona → back to a suggestion | pass |
| 40 | 697 API responses in the browser: **no consumer key or secret, no `credentials` field** | pass |
| 41 | No uncaught page errors | pass |

**API checks (`e2e/api_checks.sh`): 17/17 passed** (`e2e/results/api_checks.txt`).
- Admin lists stores with no credentials.
- An agent cannot list, disconnect or change stores (401).
- An agent of the inbox reads the panel (200); an agent without access is refused (401).
- Admin B cannot enter account A (401), nor read A1 through account B's conversation (404).
- Admin A cannot read or modify B1 (404).
- A forged link token gives 422, and a name search gives 422.
- `https://169.254.169.254` and `https://[::1]` give 422 `ip_address_not_allowed`.
- A malformed key gives 422, and an unsupported provider gives 422.

## 4. Multi-store and multi-tenant

**Account A** has A1 and A2:
- Layla is linked separately per store (`commerce_customer_links` rows for store 11 and store 12, same contact).
- The panel shows one store at a time through the selector (#22… for A1; #12, #11 for A2).

**Account B** has B1:
- Its admin cannot claim A1.
- No A1/A2 data is reachable from account B, and B1 is not reachable from account A: checks 7 and 8 plus the API checks.
- Cache keys carry the account and store (`COMMERCE::V1::ACCOUNT::1::STORE::11::…`).

## 5. Evidence

**Encryption:**
- `commerce_stores.credentials` is stored as `{"p":"R1MKkGWc7h…","h":{"iv":…}}` (253 bytes).
- `external_customer_id` is ciphertext too.
- A full `pg_dump` of the E2E database contains **0** occurrences of any of the three stores' keys or secrets.

**Audit trail (`e2e/results/audit_trail.json`):**
- store_connected ×3;
- customer_link_created ×5 (3 `verified_phone`, 2 `manual`);
- store_disabled, store_enabled, credentials_rotated, store_disconnected (1 link removed);
- customer_link_changed, customer_link_removed.

No credentials appear in any payload.

**Redis:**
- 11 keys: `alfred:COMMERCE::V1::ACCOUNT::1::STORE::11::CANDIDATES::<hmac>` ×6 and `…::ORDERS::<hmac>` ×5.
- TTL ≈ 24 h.
- No email or phone in any key; no key or secret in any value.

**Server log:**
- 0 occurrences of any key or secret; request parameters show `[FILTERED]`.
- 59 `[Commerce]` lines: paths, statuses, ms, event names and ids.
- 0 contain an email, a phone or a search term.

## 6. Regression

Final pass on the pushed code (`20cd47a91`, 2026-09-30), Ruby 3.4.4 / Node 24 (`lynomia/verify:base`).

| Suite | Result | Phase 4 baseline |
|---|---|---|
| RSpec, Enterprise tree (4 shards) | 9757 examples, **1 failure**, 67 pending (161 Commerce examples) | 9580 examples, 1 failure |
| RSpec, Community tree (`enterprise/` and `spec/enterprise/` removed; 4 shards) | 7060 examples, **1 failure** (passes on re-run, see below), 69 pending (160 Commerce examples) | 6884 examples, 0 failures |
| Vitest | 453 files, **4692 tests passed** | all passed |
| ESLint | **0 errors**, 455 warnings | 0 errors, 444 warnings |
| RuboCop (3135 files) | 54 offenses, **all in files this phase did not touch** (`script/`, `spec/support/opensearch_check.rb`, `spec/rails_helper.rb`, `docker/…`) | the same 54 |
| WhatsApp harness `check_existing_whatsapp.rb` (existing WhatsApp numbers, fresh DB + `seed_pre_upgrade.rb` 2/2) | **41/41** | 41/41 |
| Lynomia harness `check_lynomia.rb` (custom/ overlay, billing lock and plan limits, platform billing API, Stripe webhook, mobile auth and billing return, dashboard title, profile API) | **17/17** | 17/17 |
| واتساب بزنس harness `check_coexistence.rb` | **54/54** | 54/54 |

**The two remaining failures:**
- **Enterprise:** `spec/enterprise/services/voice/call_transcription_service_spec.rb[1:1:7]`. It is the same example as in the Phase 4 baseline, is unrelated to Commerce, and passes in isolation.
- **Community:** `spec/controllers/dashboard_controller_spec.rb[1:1:1]` answered 500 once, then passed on re-run (4/4).
  - Cause: the refreshed Community tree had no Vite build digest.
  - So `vite_ruby` auto-build rebuilt the test assets in the four parallel shards at the same time.
  - One request hit the asset folder mid-rebuild. This is a runner race, not a product failure.

**The ESLint warning delta (+11):**
- All 11 are `@intlify/vue-i18n` warnings in the new Commerce components.
- They come from dynamic keys for status and error codes, and the literal `#` before order numbers.
- They are warnings in the repository configuration, not errors.

**Found and fixed by the first pass** (commits after the Phase 2 feature commits):
- `spec/support/commerce_encryption.rb` reset the Active Record keys to nil after each Commerce example.
  - Channels that declare `encrypts … if Chatwoot.encryption_configured?` and were first loaded inside such an example then failed later.
  - Result: 38 order-dependent Twilio/WhatsApp spec failures in one shard.
  - Fix: the throwaway keys stay configured; ENV is still restored.
- `spec/models/account_spec.rb` pins every `feature_flags_ext_1` flag. Added `lynomia_commerce` (bit 7, append-only; no existing bit moved).
- The Commerce link audit spec now orders rows by id.

**Shopify:** the upstream Shopify specs (`spec/controllers/shopify`, `spec/services/shopify`, integration helper, hooks, webhooks) run inside both suites.

**With `lynomia_commerce` off:**
- the full suites run against the unchanged core behaviour (the flag is off by default);
- the E2E checks 31–32 prove nothing Commerce is shown.

## 7. Screenshots (`screenshots/`)

| File | Shows |
|---|---|
| `01-settings-no-stores.png` | Settings → Commerce, empty |
| `02-connect-wrong-secret.png` | connect refused, `AUTH_INVALID` message |
| `03-connect-private-dns.png` | `localtest.me` refused (private network) |
| `04-settings-two-stores.png` | A1 + A2 active |
| `05-account-b-cannot-claim-a1.png` | account B: "already connected" |
| `06-whatsapp-verified-phone-guest.png` | WhatsApp guest auto-linked, 3 orders |
| `07-registered-five-orders-store-a1.png` | registered customer, 5 latest orders, store selector |
| `08-registered-store-a2.png` | same contact, store A2 |
| `09-duplicate-phone-manual-selection.png` | two masked candidates |
| `10-duplicate-phone-linked.png` | linked by the agent |
| `11-email-suggestion.png` | suggestion from the contact email |
| `12-linked-no-orders.png` | linked, no orders |
| `13-duplicate-email.png` | two candidates for one billing email |
| `14-not-found.png` | not found + Link customer |
| `15-manual-search.png` | manual search result |
| `16-store-down-stale.png` | stale data with its age |
| `17-store-down-nothing-cached.png` | unavailable, safe message |
| `18-arabic-linked-orders.png`, `19-arabic-not-found.png`, `20-arabic-settings.png` | Arabic (RTL) |
| `21-mobile-arabic.png`, `22-mobile-english.png` | 390×844 |
| `23-feature-off-conversation.png`, `24-feature-off-settings.png` | `lynomia_commerce` off |
| `25-disconnect-confirm.png`, `26-settings-after-lifecycle.png` | disconnect flow and resulting states |

## 8. Reproduce

```bash
cd docs/commerce/e2e/woocommerce
./build_woocommerce.sh && ./up_site1.sh && ./up_sites2_3.sh   # 3 seeded stores + Read keys (key.txt, key2.txt, key3.txt)
cd .. && cp e2e.env.example e2e.env                           # fill in local secrets
./erun.sh "bundle exec rails db:create db:schema:load && bundle exec rails runner docs/commerce/e2e/rails/seed.rb"
./erun.sh "RAILS_ENV=production bin/vite build"               # then start: ./erun.sh "bundle exec rails s -p 3100"
PLAYWRIGHT_MODULE=… CHROMIUM_PATH=… node e2e.js <out_dir> '{"s1":{"ck":…,"cs":…},"s2":…,"s3":…}'
WOO_DIR=./woocommerce ./api_checks.sh
```

- `e2e.js` starts by resetting Commerce state (`rails/reset.rb`).
- It stops and restarts the store 1 container to test the stale fallback.
- It waits 125 s for the fresh window to pass.
