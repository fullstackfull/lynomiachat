---
agent: 056
scope: Corpus audit of the `commerce` section (7 articles, EN + AR) against the commerce code, the provider capability matrices, EN/AR parity, and the retired Shopify path
confidence: high
---

Path legend, used throughout: `doc/` = `custom/db/documentation/`, `svc/` = `custom/app/services/commerce/`, `ctl/` = `custom/app/controllers/api/v1/accounts/`, `fe/` = `app/javascript/dashboard/`, `m01` = `docs/commerce-production/01-provider-capability-matrix.md`, `m05` = `docs/commerce/05-provider-capability-matrix.md`. Doc citations are `file:line` of the Markdown file as seeded (front matter counts as lines 1-7).

Method: every article was read in full in both locales; every checkable claim was traced to code at `claude/documentation-v2` (HEAD `f986521c`, baseline `021ea6e3`). Nothing was rendered in a browser and nothing was run: where a verdict rests on reading a route or a renderer, it says so. The baseline map `01-current-system.md` was verified for the commerce-relevant parts: 7 EN + 7 AR articles (confirmed), `commerceErrorArticle` maps 19 codes (`fe/helper/documentationLinks.js:109-133` has 19 entries, confirmed). The count of 87 `DOC_ARTICLES` keys was not checked here.

## 1. Inventory

Word counts are body words (front matter excluded, punctuation-only tokens such as table pipes excluded). All 14 files have complete front matter (`title`, `description`, `position`, `tags`, `seo_description`); none has `seo_title`, `version`, or an image. EN slug = key; AR slug = key + `-ar` (`custom/app/services/documentation/content_seeder.rb`, `slug_for`).

| key | EN file | AR file | EN title | AR title | pos | EN words | AR words |
|---|---|---|---|---|---|---|---|
| commerce-overview | doc/en/commerce/commerce-overview.md | doc/ar/commerce/commerce-overview.md | What connecting a store gives you | ما يمنحك ربط المتجر | 10 | 832 | 689 |
| commerce-provider-support | doc/en/commerce/commerce-provider-support.md | doc/ar/commerce/commerce-provider-support.md | What each platform supports | ما تدعمه كل منصة | 20 | 874 | 814 |
| connect-woocommerce | doc/en/commerce/connect-woocommerce.md | doc/ar/commerce/connect-woocommerce.md | Connect WooCommerce | ربط WooCommerce | 30 | 882 | 733 |
| connect-salla | doc/en/commerce/connect-salla.md | doc/ar/commerce/connect-salla.md | Connect Salla | ربط Salla | 40 | 810 | 671 |
| connect-zid | doc/en/commerce/connect-zid.md | doc/ar/commerce/connect-zid.md | Connect Zid | ربط Zid | 50 | 804 | 656 |
| connect-shopify | doc/en/commerce/connect-shopify.md | doc/ar/commerce/connect-shopify.md | Connect Shopify | ربط Shopify | 60 | 812 | 679 |
| customer-360 | doc/en/commerce/customer-360.md | doc/ar/commerce/customer-360.md | Customer 360 | عرض العميل الشامل | 70 | 1016 | 892 |
| **total** | | | | | | **6030** | **5134** |

Section is registered in `doc/manifest.yml` (slug `commerce`, position 70, icon `shopping-bag`). Every cross-link in the EN articles (`customer-360`, `shared-audiences`, `automation-rules`, `flow-builder`, `labels`, `custom-attributes`, `contacts`, `whatsapp-campaigns`, the six sibling keys) resolves to an existing key (checked by listing `doc/en/*/<key>.md`). All seven keys are in `fe/helper/documentationLinks.js:64-70`; `customer360` (line 70) has **no consumer anywhere in the dashboard** (grep of `app/javascript`), so the Overview tab has no in-product link to its article.

## 2. Per-article verdict

