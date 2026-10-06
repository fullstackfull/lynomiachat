# 01 — Provider capability matrix

**Verified against HEAD, not against memory.** Every cell below was classified from code and specs read at this
HEAD. P6's brief recorded a provider history; where the code disagrees with it, the code wins and the difference
is noted.

---

## 1. The classification scale, and why provenance is separate from passing

A green test suite says the **Lynomia side** behaves as its author intended. It says nothing about whether the
provider's real response looks like the fixture the test used. Those are two different claims, and conflating them
is how a product comes to advertise a capability nobody has ever seen work. So every cell carries two independent
dimensions.

**Evidence provenance** — where the provider's half of the exchange came from:

| Level | Meaning |
|---|---|
| `REAL PROVIDER RESPONSE VERIFIED` | A genuine captured response from a real instance of that provider exists in the repository and the tests run against it |
| `PROVIDER-CONTRACT VERIFIED` | The request/response shape was checked against the provider's current published documentation, read and cited, but no real response exists here |
| `SIMULATED / HAND-AUTHORED FIXTURE` | The only provider input is a payload this repository wrote. It may be faithful; nothing proves it is |
| `UNKNOWN` | Not established at all |

**Operational state** — what the product may honestly do with it:

| Level | Meaning |
|---|---|
| `SOFTWARE COMPLETE / REAL UAT BLOCKED` | The code path exists and is tested; it has never run against a real store |
| `PRE_UAT` | A gate blocks it in production regardless of code quality |
| `READ ONLY` | Reads implemented, no write exists |
| `UNSUPPORTED` | Either the provider's API does not offer it, or Lynomia has not built it — always stated which |

**No cell is marked PROVEN against a real store anywhere in this matrix**, because no provider UAT has run in this
environment. That is the honest state and §4 records it per provider.

## 2. The provenance finding that shaped everything

