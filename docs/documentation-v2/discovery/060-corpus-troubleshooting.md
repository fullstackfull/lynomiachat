---
agent: 060
scope: troubleshooting section of the corpus (7 articles x EN+AR, including the Platform Support Desk article contact-lynomia-support) classified, checked against code, analysed for article shape, with a proposed canonical troubleshooting-article pattern
confidence: high
---

# 060 — Corpus: `troubleshooting`

Read-only. All 14 files were read in full. Every checkable claim was traced to code and carries `path:line`. Every
string an article presents as "what you see" was tested with `rg -F` against the shipped locale files
(`app/javascript/dashboard/i18n/locale/{en,ar}/*.json`, `config/locales/{en,ar}.yml`). Nothing was run, rendered or
opened in a browser: where I say a page behaves a certain way (for example Arabic link targets) it is from reading
the route and controller. Claims that are about a provider (WooCommerce, Salla, Zid, Shopify, Meta) rather than
about Lynomia are marked `unverifiable` and routed, not resolved.

The headline, before the template sections:

1. **The five commerce articles open with a table of "what you see" strings, and none of the 19 strings exist in
   the product** (0 of 19 in `en/commerce.json`; the Arabic equivalents are translations of the invented English,
   not the Arabic locale). This is ledger item DC-14 (agent 056); I confirm it for every string and extend it in
   §3.2. The section's one promise — match what is on your screen to a cause — fails at its first step.
2. **Several articles state provider state Lynomia never received.** The sharpest: `NOT_APPLIED` is explained as
   "the store accepted the request", but the code can only produce that code after Lynomia *lost* the answer
   (`action_executor.rb:120`). The reconnect article names causes (key deleted, app uninstalled) that Lynomia
   inferred from a bare 401 or a refused or lost token refresh, and the uninstall it names actually takes a
   different path (`disconnected`, not `needs_reauth`). §3.4.
3. **Remedies are wrong or unreachable.** "Reconnect" is given for all four platforms (DC-15) but WooCommerce shows
   "Replace keys" and Salla shows no button. The Shopify and Zid scope remedies describe order actions that are
   held out of production (`switches.rb:16,21-26`). The address article's own four examples each produce a
   *different* message from the one it explains, it excludes Shopify (which also raises `INVALID_STORE_URL`) and
   tells Shopify merchants the opposite of what works.
4. **The best epistemic writing in the section is real and rare**: the "We do not know" section of the order-action
   article, and the support article's faithfulness to shipped UI strings. Nothing in the section tells the reader
   what Lynomia *recorded* versus what it *inferred*, and none of the five commerce articles has an escalation
   path (zero links to the ticket article; the hub does not link it either).
5. **The support article has four defects of its own** (§3.3, S1, S3, S9, S10): "two desks" above a three-row
   table; "a ticket needs all four" fields (two are required); a priority control the UI does not have; and a
   promise to "say so on the ticket" when priority is re-triaged, which the code makes impossible.

---

## 1. Inventory

`C` = `custom/db/documentation`. Words are **body words** (front matter excluded), whitespace tokens, counted with
Python. Registry keys are in `app/javascript/dashboard/helper/documentationLinks.js`.

| key | EN file | AR file | title (EN / AR) | position | EN words | AR words |
|---|---|---|---|---|---|---|
| `troubleshooting` | `C/en/troubleshooting/troubleshooting.md` | `C/ar/troubleshooting/troubleshooting.md` | When something is not working / عندما لا يعمل شيء | 10 | 859 | 747 |
| `contact-lynomia-support` | `C/en/…/contact-lynomia-support.md` | `C/ar/…/contact-lynomia-support.md` | Raising a ticket with Lynomia / فتح تذكرة مع لينوميا | 20 | 1000 | 806 |
| `commerce-store-needs-reconnecting` | `C/en/…/commerce-store-needs-reconnecting.md` | `C/ar/…/commerce-store-needs-reconnecting.md` | Your store needs to be reconnected / متجرك يحتاج إلى إعادة ربط | 60 | 460 | 355 |
| `commerce-store-unreachable` | `C/en/…/commerce-store-unreachable.md` | `C/ar/…/commerce-store-unreachable.md` | Lynomia cannot reach your store / لينوميا لا تستطيع الوصول إلى متجرك | 61 | 456 | 339 |
| `commerce-store-address-refused` | `C/en/…/commerce-store-address-refused.md` | `C/ar/…/commerce-store-address-refused.md` | The store address was refused / عنوان المتجر مرفوض | 62 | 404 | 332 |
| `commerce-keys-cannot-do-that` | `C/en/…/commerce-keys-cannot-do-that.md` | `C/ar/…/commerce-keys-cannot-do-that.md` | Your store keys cannot do that / مفاتيح متجرك لا تستطيع ذلك | 63 | 456 | 359 |
| `commerce-order-action-did-not-apply` | `C/en/…/commerce-order-action-did-not-apply.md` | `C/ar/…/commerce-order-action-did-not-apply.md` | An order action did not apply / إجراء طلب لم يُطبَّق | 64 | 601 | 436 |
| **section total** | 7 | 7 | | | **4236** | **3374** |