| key | verdict | reason | evidence |
|---|---|---|---|
| commerce-overview | **REWRITE** (three passages, rest stands) | States Lynomia Chat "remembers nothing beyond a short cache" (L9-10), "a webhook carries no data" (L38-39) and "there is no commerce report" (L50); all three are inaccurate. Also repeats the provider-support wording that carts are "not available on any platform" without saying why. | §3 D3, D4, D6 |
| commerce-provider-support | **REWRITE** | The Salla "live updates: yes" cell contradicts matrix `m01` (blocker by the brief's rule); the "Not in production on any platform" block says "switched off everywhere / no setting" while WooCommerce actions are live and an ENV override exists; "Find an order ... still searches the others" is surface-dependent; the opening claim "implements only what a platform documents and confirms" is contradicted by the code's own `VERIFY` markers. | §3 D1, D5, D7, D9, D10 |
| connect-woocommerce | **EXPAND** | Accurate and the best-evidenced article (the only provider with a real captured fixture, `m01:45`), but it is the only platform with live write actions and nothing explains how to *run* an action, the WooCommerce version needed for "resend", or what happens when WordPress cannot reach the webhook URL. | §3.4, §4 |
| connect-salla | **KEEP** (4 small edits) | Core claims verified. Edits: drop "permanently ... none planned" (roadmap promise, unverifiable); unpaid Salla orders read "Unpaid", not "Payment not confirmed"; "other stores are still searched" is true only from the Overview tab; say nothing about live updates until D1 is arbitrated. | §3.4 |
| connect-zid | **REWRITE** (two sentences) | "Subscribes to three Zid events" (L11) and "the three event subscriptions" (L94) are wrong: the code subscribes to five. "Those events carry no order data" is wrong about what Zid sends. | §3 D2 |
| connect-shopify | **KEEP** (1 sentence) | The retirement fix held; all Shopify behaviour claims verified. Only L11's second sentence ("If you connected a store here before, nothing changes") is ambiguous and, read as covering the retired integration, false. | §3.3, §3.4 |
| customer-360 | **SPLIT**, then REWRITE the parts | ~1,000 words covering three tasks (read the Overview tab, link/unlink a store customer, find an order). Contains three wrong statements (L70 "no commerce report anywhere", L83 "in a store's view ... across your stores", L90-91 "a disabled store ... is listed without data") and one overstated storage claim (L35, L92). | §3 D3, D4, D8 |

No article is a RETIRE, MERGE or RELOCATE candidate. The four `connect-*` articles share a skeleton on purpose and describe different procedures; merging them would lose that.

## 3. Accuracy against the product

### 3.1 Defect register

Severity follows the brief: a doc that says a capability works for a provider whose matrix says otherwise is **blocker**. Where the matrix itself is contradicted by the code, that is stated and flagged for arbitration rather than silently resolved.

| ID | Sev | Where (EN; AR same unless noted) | Defect | Evidence |
|---|---|---|---|---|
| D1 | **blocker (needs arbitration)** | commerce-provider-support.md:29; AR :131 | The table says live order updates work on Salla ("yes"). Matrix `m01` says Salla WEBHOOKS is "UNSUPPORTED (Lynomia: registers none)" (`m01:76`) and REALTIME is "UNSUPPORTED (no webhooks)" (`m01:83`). The code supports it **only if the Salla app is subscribed to store events in the Salla Partner Portal**: `svc/providers/salla.rb:47` `supports_realtime? = true`, `svc/providers/base.rb:54` `registers_webhooks? = false` (inherited, Lynomia never subscribes), `custom/app/jobs/commerce/salla/webhook_job.rb:13,18` handles `order.` / `shipment.` events, and `svc/providers/salla.rb:70-73` marks the payload shape `VERIFY(salla-store-events)` ("unconfirmed on a live store"). `m05:59,61`, `docs/commerce/24-realtime-architecture.md:56,70` and report `046-salla.md:157-163` agree with the code. So `m01` is stale on this row, but the doc's unconditional "yes" is still unsupported: it hides an operator-side prerequisite and an unverified payload. `connect-salla.md` never mentions live updates at all. Shopify has the same structural dependency (`svc/shopify/webhook.rb:1-4`, subscriptions live in the app's `shopify.app.toml`) but `m01:76` classes it supported. Zid and WooCommerce register their own webhooks and are fine. |
| D2 | major | connect-zid.md:11-13, :94; AR :110-112, :187-188 | "Subscribes to three Zid events" and "the three event subscriptions" are wrong. `svc/zid/webhooks.rb:12-13` subscribes to `order.create`, `order.status.update`, `order.payment_status.update` **plus** `abandoned_cart.created` and `abandoned_cart.completed` (`svc/providers/zid/cart_events.rb:26`), five in all, removed together on disconnect (`svc/zid/webhooks.rb:34-36`). A merchant counting webhooks in the Zid dashboard sees five. Cart deliveries are accepted but not stored while carts are PRE_UAT (`svc/cart_lifecycle.rb:32,44`). "Those events carry no order data" is also wrong about what Zid sends: they "carry the order at the top level, with its customer" (`svc/providers/zid.rb:87-88`); Lynomia reads only the customer id and keeps nothing (`svc/providers/base.rb:49`). Matrix `m01:79,81` is also wrong here (says Lynomia does not subscribe to Zid cart events). |
| D3 | major | commerce-overview.md:9-10; customer-360.md:35, :92; AR overview :9-10 | "Lynomia Chat keeps no copy of your orders ... remembers nothing beyond a short cache" and "nothing is copied onto the contact / nothing here is stored" are overstated. The cache is 120 s fresh, 24 h stale (`svc/cache.rb:8-10`), but Lynomia also persists, per customer link, a summary row (`commerce_contact_metrics`: order count, active count, last purchase, spend per currency, order/payment/shipment status sets, fetched time) and per-order hashed state (status, payment status, shipment statuses, created-at) so automation can detect changes: `custom/app/models/commerce/contact_metric.rb:1-8,32-51`, `custom/db/migrate/20261002100000_create_commerce_contact_metrics.rb`, `custom/db/migrate/20261003100100_add_order_states_to_commerce_contact_metrics.rb`. The corpus contradicts itself: `doc/en/audiences-and-campaigns/shared-audiences.md:59` says "Commerce conditions read what Lynomia Chat has already stored locally", and commerce-overview.md:40 itself says filters "read what was last read". What is true and worth saying: no orders, items, addresses or payments are stored (migration comment), only counts, dates, totals and statuses, and the row goes when the link is removed (`contact_metric.rb:7-8`). |
| D4 | major | commerce-overview.md:50; customer-360.md:70; AR overview :49, AR customer-360 :72 | "There is no commerce report" / "no commerce report anywhere in Lynomia Chat" is false. **Analytics → Commerce** exists: sidebar entry `fe/components-next/sidebar/Sidebar.vue:670-674`, route `fe/routes/dashboard/analytics/analytics.routes.js:57-62`, API `config/routes/analytics.rb:19`, data `custom/app/services/analytics/commerce/overview.rb`. What *is* true is the second half: it reports cart and order-action counts and deliberately no revenue, GMV or per-currency total (`custom/app/services/analytics/commerce/metrics.rb:9-12`, "NO REVENUE, GMV OR PROFIT"). The page is documented nowhere in the corpus (only campaigns analytics are mentioned). Corroborated by `043-commerce-core.md` §10. |
| D5 | major | commerce-provider-support.md:41-43; connect-salla.md:62-64; customer-360.md:83-86 | "Find an order ... still searches the others" and "in a store's view, looks up an exact order number across your stores": the search is scoped by where you open it. In a single store's view it passes that store's id and searches **only that store** (`fe/components/widgets/conversation/commerce/CommercePanel.vue:558-562`, `fe/api/commerce.js:68-74`, `ctl/conversations/commerce/orders_controller.rb:21` honours `store_id`); only the Overview tab's search (`CommercePanel.vue:376-379`, no store id) spans stores. In a Salla store's own view the result is just "order search isn't available for this store" (`fe/i18n/locale/en/commerce.json:97`, `svc/order_search.rb:30`). |
| D6 | major | commerce-overview.md:38-39 | "A webhook carries no data ... The webhook body itself is discarded." Providers' bodies do carry order and customer data (names, emails, phones: `svc/webhook_queue.rb:5-6`); Lynomia reads only the customer ids (`svc/providers/base.rb:46-49`), encrypts the body for the queue and keeps nothing. Say that, not "carries no data": a data-protection reader will rely on this sentence. (Cart events are different: they write `Commerce::Cart` rows when carts are enabled.) |
| D7 | major | commerce-provider-support.md:68-71; description line 3 | The block "Not in production on any platform" opens "Two things ... are switched off everywhere. They are held in code, so no setting turns them on." Its first row exempts WooCommerce (actions *are* live there, default-on with per-store opt-in: `svc/switches.rb:21-24` default `provider == 'woocommerce'`), so "everywhere" is wrong; and "no setting" is imprecise: `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` is exactly such a setting (ENV-only, staging, `svc/switches.rb:39-41`; the held list is `svc/switches.rb:16`). |
| D8 | major | customer-360.md:90-91; AR :94-95 | "A disabled store, or one waiting for re-authorization, is listed without data." A **disabled** store is not listed at all: the overview reads only `active` and `needs_reauth` stores (`svc/customer360.rb:43`); a switched-off *provider* is listed as "Provider currently unavailable" (`svc/customer360.rb:89`, `fe/i18n/locale/en/commerce.json:85`). The Commerce section of a conversation also lists only active stores of enabled providers (`ctl/conversations/commerce/stores_controller.rb:54-56`, `active_stores`). |
| D9 | major | commerce-provider-support.md:8-10 | "Lynomia Chat implements only what a platform documents and confirms." Contradicted by the code's own markers: `VERIFY(salla-store-events)` (`svc/providers/salla.rb:70-73`), the `@idempotent` directive "VERIFY on a live store" (`svc/providers/shopify/actions.rb:38-39`), Zid cancel status name "VERIFY" (`svc/providers/zid/actions.rb:6`), Zid cart identity/envelope UNVERIFIED (`svc/providers/zid/cart_events.rb:11-20`). Provenance per `m01:43-51`: only WooCommerce has a real captured response; Salla, Zid and Shopify fixtures are hand-authored, no provider UAT has run, and `m05:68` records Salla, Zid and Shopify production as NO-GO. Nothing in the seven articles tells a reader on an installation that has enabled those platforms that they have not been verified against a live store. |
| D10 | minor | commerce-provider-support.md:55-56; connect-woocommerce.md:71-74 | "Resend payment link: yes" (WooCommerce) is stated without caveat. `m01:75` records it as "SIM (no spec performs it)"; the endpoint needs WooCommerce 9.8+ (`docs/commerce/29-provider-action-capabilities.md:46`; no version check exists in code: grep for `9.8` finds only that doc). Shopify refund also has an undocumented constraint, one payment transaction only (`svc/providers/shopify/actions.rb:112`), though it is held. |
| D11 | minor | commerce-provider-support.md:20-21 | "Matched by email: yes" for all four reads as if email matches link automatically. Email and the contact's phone field only ever produce *suggestions* an agent confirms (`svc/customer_matcher.rb:54-65`, `customer-360.md:49-51` says so correctly). Only the conversation's own channel phone auto-links, and only from a fresh read (`svc/customer_matcher.rb:46-52`, `:77-86`); neither nuance is stated. |
| D12 | minor | connect-salla.md:12-13; commerce-provider-support.md:59 | "Read-only, permanently ... none are planned." Read-only is verified (`svc/salla/tokens.rb:3-7,22-28` refuses any token with a write scope; `svc/providers/salla.rb:1-3`), but "permanently" and "none planned" are roadmap promises no code can prove. |
| D13 | minor | commerce-provider-support.md:78-79 | "see WhatsApp campaigns for the two types that exist": the target article describes one shape (one template, once, at a scheduled time; `doc/en/audiences-and-campaigns/whatsapp-campaigns.md:8-11`) and never names two types. Unverified. |
| D14 | minor | connect-woocommerce.md:58-59 etc. | Docs say "a custom role that includes order management"; the actual permission label is "Manage store orders (status changes, resend store emails)" (`fe/i18n/locale/en/customRole.json:34`, documented correctly in `doc/en/workspace/roles-and-permissions.md:37`). |
| D15 | minor | quotes of UI strings | Several quoted UI strings are partial: "This Salla store is connected to another account." (UI: "...another {installationName} account. Disconnect it there first.", `fe/i18n/locale/en/commerce.json:256`); "The store rejected the credentials." (UI: "...rejected {installationName}'s credentials. An administrator needs to reconnect the store.", `:134`). |