There is **no HTTP recording mechanism in this repository at all** — no VCR gem, no cassettes (a search for
cassettes finds only the vendored `koala` gem's own). Every provider test is WebMock plus JSON. So the question for
each provider is simply: who wrote that JSON?

| Provider | Fixture | Verdict |
|---|---|---|
| **WooCommerce** | `spec/fixtures/files/commerce/woocommerce/orders.json` — 14 orders, each carrying `"version": "10.9.4"`, `customer_user_agent: "WP CLI 2.12.0"`, `is_editable`, `needs_payment`, `_links` with `targetHints`, `order_key: "wc_order_redacted"`, `_links` host `https://localhost:8081`, `currency: "SAR"`, dated 2026-09-29 | **a real capture.** A WP-CLI-seeded local WooCommerce 10.9.4, with the order key redacted afterwards. `targetHints` is a genuine WP REST feature, not something an author invents |
| **Zid** | `spec/fixtures/files/commerce/zid/orders.json` | **hand-authored.** It contains `https://track.kwickbox.example/KWB123456789SA` — `.example` is an RFC 2606 reserved TLD that cannot occur in a real capture |
| **Salla** | `spec/fixtures/files/commerce/salla/*.json` | **hand-authored**, and `spec/services/commerce/providers/salla_spec.rb:3-4` says so in the repository itself: no live store could be recorded |
| **Shopify** | `spec/fixtures/files/commerce/shopify/*.json` | **hand-authored**, checked against Shopify's published schema — `spec/services/commerce/providers/shopify_spec.rb:3-4` states "checked against Shopify's published schema … with this spec's own shop, customers and orders" |

So WooCommerce reaches `REAL PROVIDER RESPONSE VERIFIED` for the paths its capture covers. The other three reach at
best `PROVIDER-CONTRACT VERIFIED`, and only where a published contract was actually cited.

This distinction was challenged before being adopted. An adversarial pass over each column downgraded 23 cells,
and the WooCommerce column survived with none — not because it was reviewed more softly, but because its reviewer
checked fixture provenance and found a real capture. That claim was then re-verified directly.

## 3. The matrix

`CONTRACT` = provider-contract verified · `SIM` = simulated/hand-authored · `REAL` = real provider response
verified · `—` = not applicable.

| Capability | WooCommerce | Salla | Zid | Shopify |
|---|---|---|---|---|
| CONNECT | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM |
| TOKEN REFRESH | UNSUPPORTED (provider: key-based auth, no token) · — | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM |
| READ CUSTOMER | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM |
| READ ORDERS | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM |
| ORDER LOOKUP BY ID | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | **UNSUPPORTED (Lynomia: implemented but unreachable)** · — | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | PRE_UAT · SIM |
| ORDER LOOKUP BY NUMBER | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | UNSUPPORTED (Lynomia) · — | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM |
| ORDER STATUS | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | READ ONLY · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | READ ONLY · SIM |
| PAYMENT STATUS | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | READ ONLY · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | READ ONLY · SIM |
| TRACKING | UNSUPPORTED (Lynomia: no write; read not surfaced) · — | READ ONLY · SIM | READ ONLY · SIM | READ ONLY · SIM |
| CANCEL ORDER | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | UNSUPPORTED (Lynomia, and token scope forbids it) · — | UNSUPPORTED (Lynomia) · — | PRE_UAT · SIM |
| REFUND | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | UNSUPPORTED (Lynomia, scope forbids) · — | UNSUPPORTED (Lynomia) · — | PRE_UAT · SIM |
| PAYMENT LINK | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM (no spec performs it) | UNSUPPORTED (Lynomia) · — | UNSUPPORTED (Lynomia) · — | UNSUPPORTED (Lynomia) · — |
| WEBHOOKS | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | **UNSUPPORTED (Lynomia: registers none)** · — | SOFTWARE COMPLETE / REAL UAT BLOCKED · **CONTRACT** | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM |
| WEBHOOK AUTH | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** (shared secret) | UNSUPPORTED (none registered) · — | SOFTWARE COMPLETE / REAL UAT BLOCKED · **CONTRACT** (Basic Auth, §02) | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM (HMAC) |
| CART DATA | **UNSUPPORTED (provider, as Lynomia reads it)** · — | PRE_UAT · SIM, endpoint self-declared unverified | PRE_UAT · **CONTRACT** | PRE_UAT · SIM |
| CART CREATED | UNSUPPORTED (provider) · — | UNSUPPORTED (Lynomia: polls, no event) · — | **UNSUPPORTED (Lynomia: provider offers the event, Lynomia does not subscribe)** · **CONTRACT** | UNSUPPORTED (Lynomia) · — |
| CART UPDATED | UNSUPPORTED (provider) · — | UNSUPPORTED (Lynomia) · — | UNSUPPORTED (provider: no cart.updated event exists) · **CONTRACT** | UNSUPPORTED (Lynomia) · — |
| CART RECOVERED | UNSUPPORTED (provider) · — | **UNSUPPORTED (provider: undetectable by construction)** · — | **UNSUPPORTED (Lynomia: `abandoned_cart.completed` exists, not subscribed)** · **CONTRACT** | PRE_UAT · SIM |
| CHECKOUT/ORDER CORRELATION | UNSUPPORTED (Lynomia) · — | UNSUPPORTED (provider) · — | **PRE_UAT · CONTRACT** (`order_id` on the cart) | UNSUPPORTED (Lynomia: `completedAt` read, order id discarded) · — |
| REALTIME | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | UNSUPPORTED (no webhooks) · — | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM |
| BACKGROUND TOKEN REFRESH | UNSUPPORTED (provider) · — | UNSUPPORTED (Lynomia: on-demand only) · — | UNSUPPORTED (Lynomia: on-demand only) · — | UNSUPPORTED (Lynomia: on-demand only) · — |
| REVOCATION | SOFTWARE COMPLETE / REAL UAT BLOCKED · **REAL** | UNSUPPORTED (Lynomia) · — | UNSUPPORTED (Lynomia) · — | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM |
| UNINSTALL DETECTION | UNSUPPORTED (provider) · — | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM | UNSUPPORTED (Lynomia: provider offers `app.market.application.uninstall`) · **CONTRACT** | SOFTWARE COMPLETE / REAL UAT BLOCKED · SIM |

### Where this contradicts the recorded history

| Recorded in the brief | What HEAD shows |
|---|---|
| "WooCommerce: historically no cart data in the Lynomia connector **by design**" | Confirmed, and stronger: `providers/base.rb:87` defaults `supports_carts?` false and WooCommerce never overrides it; `switches.rb:15` has no WooCommerce recovery key at all |
| "Zid: historically the strongest abandoned-cart candidate" | Confirmed as the conclusion, but for a reason the brief did not state: Zid is the only provider offering **both** a native abandonment event and a native completion event, and Lynomia subscribes to neither |
| "Zid: some write actions exist" | Confirmed and narrow: exactly `update_order_status`, and only `ready → shipped` and `indelivery → delivered` |
| "Salla: no write actions in current architecture" | Confirmed and stronger: `salla/tokens.rb:22-28` refuses to store any token whose scope is not `offline_access` or `*.read`, so a connected Salla store is structurally incapable of writing |
| "Shopify: protected customer data may constrain UAT" | Confirmed as a live gate: cancel and refund are `PRE_UAT` |

## 4. Real UAT blockers, per provider

| Provider | What blocks real UAT |
|---|---|
| WooCommerce | No real store credentials in this environment. Its contract is the best-evidenced of the four, and it is the only provider whose production path is not gated off — so it is the natural first real UAT. Needs a store URL, a consumer key/secret, and a harmless test order |
| Salla | No credentials; and partner/marketplace approval governs whether a read-scope app can be installed at all. Nothing Lynomia can unblock from here |
| Zid | No credentials. Separately: every cart path is `PRE_UAT` behind an ENV-only flag, and the webhook registration defect in `02` meant order webhooks could never have delivered — so any earlier "Zid works" impression was about polling, not webhooks |
| Shopify | No credentials; plus Shopify's protected customer data approval, which is a Shopify-side review, not a configuration |

## 5. One source of truth for capability

Provider capability is decided in more than one place, which is a real risk of the UI offering what the backend
cannot do. The authoritative chain as it stands:

- `Commerce::Providers::Base` declares the interface and the defaults (`supports_actions?`, `supports_carts?`,
  `registers_webhooks?`), and each adapter overrides what it has.
- `Commerce::Switches` holds the production gates, including `PRE_UAT[:recovery]`.
- `Commerce::OrderActions` reports per-action availability to the API, and refuses an action the adapter does not
  claim — so the backend is the last word even if a UI offers a button.

That ordering is sound and no new capability platform is needed. What `03` proposes instead is a single
read-only report that prints the same chain, so an operator can see what a given store may actually do.