The section is the last of 12 (`manifest.yml:117-125`, position 110, icon `life-buoy`, EN "When something is not
working.", AR "عندما لا يعمل شيء كما ينبغي."). Article positions are 10, 20, 60–64; 30–50 are unused. Five of the
seven articles are commerce; the other two are the hub and the vendor desk. There is no troubleshooting article for
WhatsApp, Facebook, Instagram, email or the web widget in this section — WhatsApp has its own 14-article section
(`whatsapp-errors`, agent 054), and the others have none anywhere.

**Measurement hazard for every corpus agent (049–062).** In this shell's default POSIX locale `wc -w` counts Arabic
text roughly 4-5x low: `ar/…/commerce-keys-cannot-do-that.md` reports **89** words, while `LC_ALL=C.UTF-8 wc -w`
and `awk '{n+=NF}'` both report **415** (file including front matter). Any AR word count taken with plain `wc -w`
is wrong; the ratio AR/EN of 0.80 above is the true one.

**How readers reach each article** (inbound, computed from every `](key)` link in both locales plus the registry):

| key | inbound Markdown links (corpus) | inbound from the product |
|---|---|---|
| `troubleshooting` | 6 links from 4 articles, per locale (audit-logs, webhooks, your-first-conversation, contact-lynomia-support) | `troubleshooting` key (`documentationLinks.js:87`) |
| `contact-lynomia-support` | **0** (the hub does not link it) | `contactLynomiaSupport` (`:93`), three Help & Support pages |
| `commerce-store-needs-reconnecting` | **0** | `commerceStoreReconnect` via `commerceErrorArticle` only |
| `commerce-store-unreachable` | 2 (both from contact-lynomia-support) | same resolver |
| `commerce-store-address-refused` | **0** | same resolver |
| `commerce-keys-cannot-do-that` | **0** | same resolver |
| `commerce-order-action-did-not-apply` | **0** | same resolver |

`commerceErrorArticle` is consumed in exactly one place, the panel's read-error banner
(`CommercePanel.vue:406-417`, label "What to do about this", `commerce.json:55`). That banner shows `panel.error`,
which is a *read* error. The order-action dialogs, the Settings → Commerce store rows ("Needs re-authorization",
"Reconnect", "Replace keys") and the connect dialogs carry no link to any of the five (`rg DocsLink` under
`components/widgets/conversation/commerce` and `routes/dashboard/settings/commerce` finds only `CommercePanel.vue`
and the connect dialogs' own "how to connect" links; agent 043 logged the same in `_ARBITRATION.md` §CH). So the
action codes mapped at `documentationLinks.js:123-132` have a registry entry and no surface that uses it.

---

## 2. Per-article verdict

| key | verdict | reason | evidence |
|---|---|---|---|
| `troubleshooting` | **EXPAND** | The structure (four causes, then a symptom → first check → article table) is the best routing in the corpus and should stay. It needs a fifth cause (a connected store), links to the five commerce articles and to the ticket article, and corrections to two "nothing" rows. | §3.3 H6-H7; §1 inbound table; §5.2 |
| `contact-lynomia-support` | **SPLIT** | Three jobs in 1,000 words — how the desk works, what to put in a ticket, what a status means — and the product links all three questions to one URL with no anchor (`PlatformSupportNewPage.vue:79-82`, `PlatformSupportIndexPage.vue:148-151`, `PlatformSupportDetailPage.vue:280-283`; `DocsLink.vue:24-26` builds `href` from the key alone). Keep the key as the parent ("how the desk works"), add two keys. Four local defects need fixing in the same pass. The cheaper alternative is stable heading anchors plus an `anchor` prop on `DocsLink`; that is an IA decision (Phase 3), not a content one. | §3.3 S1-S10; `documentationLinks.js:88-93` records the one-article decision |
| `commerce-store-needs-reconnecting` | **REWRITE** | Wrong on-screen strings, one remedy stated for four platforms where three differ, a cause table that conflates uninstall (`disconnected`) with refresh failure (`needs_reauth`), a false "not a guess from a single failed request", and it advertises abandoned carts the sibling article says do not exist. | §3.2; §3.3 R2-R12; DC-15 |
| `commerce-store-unreachable` | **EXPAND** | The best-verified commerce article (timeouts, retry rule, stale fallback and "status unchanged" all confirmed). It needs the true strings, the 24-hour bound on the stale fallback, DNS and TLS as named causes, and the two codes the registry sends here that it never explains (`RATE_LIMITED`, `INVALID_RESPONSE`). | §3.3 U1-U11; `documentationLinks.js:112-115` |
| `commerce-store-address-refused` | **REWRITE** | Its examples do not produce its message; it says WooCommerce is the only platform where you type an address (Shopify also does, and gets the opposite advice); "no path" is wrong for a WordPress subfolder; port and bare-IP rules are not mentioned. | §3.3 A2-A7 |
| `commerce-keys-cannot-do-that` | **REWRITE** | Groups three codes with three different remedies under "keys" (a Shopify approval nobody on the customer side can obtain is not a key problem); its Shopify and Zid remedies target order actions that are held out of production; omits that a Read key also loses live updates and that "order actions off" has installation-level causes. Consider splitting `PROTECTED_DATA_NOT_APPROVED` into its own article. | §3.3 K2-K9; `switches.rb:16-26`; XA-02 |
| `commerce-order-action-did-not-apply` | **REWRITE** (table) / **KEEP** ("We do not know") | The conceptual core is right and unique in the corpus. Two table rows are wrong (`NOT_APPLIED`, `ACTION_UNAVAILABLE`), three are incomplete (`ACTIONS_DISABLED`, `ACTION_IN_PROGRESS`, `ORDER_CHANGED`), the opening "only thing Lynomia writes" is false, and `NOT_SENT`, `IDEMPOTENCY_CONFLICT` and the action-throttle `RATE_LIMITED` are mapped here and never explained. | §3.3 O1-O16 |

No article should be RETIRED or MERGED. **RELOCATE** is an open IA question, not a verdict: five of the seven
articles are commerce while a seven-article `commerce` section exists, and WhatsApp errors have their own section.
I recommend keeping the commerce articles here — the registry comment (`documentationLinks.js:87-93`) already argues
"that is where a stuck reader already is", the 31-code error surface collapses to five remedies and will not grow
the way Meta's does — and fixing the hub so it routes to them (agent 062 to decide).