### 3.2 Reconciliation of `commerce-provider-support.md` with the matrix and the code

`m01` = production matrix (dated 2026-10-12, claims "verified against HEAD"), `m05` = Phase 7-10 matrix. Two rows of `m01` are stale against the code (Salla WEBHOOKS/REALTIME, Zid CART CREATED/RECOVERED), so the code was used as the tie-breaker (the matrix's own rule, `m01:3-5`, is that the code wins over recorded history).

| Doc row (EN line) | WooCommerce | Salla | Zid | Shopify | Verdict |
|---|---|---|---|---|---|
| Orders beside the conversation (:19) | yes; `svc/providers/woocommerce.rb:62-70` | yes; `salla.rb:42-45` | yes; `zid.rb` `list_customer_orders` | yes; `shopify.rb:83-93` | confirmed. `m01:67`: only WooCommerce is REAL evidence (D9). |
| Matched by verified phone (:20) | `woocommerce.rb:53-60` | `salla.rb:31-40` | `zid.rb:33-41` | `shopify.rb:73-81` | confirmed. Channels that count: WhatsApp, SMS, Twilio SMS only (`svc/customer_matcher.rb:33-42`). |
| Guest checkouts (:22) | yes, email or phone (`woocommerce.rb:53-65`) | no (registered customers only, `salla.rb:31-40`) | no (`svc/providers/zid/normalizer.rb:43-45`) | yes, email only (`shopify.rb:73-81,196-201`; no phone filter, header `:8-12`) | confirmed |
| Shipments and tracking (:23) | no; `woocommerce/normalizer.rb:14` ("tracking is always nil") | yes; `salla.rb:101-104`, `salla/normalizer.rb:53` | yes, one per order; `zid/normalizer.rb:65-87` | yes; `shopify/normalizer.rb:73-93` | confirmed; `m01` TRACKING row agrees |
| Can show shipped / delivered (:24-25) | no; `woocommerce/normalizer.rb:17-20` has neither | yes; `salla/normalizer.rb:12-15` | yes; `zid/normalizer.rb:16-19` | yes; `shopify/normalizer.rb:15-18,65-71` | confirmed |
| Can show paid, counts to spend (:26) | yes; `woocommerce/normalizer.rb:74-79` | **no**; `salla/normalizer.rb:74-76` (only unpaid/unknown) | yes; `zid/normalizer.rb:20` | yes; `shopify/normalizer.rb:19-22` | confirmed. Spend counts `payment_status == 'paid'` only (`svc/customer360.rb:22-27`). |
| Link to order in store admin (:27) | yes; `woocommerce.rb:83-88` | yes, only when Salla returns `urls.admin` on `s.salla.sa` (`salla/normalizer.rb:23,104-109`) | no; `zid/normalizer.rb:35`, header `:14` | yes; `shopify.rb:175-180` | confirmed (Salla conditional) |
| Find an order by number (:28) | yes; `woocommerce.rb:79-80` | no; `base.rb:30` default, no override in `salla.rb` | yes; `zid.rb:57` | yes; `shopify.rb:102-108` | confirmed (surface-dependent, D5) |
| Live updates (:29) | yes with Read/Write key; `woocommerce.rb:16-20,94-108` | **D1** | yes; `zid.rb:59`, `svc/zid/webhooks.rb:12-13`; `m01:76` supports | yes if app subscriptions exist; `shopify.rb:110`, `svc/shopify/webhook.rb:9-11` | **conflict on Salla** |
| Change status (:52) | processing to completed/on hold, on hold to processing; `woocommerce/actions.rb:20` | none | shipped then delivered; `zid/actions.rb:14` | none; `shopify/actions.rb:12` | confirmed; `m01` ORDER STATUS agrees |
| Cancel (:53) | pending, on hold; `woocommerce/actions.rb:22,92` | none | no; `zid/actions.rb:6` | unpaid and unfulfilled; `shopify/actions.rb:17,100-106` | confirmed |
| Refund (:54) | yes up to refundable; `woocommerce/actions.rb:102-110` | none | no; `zid/actions.rb:7` | yes, single payment only; `shopify/actions.rb:108-119` | confirmed (+D10) |
| Resend details / payment link (:55-56) | yes; `woocommerce/actions.rb:57-58,86-87` | none | no | no; `shopify/actions.rb:12` | confirmed (+D10) |
| Change shipping/address (:57) | no | no | no | no | confirmed; `woocommerce/actions.rb` header "update_shipping unsupported" |
| Actions held on Salla/Zid/Shopify (:75) | live, opt-in per store (`switches.rb:21-24`) | `supports_actions?` false (`base.rb:66`); tokens refuse writes | PRE_UAT (`switches.rb:16`) | PRE_UAT | confirmed (but see D7 wording) |
| Carts held (:76) | `supports_carts?` false (`base.rb:87`) | PRE_UAT | PRE_UAT | PRE_UAT | confirmed: `svc/switches.rb:16,28-31`, `svc/abandoned_carts.rb:19-21`; ingestion is gated by the same check (`svc/cart_lifecycle.rb:44-46`) |
| Platform availability (:83-88) | always on (`Base.enabled?`, `base.rb:6`) | `SALLA_ENABLED` default false (`config/installation_config.yml:465-468`) | `ZID_ENABLED` default false (`:492-495`) | `SHOPIFY_COMMERCE_ENABLED` default false (`:512-517`) | confirmed |
| Protected Customer Data (:87) | n/a | n/a | n/a | `svc/shopify/graphql.rb:6,62-64`; `m01:96,105` | confirmed |
| Per-platform limits (:92-97) | Order id numbering `woocommerce.rb:79` | per-store backoff `salla.rb:106-123` | 60 req/min `zid.rb:12` (provider fact; comment only) | 60-day window `shopify.rb:13`, `svc/shopify/config.rb:12-14`; no names `shopify/normalizer.rb:12,51` | confirmed in code; the two provider facts need provider citations from 044/047 |

### 3.3 The known integrations/commerce contradiction: it stayed fixed

History: the legacy Shopify integration was retired in `f4e81c84` (2026-10-12 15:25), which rewrote `connect-shopify` in both locales but missed `integrations.md`; `309d7a20` (2026-10-12 21:36, "one Shopify product, in both locales") then removed the "There are two Shopifys" paragraph, the catalogue row, the "shown when" row, the troubleshooting entry, and moved the Limits bullet. Re-verified today at HEAD:

| Check | Result | Evidence |
|---|---|---|
| "two Shopifys", "older", "legacy", "Settings → Integrations → Shopify", "ENABLE_SHOPIFY" anywhere in EN/AR corpus or changelog | none (only the unrelated "older than 60 days" in connect-shopify.md:40,55,95) | grep over `doc/{en,ar}` and `custom/db/changelog` |
| Integrations count | "Ten" (EN :8) / "عشرة" (AR :8) = 10 apps declared | `config/integration/apps.yml:13,20,26,60,68,75,92,177,215,257` |
| Shopify listed as a Commerce platform, not an integration | yes: integrations.md:88, AR :82; links to `connect-shopify` at :94 / AR :88 | files |
| `connect-shopify` says it is the only Shopify integration | yes, :11 (EN), :101 (AR) | file |
| "Already connected" troubleshooting matches the product | yes: "This store is already connected." (connect-shopify.md:84-86) equals `fe/i18n/locale/en/commerce.json:143`; the legacy-hook guard is gone from `ctl/commerce/shopify_connections_controller.rb:22-32` | files |
| Legacy surface actually removed in code | yes: routes `config/routes/commerce.rb:56-61` carry the retirement note; hook creation answers 404 (`app/controllers/api/v1/accounts/integrations/hooks_controller.rb:49-61`); settings page only `shopify_commerce` (`app/helpers/super_admin/features.yml:120-125`); `apps.yml` has no shopify key | files |

What the docs now say about the retired path: only that Commerce is "Lynomia Chat's only Shopify integration" (connect-shopify.md:11). One residual defect: the next sentence, "If you connected a store here before, nothing changes", is ambiguous. If "here" means the retired Settings → Integrations path it is false (the legacy panel was deleted, `docs/product-refinement/02-shopify-retirement.md` §2.4; the retirement doc §5 records that no Shopify stores exist in production). If "here" means Commerce it says nothing. Recommend deleting the sentence.

Residuals outside the corpus that still describe the retired path (not a documentation defect, reported because the brief asked what the product says): `config/installation_config.yml:510-511,515,520` (Super Admin setting descriptions: "separate from the legacy Shopify integration above", "The legacy Shopify integration is not affected", "not the legacy Shopify integration app") and `svc/shopify/webhook.rb:3-4` (comment: "The legacy Shopify integration keeps /webhooks/shopify"). The `SHOPIFY_*` legacy keys are gone, so these descriptions point at nothing.

One adjacent **cross-section contradiction found while checking**: `doc/en/automation/automation-rules.md:44` says "Shopify has no cancelled one" (a cancelled-order trigger). The code produces `cancelled` for Shopify whenever `cancelledAt` is set (`svc/providers/shopify/normalizer.rb:66`), and connect-shopify.md:64-65 lists *cancelled* among Shopify's statuses. The claim comes from the product's own recipe note (`fe/i18n/locale/en/recipes.json:189`, `fe/recipes/index.js:20`). The code agrees with connect-shopify; the recipe note and automation-rules.md look wrong. Needs arbitration (agents 036/055).

### 3.4 Claim register (everything else checked)

`confirmed` unless marked.

| Article | Claim (line) | Evidence | Verdict |
|---|---|---|---|
| overview | Fresh 120 s; stale up to 24 h, labelled with fetch time (:30-32) | `svc/cache.rb:8-10,20-26`; stale only for `STORE_UNAVAILABLE`, `TIMEOUT`, `RATE_LIMITED`, `INVALID_RESPONSE` (`:10`); a rejected key purges the cache instead (`svc/store_connection.rb:80-86`), which matches the "re-authorization" entry (:104) | confirmed |
| overview | Latest 5 orders, spend = paid orders per currency, never converted (:36-37) | `svc/conversation_panel.rb:9`, `svc/customer360.rb:22-27` | confirmed |
| overview | No scheduled import (:29) | `config/schedule.yml:79-83` has only the action sweep (reads stores to settle lost action jobs) | confirmed |
| overview | Contact filters list (:19) | `custom/app/services/audience/commerce_condition.rb:14-24` (store, provider, orders count, last purchase, active order, order/payment/shipment status, spend per currency) | confirmed (omits "has an active order") |
| overview | Seven automation triggers (:20) | `svc/order_transitions.rb:22-29` | confirmed |
| overview | Flow lookup step, own latest order or quoted number (:21) | `custom/app/services/flows/nodes/commerce_lookup.rb:1-11,28-46` | confirmed |
| overview | WooCommerce order-action menu once an admin turns it on (:22) | `svc/order_actions.rb:100-107` (store_blocker), `svc/switches.rb:21-24` | confirmed |
| overview | Roles table (:73-78) | `custom/app/policies/commerce/store_policy.rb:1-18`, `action_policy.rb:8-30`; "any agent who can see the conversation" (`ctl/conversations/commerce/stores_controller.rb:1-11` comment, `:54-56`) | confirmed |
| overview | One store per account; plan limit; disconnected stops counting (:82-83) | `svc/store_connection.rb:130-133,137-145`; `custom/app/models/commerce/store.rb:42` | confirmed |
| overview | Disconnect deletes credentials and links, contacts untouched (:87-88) | `svc/store_connection.rb:96-108` | confirmed |
| overview | Plan feature required (:58) | `ctl/commerce/stores_controller.rb:14,50-52` (`lynomia_commerce`) | confirmed |
| connect-woocommerce | Three webhooks, named "Lynomia Commerce", write key needed, Read key creates none (:20-22, :78-79) | `svc/providers/woocommerce.rb:12-13,94-108,156-160`; disconnect deletes them (`:110-118`) | confirmed |
| connect-woocommerce | WooCommerce disables webhooks after five refused deliveries (:79) | stated only in a comment (`woocommerce.rb:110-111`) and `m05:30` | unverifiable in code (provider fact; 045 to cite) |
| connect-woocommerce | https, domain name, standard port; IP/private network refused; redirect (:33-34) | `svc/store_url.rb:33-35,43-56`; `fe/i18n/locale/en/commerce.json:168-174` | confirmed (a `COMMERCE_TRUSTED_STORE_HOSTS` ENV exception exists for dev) |
| connect-woocommerce | Test before saving: API answers as v3, lists orders and customers (:46-48) | `woocommerce.rb:36-47`, `svc/store_connection.rb:14-20` | confirmed |
| connect-woocommerce | No shipments, never shipped/delivered (:67-68) | `woocommerce/normalizer.rb:14,17-20` | confirmed |
| connect-woocommerce | Action list, never trash, refund via gateway or recorded only (:71-76) | `woocommerce/actions.rb:20-22,57-58,102-123`; `fe/i18n/locale/en/commerce.json:395-397` | confirmed |
| connect-woocommerce | Keys encrypted, "Replace keys" tests first (:77) | `store.rb` `encrypts :credentials`; `svc/store_connection.rb:41-54` | confirmed |
| connect-woocommerce | Cancel/Refund never granted by a custom role (:103) | `action_policy.rb:23-29` | confirmed |
| connect-woocommerce | Webhooks recreated on the next successful save (:100) | `svc/store_connection.rb:52` | confirmed |
| connect-salla | Code: 16 chars in groups of four, shown once, works once, 1 h, new code cancels previous, case/space/dash ignored (:25-30) | `svc/salla/connection_code.rb:6-13,20-21,25,30-38` | confirmed |
| connect-salla | Nothing stored until Salla confirms with a signed event (:32) | `svc/store_connection.rb:1-4`; signature check `svc/salla/webhook.rb:11-15`, `custom/app/controllers/webhooks/salla_controller.rb:7-15` | confirmed |
| connect-salla | Never reads as paid (:56-59) | `salla/normalizer.rb:74-76` | confirmed, but unpaid orders read "Unpaid" (`fe/.../commerce.json:115`), not "Payment not confirmed" (D-edit) |
| connect-salla | Shipments with courier, status, tracking link when trackable (:67-68) | `salla.rb:101-104`, `salla/normalizer.rb:48-55` | confirmed |
| connect-salla | Guests not matched (:65-66) | `salla.rb:31-40` | confirmed |
| connect-salla | Rate limit serves last answer (:70-71) | `salla.rb:106-123`, `svc/cache.rb:10` | confirmed |
| connect-salla | Troubleshooting strings (:82-97) | `fe/i18n/locale/en/commerce.json:252-261` | confirmed (D15) |
| connect-zid | OAuth in same browser, none via browser (:8-9, :28-29) | `svc/oauth_state.rb`; cookie pattern as `ctl/commerce/shopify_connections_controller.rb:44-49` | confirmed |
| connect-zid | Number = Zid order id; Find an order types it (:41-42) | `zid/normalizer.rb:33`, `zid.rb:57` | confirmed |
| connect-zid | Two status steps held; no cancel, no refund (:51-54) | `zid/actions.rb:6-7,14`; `switches.rb:16` | confirmed |
| connect-zid | Marketplace / masked values never match (:55-58) | `zid/normalizer.rb:10,43-45,129-140` | confirmed |
| connect-zid | No admin link; copy button instead (:61-62) | `zid/normalizer.rb:35`; `fe/.../CommerceOrderItem.vue` `copyNumber`; `fe/i18n/locale/en/commerce.json:52` | confirmed |
| connect-zid | One shipment from the shipping method (:63-64) | `zid/normalizer.rb:65-87` | confirmed |
| connect-zid | Payment paid/unpaid/refunded only (:65-66) | `zid/normalizer.rb:8-9,20` | confirmed |
| connect-zid | 60 requests/minute (:67) | `zid.rb:12` comment | unverifiable (provider fact) |
| connect-zid | Dates in the store-profile time zone (:69) | `zid/normalizer.rb:13,23-26` (falls back to Asia/Riyadh when the profile has none, undocumented) | confirmed |
| connect-shopify | Domain rules, myshopify only (:18-19, :81-82) | `ctl/commerce/shopify_connections_controller.rb:25-26`; `fe/.../commerce.json:174` | confirmed |
| connect-shopify | Asks to read customers and orders only (:29) | `svc/shopify/config.rb:15` (`write_orders` only on an explicit reconnect, `:18`, held) | confirmed |
| connect-shopify | Same browser (:32) | `ctl/commerce/shopify_connections_controller.rb:30,44-49` | confirmed |
| connect-shopify | 60-day window (:54-55) | `shopify.rb:13`; `svc/shopify/config.rb:12-14` | confirmed (provider fact) |
| connect-shopify | Cancel/refund implemented but held (:56-59) | `shopify/actions.rb:29-47`; `switches.rb:16` | confirmed |
| connect-shopify | No customer name; guests email only (:60-63) | `shopify/normalizer.rb:12,51,116`; `shopify.rb:8-12,73-81` | confirmed |
| connect-shopify | Status vocabulary incl. "delivered once every shipment is delivered, no completed" (:64-65) | `shopify/normalizer.rb:15-18,65-71` | confirmed |
| connect-shopify | Payment vocabulary; authorized/voided/expired read "Payment not confirmed" (:66-67) | `shopify/normalizer.rb:8-9,19-22`; `fe/.../commerce.json:120` | confirmed |
| connect-shopify | Query-cost throttling serves last answer (:68-69) | `shopify.rb:15-17,214-222`; `svc/cache.rb:10` | confirmed |
| connect-shopify | Disconnect removes Lynomia's access and links, nothing changes in Shopify (:97-98) | `svc/store_connection.rb:96-108`; no `release` override in `shopify.rb`; `fe/.../commerce.json:283` | confirmed |
| customer-360 | Overview appears only with more than one store (:8-10) | `fe/components/widgets/conversation/commerce/CommercePanel.vue:70` | confirmed |
| customer-360 | Table: stores, orders, last purchase (not draft/failed/cancelled), spend, activity, ten recent orders (:14-22) | `svc/customer360.rb:15,18-19,22-33,55-57,76-77`; labels `fe/.../commerce.json:57-87` | confirmed |
| customer-360 | Answers after about 15 s, one failing store never blanks the tab (:24-25) | `svc/customer360.rb:7,17,82-83` | confirmed |
| customer-360 | Link order: existing link, channel phone, then email/phone suggestions (:44-51) | `svc/customer_matcher.rb:33-65` | confirmed (+D11) |
| customer-360 | Unlink is remembered (:53-54) | `svc/conversation_panel.rb:49-55`, `svc/customer_matcher.rb:78` | confirmed |
| customer-360 | Refresh reads now then 30 s shared cooldown (:76-78) | `ctl/conversations/commerce/refreshes_controller.rb:8,34-36` | confirmed |
| customer-360 | Digits only, 10 searches/minute/agent, audited (:84) | `ctl/conversations/commerce/orders_controller.rb:8-9,37-50` | confirmed |
| customer-360 | Found order shown without its customer; tracking cannot be sent (:85-86) | `svc/order_search.rb:33-35`, `fe/.../CommerceOrderItem.vue:24-25,64-65` | confirmed |
| customer-360 | Unknown, not zero, for filters (:93-94) | `custom/app/models/commerce/contact_metric.rb:7`, `commerce_condition.rb:1-12` | confirmed |
| whole section | Salla live updates; Zid three events; no report; no stored copy; Find-an-order scope; disabled store | see D1-D8 | wrong or in conflict |

## 4. Missing articles

The section answers "what does a connected store give me" and "how do I connect platform X". It does not cover what an agent or administrator does *after* connecting. Questions below are ones a stuck user has today; each has a UI or code surface.

| # | Missing article | The question it answers | Evidence it exists in the product |
|---|---|---|---|
| 1 | Change an order from a conversation (WooCommerce) | "How do I mark an order completed, cancel it, or refund part of it? What is 'Still being processed'? Why can't I refund?" | `fe/components/widgets/conversation/commerce/CommerceOrderActions.vue`; strings `fe/i18n/locale/en/commerce.json:333-413`; rate limits 10/min/user, 30/min/store, 5 per 10 min/order (`svc/order_actions.rb:25`); troubleshooting only covers failures, not the happy path. This is the only provider with live writes and the highest-risk surface (money). |
| 2 | Manage connected stores | "How do I stop reading a store without deleting it? Rename it? Replace keys? Reconnect? What does the plan count show?" | `svc/store_connection.rb:41-108`; `fe/.../commerce.json:176-331` (states Active/Disabled/Needs re-authorization/Disconnected, "Stores on your plan: X of Y", "Order actions: on/off", "Live order updates on"). Facts are scattered across five articles. |
| 3 | Link or change a store customer | "Why does it say 'Possible match' / 'Several store customers match' / 'Customer not found'? How do I search?" | `fe/.../commerce.json:15-33`; `svc/conversation_panel.rb:94-101`; error codes `INVALID_QUERY`, `NOT_FOUND` (`:139,141`). Currently prose inside customer-360. |
| 4 | Read an order in the panel | "What do 'Pending payment', 'Payment not confirmed', 'Preparing shipment' mean? What do View order, Track shipment, Send tracking and the number button do?" | Status vocabularies `fe/.../commerce.json:100-131`; `CommerceOrderItem.vue`. Vocabulary is explained per provider but never as one reference. |
| 5 | Analytics → Commerce | "What does the Commerce analytics page measure, and why is it all zero?" | D4; `Sidebar.vue:670-674`; the page is not gated on `lynomia_commerce` (`043-commerce-core.md` D4). The whole Analytics hub (Overview, WhatsApp, Campaigns, Automations, Flows, Commerce, Tickets) has no article in the corpus. |
| 6 | What Lynomia Chat stores about your store's customers | "Does Lynomia copy my orders? What is kept after I disconnect? What does a privacy request do?" | D3, D6; `svc/cache.rb`, `contact_metric.rb`, Shopify privacy topics (`svc/shopify/webhook.rb:10-11`). Replaces the false "keeps nothing" claim with a statement a DPO can use. |
| 7 | Abandoned carts and recovery messages | "What is the Abandoned carts queue and 'Prepare recovery message'?" | Held today, so no article is needed *yet*; the surfaces exist (`CommerceCarts.vue`, `CartQueue.vue`, trigger `commerce_cart_abandoned`, `svc/automation/commerce_events.rb`). Needed the day a provider leaves PRE_UAT (`switches.rb:16`: "through a reviewed code change"). |
| 8 | Customer not found / matching troubleshooting | "My customer exists in the store but the panel says not found." | `043-commerce-core.md` §9; belongs in `troubleshooting` (agent 060). |
| 9 | Installation operator guide for the Salla, Zid and Shopify apps | "Why is Salla not live-updating? Where do the app credentials and the webhook secret go?" | `config/installation_config.yml:465-581`; D1's Partner Portal subscription; `046-salla.md:211-213` reports the same gap. Audience is whoever runs the installation, not the account administrator; may belong outside the customer corpus. |

Small additions to existing articles: the WooCommerce version needed for "resend" (D10); webhook reachability for WooCommerce (`delivery_url = FRONTEND_URL/webhooks/woocommerce/:id`, `woocommerce.rb:170`); WooCommerce key shape `ck_` + 40 hex / `cs_` + 40 hex is enforced (`ctl/commerce/stores_controller.rb:12`), so a mistyped key is refused before any network call; an in-product link from the Overview tab to `customer-360`.

## 5. Quality

**Structure.** Strong and consistent. The four `connect-*` articles share one skeleton (intro, What you need first, Steps, A worked example, Who can do this, Limits, Related, If it does not work) and put the caveat that changes behaviour first. Headings are sentence-case `##`; the title lives in front matter. 800-1,000 words each is the right size for a task article.

**Task-orientation.** Good for connecting; weak for operating (see §4). `customer-360` is a concept article that smuggles in two tasks.

**Screenshots and media.** None (0 images in all 14 files). The WooCommerce key screen in WordPress, the Salla app-settings screen where the code is pasted, and the Zid / Shopify consent screens are exactly the steps that happen outside Lynomia and that users get wrong ("The dialog stays on 'Waiting for the code from Salla'").

**Front matter and SEO.** All fields present and well-formed. `description` and `seo_description` are all 100-155 chars (inside the audit's 50-160 band, `lynomia:docs:seo_audit`). Titles are 11-33 chars in EN and 7-19 in AR: valid, but "Connect Zid" / "Connect Salla" are poor search titles; no `seo_title` is used anywhere. Tags: `commerce` plus the platform; `customer-360` adds `contacts`; `commerce-overview` and `commerce-provider-support` carry only `commerce`. The tag vocabulary is minimal and gives no cross-section grouping (nothing links the section to `automation`, `audiences`, `analytics`).

**Duplication and drift.** The same facts are restated in 3-6 places ("latest 5 orders", "carts not available", "Salla never paid", "Find an order not available on Salla"). Drift has already happened: three facts changed after the docs were written on 2026-10-05 (Zid cart subscriptions, Analytics → Commerce, the persisted summary), because the later work (commits of 2026-10-06 to 2026-10-12) never touched the corpus. Recommendation for Phase 5: one canonical matrix (provider-support) and links from the others, not restated cells.

**Link hygiene.** EN links are all valid. AR: see §6, all 46 AR internal links point at the English slug.

**Contextual help.** `customer360` has no consumer (§1). The Overview tab, Analytics → Commerce and the order-action dialog have no help link.

## 6. EN/AR parity

Structural parity is exact: same number of `##` headings, tables and links in every pair (10/6/8/7/7/7/9 headings; 2/4/1/0/0/0/2 tables; links 17/7/3/4/3/3/9). Length parity is good (AR body 82-93% of EN words). Meaning parity is also very good: **every factual defect in §3 is replicated identically in AR**, so fixing the EN text requires the same edit in the AR file, and a reader of one locale is not told something different from a reader of the other.

Divergences in meaning (small, none contradict):

| Where | EN | AR | Note |
|---|---|---|---|
| provider-support, "Three rows deserve a sentence" | no status list | AR :135-137 adds the full WooCommerce status list (pending, processing, on hold, completed, cancelled, refunded, failed, draft) | AR is *more* informative and correct (`woocommerce/normalizer.rb:17-20`); EN lacks it |
| connect-woocommerce, "If it does not work" | one entry for read-only key (mentions "Turn on order actions" inside it, :99-101) | AR :94-97 splits it into two entries, adding "Turn on order actions is refused" | correct (`svc/order_actions.rb:100-107`, `svc/store_connection.rb:70-76`) |
| connect-woocommerce, webhooks (:78-79) | "A Read key cannot [delete them], so WooCommerce disables them itself after five refused deliveries" | AR :74-75 "if you reduced the key's permission, WooCommerce disables its webhooks after five refused attempts" | AR adds the scenario; EN is terser |
| customer-360, store-failure behaviour (:24-26) | no mention of the banner | AR :25 adds "*Some stores couldn't be refreshed* appears at the top" | matches `fe/.../commerce.json:76` |
| provider-support, limits table | one row per platform | AR splits WooCommerce (2 rows), Zid (2) and Shopify (2) | same content |

Terminology and UI-fidelity problems (for agent 061, listed here because they sit in this section):

1. **Brand names.** AR articles write "Salla" / "Zid" in Latin; the AR UI writes سلة / زد (`fe/i18n/locale/ar/commerce.json:6-7`), so the quoted strings do not match what the user sees: connect-salla (AR) :29 quotes «بانتظار وصول الرمز من Salla» while the UI says «بانتظار وصول الرمز من سلة…» (`fe/i18n/locale/ar/commerce.json:253`); connect-zid (AR) :123 says **الربط مع Zid** where the button is «الربط مع زد» (`fe/i18n/locale/ar/commerce.json:268`). Shopify and WooCommerce are Latin in both, which is fine.
2. **"Spend".** The AR UI label for the Spend line is «المدفوعات» ("payments", `fe/i18n/locale/ar/commerce.json:68`); AR docs use «المدفوعات» in the table (customer-360 :19) but «الإنفاق الظاهر» in titles, descriptions and headings (customer-360 :3, :58; overview :19). Same figure, two names; and «المدفوعات» is also the product's wording for payments generally.
3. **«المتجر» does double duty.** The UI names the Commerce section «المتجر» and also calls a single store «متجر»; the AR overview's first sentence ("يربط **المتجر** متجرك الإلكتروني") reads as a tautology. The UI's own choice; the docs inherited it.
4. **Internal links in AR point at the English article.** All 46 internal links in the 7 AR files use the bare key, e.g. `[عرض العميل الشامل](customer-360)`. Arabic articles live at `.../articles/<key>-ar` (`content_seeder.rb` `slug_for`; canonical form in `docs/global-documentation/16-regression-results.md:201`), the route has no locale segment (`config/routes.rb:519` `hc/:slug/articles/:article_slug`), the controller finds by slug only (`app/controllers/public/api/v1/portals/articles_controller.rb:80-83`), and nothing rewrites links (`lib/chatwoot_markdown_renderer.rb:13-19`, no `<base>` tag in `app/views/public`). A relative `customer-360` from an `-ar` page therefore resolves to the English article. Verified by reading route, controller and renderer, **not rendered in a browser**. This is a corpus-wide defect (agents 061/076), not only commerce; it is the single largest EN/AR parity problem found here because it silently moves an Arabic reader into English on every cross-link.
