---
agent: 094
scope: Refute EN/AR equivalence across the 63-pair documentation corpus — prove where the Arabic says something different from the English
confidence: high
---

## 1. What you attacked

All 63 EN/AR pairs under `custom/db/documentation/{en,ar}/<section>/<key>.md`, compared on seven axes:
front matter fields, heading inventory and level, table rows, bullet and ordered-step counts, link
targets, numeric literals, and quoted UI labels. Quoted Arabic UI labels were then checked against the
product's own Arabic locale (`app/javascript/dashboard/i18n/locale/ar/*.json`), which is the only authority
on what an Arabic user actually sees. Two AR-only product claims were checked against the Ruby.

Three specific prior claims were attacked directly:

- Agent 031: `contacts.md` is 191 AR words against 1144 EN, read as a tokenization artefact.
- Agent 036: `automation-rules.md` is 211 against 1029, read the same way.
- Agent 057: `ar/workspace/roles-and-permissions.md:92` carries an AR-only claim that a custom role
  "cannot be reassigned" after a plan downgrade.

## 2. The extreme word-count question, settled

**Agents 031 and 036 reached the right conclusion from a wrong number, and the number is the one that got
written down.** The ratios are a `wc -w` locale artefact, not tokenization and not truncation:

```
$ LC_ALL=C      wc -w < ar/contacts/contacts.md   ->  191
$ LC_ALL=C.UTF-8 wc -w < ar/contacts/contacts.md   ->  923
$ python3 len(text.split())                        ->  923
```

This container runs `LC_CTYPE="POSIX"`. GNU `wc -w` in the C locale miscounts Arabic UTF-8; every Arabic
figure quoted in reports 031 and 036 — and any other report that used bare `wc -w` — is low by roughly a
factor of five. The giveaway was already in the data and went unremarked: **the Arabic files are *larger*
than the English in bytes** (`ar/contacts/contacts.md` 9138 bytes vs 6572), which is impossible for a file
holding one sixth of the words.

Recomputed over all 63 pairs with correct UTF-8 counting:

| metric | min | median | mean | max |
|---|---|---|---|---|
| AR words / EN words | 0.74 | 0.82 | 0.83 | 0.96 |
| AR chars / EN chars | 0.73 | 0.82 | 0.83 | 0.93 |

A 0.80–0.85 ratio is what a faithful Arabic translation of English prose looks like: Arabic attaches
articles, prepositions and pronouns as clitics, so it needs fewer whitespace-delimited tokens for the same
content. The word and character ratios track each other within 0.02 across the whole corpus, which is the
signature of uniform linguistic compression rather than of dropped content.

**Verdict on the two flagged pairs, as the brief demands, plainly:**

| pair | EN w | AR w | true ratio | verdict |
|---|---|---|---|---|
| `contacts/contacts.md` | 1148 | 923 | 0.80 | **faithful rendering** |
| `automation/automation-rules.md` | 1038 | 902 | 0.87 | **faithful rendering** |

Counts here are whole-file, to be directly comparable with the `wc -w` figures reports 031 and 036 quoted.
The table in §8 counts body words only (front matter excluded); the ratios are the same to two decimals.

Neither is condensed and neither is materially incomplete. `contacts.md` matches heading for heading (10/10),
table row for table row, and sentence for sentence through the intro, "How a contact comes to exist", "The
three identities" and "Phone numbers are stored in international form" — including the literal
`+96522201234` and `0551112233` examples and the fifteen-digit ceiling. `automation-rules.md` matches 11/11
headings. **The program's premise about Arabic being first-class survives on volume.** It does not survive
intact on accuracy — see §4.

Supporting evidence that the Arabic is genuinely authored rather than machine-padded: all 63 pairs have
**identical link-target multisets** (zero divergence), identical front-matter key sets, identical `position`
values and identical `tags` across all 63 pairs. The most-compressed pair in the corpus,
`troubleshooting/commerce-order-action-did-not-apply.md` at 0.74, is claim-for-claim complete — all nine
outcome rows, all nine machine codes (`ORDER_CHANGED`, `NOT_APPLIED`, `REFUND_DECLINED`, `PROVIDER_REJECTED`,
`ACTION_IN_PROGRESS`, `INVALID_AMOUNT`, `ACTIONS_DISABLED`, `ACTION_UNAVAILABLE`), all three numbered
read-back steps, all four closing bullets and the "four opportunities" count.

## 3. Quantified content parity

Word count was the wrong instrument. Structural and claim-level comparison is the right one:

| classification | pairs | share |
|---|---|---|
| Structure and emphasis counts identical, no substantive divergence found | 41 | 65% |
| Structure identical, emphasis count differs by 1–2 only | 14 | 22% |
| Structural divergence (headings, table rows, bullets, steps) | 8 | 13% |
| **Link targets divergent** | **0** | **0%** |

Collapsing that into a verdict per pair after claim-level review:

| verdict | pairs |
|---|---|
| FAITHFUL — no divergence found | 45 |
| REFORMATTED — content equivalent, presentation differs (prose↔list, section promotion) | 4 |
| DIVERGENT — at least one substantive divergence | 14 |

**Answer to the brief: the Arabic corpus is at parity in content volume across all 63 pairs, at parity in
structure for 55 of 63, and free of substantive divergence in 49 of 63. The remaining 14 pairs carry
divergences concentrated in exactly the places where being wrong costs most — navigation paths in
troubleshooting articles, the permissions matrix, and the corpus's central domain term.**

Parity of presence is not parity of meaning, and neither is parity of length.

## 4. Refutations

### R1 — AR tells Arabic readers a custom role cannot be reassigned after a downgrade. The code says it can. `blocker`

**Claim**: `ar/workspace/roles-and-permissions.md:92` — "الأدوار المخصصة قدرة مدفوعة. وعند تخفيض الخطة يمكن
إزالة دور مخصص مُسنَد لكن لا يمكن إسناده مجدداً." ("Custom roles are a paid capability. On a plan downgrade an
assigned custom role can be removed but cannot be reassigned.")

**Made by**: the Arabic corpus. Flagged by agent 057; **confirmed, and it is worse than 057 reported.**

**Why it is wrong, twice over.**

First, it is AR-only. The EN "Limits" list has five bullets (`en/workspace/roles-and-permissions.md:88-94`);
the AR has six (`ar/...:87-94`). The words "reassign" and "downgrade" appear nowhere in the English file —
its only plan-related statements are `en:63` ("on a plan without them the Custom Roles page is not shown")
and `en:110` ("Custom roles are not included on your plan").

Second, and decisively, **the claim is false against the code.** `feature_enabled?('custom_roles')` is
checked in exactly one place in the entire repository:

- `custom/app/controllers/api/v1/accounts/custom_roles_controller.rb:53` — `ensure_capability`, guarding the
  five actions that define role rows.

Attachment of a role to a person does not happen there. It happens on the agent endpoints, in
`custom/app/controllers/custom/api/v1/accounts/agents_controller.rb:22` (`before_action :validate_custom_role,
only: [:create, :update]`) and `:53-58` (`apply_custom_role`). That controller resolves the id inside
`Current.account.custom_roles` and 404s an id from another account — and **never consults the capability
flag**. There is no model-level guard either: `app/models/account_user.rb` carries `custom_role_id` with no
validation against the feature, and `custom/app/models/custom_role.rb:54` only has `before_destroy
:detach_memberships`.

So on a downgraded account: the page is hidden and the CustomRoles API refuses (the EN claim holds), but
`PATCH /api/v1/accounts/:id/agents/:id` with `custom_role_id` **still succeeds**. Removal works and
re-assignment works. An Arabic-only reader is told a restriction exists that does not.

**Siblings, same file, same theme — all AR-only:**

| AR | the AR-only text | EN counterpart |
|---|---|---|
| `ar:62` | "ولا يمكن إسناد دور مخصص قائم إلى أحد" — an existing custom role cannot be assigned to anyone | `en:63` stops at "the Custom Roles page is not shown" |
| `ar:57` | "ولا توجد طريقة أضيق لمنح ذلك" — there is no narrower way to grant that | `en:58-59` stops at "they have to be an administrator" |
| `ar:78` | "ولا يحصل على التقارير." — and it does not get Reports | the EN worked example (`en:76-79`) never says Reports is withheld |

`ar:62` is wrong for the same reason as `ar:92`. `ar:57` and `ar:78` are consistent with the EN's logic but
are still claims only one language's readers receive.

### R2 — Four Arabic navigation paths send a stuck user to a menu item that is not named that. `major`

The product's Arabic settings nav label for Commerce is **`المتجر`** — `app/javascript/dashboard/i18n/locale/ar/settings.json:358`, `"COMMERCE": "المتجر"`.

The Arabic corpus uses two different renderings for the single EN string "Settings → Commerce":

| AR rendering | files | correct? |
|---|---|---|
| `الإعدادات ← المتجر` | `ar/commerce/commerce-overview.md:64,102`, `ar/commerce/connect-salla.md:24`, `ar/commerce/connect-shopify.md:25,80`, `ar/commerce/connect-woocommerce.md:37`, `ar/commerce/connect-zid.md:23,26`, `ar/commerce/customer-360.md:117` | **yes** |
| `الإعدادات ← التجارة` | `ar/troubleshooting/commerce-keys-cannot-do-that.md:39`, `ar/troubleshooting/commerce-order-action-did-not-apply.md:22`, `ar/troubleshooting/commerce-store-needs-reconnecting.md:12,18` | **no** |

`التجارة` is the Arabic label for the *contact sidebar's* Commerce section (`ar/contact.json:680`) and for the
flow-builder group (`ar/flowBuilder.json:72`), not for the settings menu. The four wrong instances are all in
`troubleshooting/`, which is the worst possible place for a wrong menu name: the reader is already stuck, and
the instruction they are given ("المدير يشغّله في الإعدادات ← التجارة" —
`ar/troubleshooting/commerce-order-action-did-not-apply.md:22`, against `en/...:23` "an administrator turns it
on in Settings → Commerce") names a menu entry they will not find.

The Arabic corpus knows this is a trap and defuses it exactly once, nowhere else:
`ar/audiences-and-campaigns/shared-audiences.md:53` writes "المتجر (تظهر في المنتج باسم Commerce)" — "the
Store (appears in the product as Commerce)". That gloss is AR-only; `en/...:53` has a bare `| Commerce |`.
One file out of thirteen handles the ambiguity.

### R3 — Three of five Arabic "Account Health" references name a tab the product never shows. `major`

The Arabic UI **leaves this tab in English**: `app/javascript/dashboard/i18n/locale/ar/inboxMgmt.json:787`,
`"ACCOUNT_HEALTH": "Account Health"`. The EN corpus says "Account Health" in all five places. The AR says it
three different ways:

| AR | rendering | matches the product? | EN source |
|---|---|---|---|
| `ar/whatsapp/connect-whatsapp.md:61` | `Account Health` | **yes** | `en:64` |
| `ar/whatsapp/whatsapp-troubleshooting.md:56` | `Account Health` | **yes** | `en:59` |
| `ar/whatsapp-errors/whatsapp-error-131053.md:32` | `سلامة الحساب` | no | `en:34` |
| `ar/whatsapp-errors/whatsapp-number-status.md:9` | `سلامة الحساب` | no | `en:9` |
| `ar/whatsapp-errors/whatsapp-nothing-arrives.md:9` | `سلامة` | no, and truncated | `en:10` |

Same tab, same EN string, three Arabic names, two of them invented and one of them a fragment. All three
wrong ones are in `whatsapp-errors/`.

### R4 — The corpus's central domain distinction is reversed in Arabic, and the two Arabic articles that define it contradict each other. `major`

This is the most consequential divergence found, because it is about what the product *is*.

**EN** `en/getting-started/connect-your-first-channel.md:8-10`: "In the dashboard a channel appears as an
**inbox**: **the two words describe the same thing from different sides.** The channel is the connection to
the outside world; the inbox is where its conversations land."

**AR** `ar/getting-started/connect-your-first-channel.md:9-10`: "وفي لوحة التحكم تظهر القناة ضمن **قنوات
التواصل**، **ولها صندوق وارد خاص بها**: القناة هي الاتصال بالعالم الخارجي، وصندوق الوارد هو المكان الذي تهبط فيه
محادثاتها." — "the channel appears under Communication Channels, **and it has its own inbox**."

The English states that channel and inbox are **one object seen two ways** and goes out of its way to deny the
distinction. The Arabic states a **possession relation between two objects**. That is a different data model.

The companion article then goes the opposite way and contradicts it:

- `en/workspace/set-up-an-inbox.md:8`: "An **inbox** is one channel plus everything that governs it" — inbox
  as the superset.
- `ar/workspace/set-up-an-inbox.md:8`: "القناة في **قنوات التواصل** هي اتصال واحد بالعالم الخارجي، ومعه كل ما
  يحكمه" — the *channel* is the thing that carries the governance. The word "inbox" is gone; `ar:10` closes
  "الاتصال هو القناة، والإعدادات هي قراراتك حولها" ("the connection is the channel, and the settings are your
  decisions about it"), erasing the EN sentence's second term entirely.

So `ar/getting-started/connect-your-first-channel.md` says a channel *has* an inbox, and
`ar/workspace/set-up-an-inbox.md` says there is no inbox, only a channel. An Arabic reader who reads both
gets two incompatible models; an English reader gets one.

The root cause is that the Arabic corpus has no settled rendering for "inbox" and uses three:

| AR rendering | occurrences | files |
|---|---|---|
| `قنوات التواصل` / `قناة التواصل` | 49 | 22 / 9 |
| `صندوق الوارد` / `صندوق وارد` | 31 | 16 / 7 |
| `البريد الوارد` | 1 | 1 |

Only the first matches the settings nav (`ar/settings.json:353`, `"INBOXES": "قنوات التواصل"`). They are mixed
inside single sentences: `ar/getting-started/connect-your-first-channel.md:49` reads "اذهب إلى **الإعدادات ←
قنوات التواصل** واختر إضافة صندوق وارد" — "go to Settings → Communication Channels and choose Add inbox",
using both terms in one instruction, against `en:54` "Go to **Settings → Inboxes** and choose to add an
inbox."

### R5 — "VPN" is dropped from the Arabic troubleshooting corpus entirely. `major`

`en/troubleshooting/commerce-store-unreachable.md:33-35` enumerates three unreachable cases: "A store behind a
**VPN**, on a **private network**, or on a `localhost` **address**".

`ar/troubleshooting/commerce-store-unreachable.md:30-31` gives two: "المتجر خلف شبكة خاصة أو على عنوان محلي" —
"behind a private network or on a local address". **"VPN" appears nowhere in the 63-file Arabic corpus**
(`grep -rn 'VPN' ar/` returns nothing; the EN has it once). A merchant whose WooCommerce store sits behind a
VPN reads the Arabic list and does not see their case.

The same sentence also loses the literal token: EN has `` `localhost` `` as a code span; AR has the generic
phrase "عنوان محلي". This is the only EN file in the corpus whose code-span count exceeds the AR's (4 vs 3),
and the lost token is the exact string the user would see in their own store URL.

The same sentence transliterates the brand: AR writes "ووكومرس" where the EN writes "WooCommerce" and where
the other 39 Arabic occurrences in the corpus keep the Latin form.

### R6 — A rate limit becomes an order cap in Arabic. `major`

`en/commerce/commerce-provider-support.md:94`: "Salla limits **requests** per store." This is API rate
limiting.

`ar/commerce/commerce-provider-support.md:92`: "يحدّ Salla عدد **الطلبات** لكل متجر."

`الطلبات` means both "requests" and "orders", and **this very table uses it for "orders" in every other
row**. The natural reading of the Arabic sentence, in its own context, is "Salla caps the number of *orders*
per store" — a commercial restriction that does not exist, rather than a technical one that does. The Arabic
corpus demonstrates it knows how to disambiguate: the Zid row two lines down (`ar:93`) writes "بستين **طلب
واجهة** في الدقيقة" — "sixty *interface* requests per minute" — for EN "Zid allows 60 requests a minute per
store" (`en:96`). The Salla row did not get the same treatment.

### R7 — Fixed section headings have no fixed Arabic form, including an even split. `major`

The corpus is built on a repeated EN section skeleton. The Arabic renders the same EN heading inconsistently:

| EN heading | times | AR renderings |
|---|---|---|
| `## Who can do this` | 43 | `من يستطيع ذلك` ×22 / `من يستطيع فعل ذلك` ×21 |
| `## What you need first` | 24 | `ما تحتاجه أولاً` ×17 / `ما تحتاجه قبل البدء` ×7 |
| `## If it does not work` | 37 | `إذا لم ينجح الأمر` ×33 / `إن لم ينجح الأمر` ×4 |
| `## Related` | 55 | `مواضيع ذات صلة` ×54 / `ذات صلة` ×1 |
| `## Who can do what` | 2 | `من يستطيع ماذا` ×1 / `من يستطيع فعل ماذا` ×1 |

The 22/21 split on "Who can do this" is the clearest: the most repeated heading in the corpus has no canonical
Arabic form at all. First instances: `ar/audiences-and-campaigns/shared-audiences.md:124` vs
`ar/getting-started/connect-your-first-channel.md:73` (EN `en:132` and `en:80`, both `## Who can do this`).

This is not only style. The portal's search and any anchor or TOC generation keys off heading text, so an
Arabic reader searching the canonical section name reaches roughly half the corpus. The variants on
`## When to use one` → `متى تستخدمه` / `متى تستخدم روبوتاً` / `متى تستخدم قاعدة` / `متى تستخدم تدفقاً` /
`متى تستخدمها` are defensible — Arabic needs grammatical agreement with the noun — and are excluded from this
refutation. The five above are not.

The EN skeleton is itself not clean, which is the upstream cause: it carries both `## When to use one` and
`## When to use it`, and both `## When not to use one` and `## When NOT to use one` (caps,
`en/automation/agent-bots.md:21` and `en/automation/flow-builder.md:20`).

### R8 — A product name is translated in Arabic, in front matter and in link text, in ten places. `minor`

"Customer 360" becomes `عرض العميل الشامل` ("the comprehensive customer view") in all ten Arabic occurrences,
including `title` and `seo_description`:

`ar/commerce/customer-360.md:2,6,8,28,32,40,73,94`; `ar/commerce/commerce-provider-support.md:103`;
`ar/troubleshooting/troubleshooting.md` (related-links row). EN counterparts:
`en/commerce/customer-360.md:2,6,8,27,31,39,71`, `en/commerce/commerce-provider-support.md:104`,
`en/troubleshooting/troubleshooting.md:43`.

`ar/commerce/customer-360.md` is the only Arabic file in the commerce set containing no instance of the string
`360` outside the URL slug. CLAUDE.md requires preserving product names "unless an official localized form
exists". No official localized form exists: "Customer 360" appears **only in code comments** — e.g.
`app/javascript/dashboard/components/widgets/conversation/commerce/CommerceOverview.vue:9`,
`app/javascript/dashboard/api/commerce.js:51` — and in **no** i18n string in any locale. It is an editorial
name, so translating it is not a label error; but EN and AR readers are now given different names for one
feature, the slug stays `customer-360` in both, and an Arabic reader searching the portal for the name used in
the code and in support conversations finds nothing. This belongs in the Crowdin glossary decision either way.

### R9 — Brand names are inconsistently transliterated inside single Arabic files. `minor`

The EN corpus always uses the Latin brand. The Arabic mixes Latin and transliterated forms for the same brand,
within one file:

| file | brand | Latin | transliterated |
|---|---|---|---|
| `ar/whatsapp/whatsapp-business-coexistence.md` | WhatsApp | 15 | `واتساب` 15 |
| `ar/whatsapp/connect-whatsapp.md` | WhatsApp | 15 | `واتساب` 22 |
| `ar/getting-started/connect-your-first-channel.md` | WhatsApp | 8 | `واتساب` 18 |
| `ar/getting-started/connect-your-first-channel.md` | Telegram | 1 | `تيليجرام` 1 |
| `ar/whatsapp/whatsapp-template-lifecycle.md` | WhatsApp | 2 | `واتساب` 47 |
| `ar/audiences-and-campaigns/shared-audiences.md` | Salla | 1 | `سلة` 1 |
| `ar/commerce/commerce-overview.md` | Salla | 1 | `سلة` 1 |

Seventeen Arabic files use both forms of a brand they name. `ar/whatsapp/whatsapp-business-coexistence.md` is
split exactly 15/15. Corpus totals: `واتساب` 406 / `WhatsApp` 67; `WooCommerce` 39 / `ووكومرس` 7; `Shopify` 58
/ `شوبيفاي` 8; `Salla` 64 / `سلة` 24; `Zid` 53 / `زد` 7.

Partially mitigating, and it is why this is `minor` rather than `major`: the product's own Arabic locale does
the same thing (103 `واتساب` alongside Latin `WhatsApp`), so the corpus is inheriting a product-wide
convention gap rather than inventing one. It still needs one rule.

### R10 — Two Arabic navigation paths name the Agents page with the wrong word form. `minor`

`app/javascript/dashboard/i18n/locale/ar/settings.json:350` → `"AGENTS": "وكيل الدعم"` (singular). The Arabic
corpus writes `الإعدادات ← الوكلاء` (a different plural) at
`ar/workspace/roles-and-permissions.md:70` and `ar/getting-started/invite-your-team.md:48`, against EN
"Settings → Agents" (`en:69`, `en:48`). Recognisable, but not the label on screen.

Also internally inconsistent in the Arabic: `متقدّم` (`ar/troubleshooting/commerce-keys-cannot-do-that.md:23`,
`ar/troubleshooting/commerce-store-needs-reconnecting.md:27`) vs `متقدم`
(`ar/commerce/connect-woocommerce.md:39`) for the same EN "Settings → Advanced"; and `الموظف`
(`ar/troubleshooting/commerce-order-action-did-not-apply.md` closing bullets) for the "agent" that is
`وكيل الدعم` everywhere else.

### R11 — The English is the wrong side on one UI label. `minor`

Worth recording because it refutes any framing of this as "Arabic is the weaker corpus".

`app/javascript/dashboard/i18n/locale/en/macros.json:7` → `"HEADER_BTN_TXT": "Add a new macro"`. The English
article says "Settings → Macros → **Add macro**" (`en/conversations/macros.md:49`). The Arabic says
`الإعدادات ← ماكروس ← إضافة ماكرو جديد` (`ar:48`), which matches `ar/macros.json:7` exactly. **The Arabic
quotes the product correctly and the English does not.**

### R12 — A quantified claim is dropped, and per-channel detail is added, in the same Arabic section. `minor`

`en/workspace/set-up-an-inbox.md:17` asserts a count: "**Nine** are always offered: Website, WhatsApp, Email,
SMS, Facebook, Instagram, Telegram, Line and API". `ar/workspace/set-up-an-inbox.md:14-24` replaces the
paragraph with a nine-row table and **drops the count** — no `تسع`, `تسعة` or `9` appears in the Arabic file.
The nine channels are still enumerated, so the loss is the "always offered" guarantee that distinguishes them
from the conditional TikTok / Voice / WhatsApp calling in the next sentence.

In the same table the Arabic **adds** per-channel descriptions the English does not have: Facebook = "صندوق
Messenger لصفحة" (a page's Messenger inbox), Instagram = "الرسائل المباشرة لحساب" (an account's direct
messages), Telegram = "بوت على Telegram", Line = "حساب Line", API = "تطبيقك الخاص". The English gives
parentheticals only for Website and SMS. `ar:25` further adds that Voice and WhatsApp calling "تظهر في
النهاية" ("appear at the end"), a UI-ordering claim absent from `en:19-20`.

### R13 — Smaller AR-only additions `minor`

Each is a claim only Arabic readers receive. None is contradicted by the English; all are unsourced in it.

| AR | addition | EN counterpart |
|---|---|---|
| `ar/commerce/customer-360.md:87` | "ويستمر البحث في البقية" — the search continues in the other stores | `en:86` stops at "Salla stores are reported as not searchable" |
| `ar/commerce/commerce-provider-support.md:89` | "فلا تُوجد تلك الطلبات برقمها" — those orders cannot be found by their number | `en:93` stops at "A plugin that renumbers orders breaks it" |
| `ar/commerce/commerce-provider-support.md:94` | "فالطلب الأقدم لن يظهر" — an older order will not appear | not in `en:97` |
| `ar/commerce/commerce-provider-support.md:95` | "فيظهر عميل Shopify المطابَق بلا اسم" — a matched Shopify customer appears with no name | not in `en:97` |
| `ar/workspace/set-up-an-inbox.md:12` | "لأن كل واحد منهما قناة مستقلة" — because each is an independent channel | not in `en:12-13` |
| `ar/whatsapp/whatsapp-template-lifecycle.md:82` | "ولا شيء آخر مطلوب" — nothing else is required | not in `en:83` |
| `ar/troubleshooting/commerce-keys-cannot-do-that.md` | EN has three navigation paths, AR two; `en:43` "Settings → Commerce → the store →" has no AR counterpart | `en:43` |

## 5. Survived

These are the attacks that failed. They matter as much as §4, because several were the obvious places to
expect rot and the Arabic held.

**Front matter is at perfect structural parity.** All 63 pairs have identical key sets, identical `position`
values and byte-identical `tags`. `seo_title` exists in exactly the 14 `whatsapp-errors/` files in both
languages and is translated in all 14, preserving the error numbers (`"خطأ واتساب 131042 في لينوميا تشات"`,
`ar/whatsapp-errors/whatsapp-error-131042.md:6`). I expected to find untranslated or missing SEO fields and
found none. Nothing was dropped, nothing was added, no position was renumbered.

**Link targets are at perfect parity — zero divergence across 63 pairs.** I compared link-target multisets,
not just counts, so a target swapped for a different one would have shown. Every cross-reference resolves to
the same slug in both languages. This is the single strongest piece of evidence that the Arabic is a
maintained translation of the English rather than an independently drifted corpus.

**Numeric claims survive.** My first digit-level comparison reported divergences in 25 of 63 pairs. Every one
I ran down was a false positive: Arabic spells numbers as words where English uses digits.
`en/contacts/bulk-actions.md:102` "**10,000 contacts per action**" → `ar:95` "**عشرة آلاف جهة اتصال للإجراء
الواحد**"; `en/workspace/set-up-an-inbox.md:79` "not a true 24 hours" → `ar:85` "لا أربعاً وعشرين ساعة
حقيقية". The genuinely different numbers were thousands separators only (`1,000`/`1000`, `4,096`/`4096`). **No
limit, threshold, timeout, cap or error code differs in value between the two corpora.** I checked the
24-hour window, the 15-digit phone ceiling, the 10,000-contact and 10,000-character caps, the 30-day template
name block, the 60-day Shopify window, Zid's 60 req/min, the 4,096-character flow limit, the ten-searches-a-
minute rate, the five-second webhook timeout and the 5-order visible window.

**Machine-readable identifiers survive.** All nine order-action codes, all five WhatsApp error numbers in
filenames and bodies, `localhost`, `UTC`, `+96522201234`, `0551112233`, `order_shipped`, `MARKETING`,
`UTILITY`, `X-Hub-Signature-256`, `4xx`/`5xx`, `REST API`, `CSV`, `UTF-8` and `HMAC` appear identically. R5's
`localhost` is the one exception in the corpus.

**Conversation status labels survive, including an awkward one.** The Arabic corpus writes `فتح / معلق /
مؤجلة / تم حلها` (`ar/conversations/work-in-the-inbox.md`) for EN "Open / Pending / Snoozed / Resolved". I
expected `فتح` — the verb form, not the adjective — to be a translation error. It is not: it matches
`app/javascript/dashboard/i18n/locale/ar/chatlist.json` `CHAT_STATUS_FILTER_ITEMS.open.TEXT` exactly, as do
all four, and `محادثاتي / غير معيّن / الكل` matches `ASSIGNEE_TYPE_TABS`. The awkwardness is a product i18n
defect that the corpus faithfully reproduces, which is the correct behaviour for documentation. The same holds
for `الروبوتات` (Bots, `ar/settings.json:351`), `الوسوم` (Labels, `:364`), `الأتمتة` (Automation, `:366`),
`ماكروس` (Macros, `:367`), `سجلات التدقيق` (Audit Logs, `:352`), `قنوات التواصل` (Inboxes, `:353`),
`خيارات الربط` (Integrations, `:357`) and `المدفوعات` (Spend, `ar/commerce.json:68`) — every one verified
against the locale and correct.

**The two "extreme ratio" pairs survive claim-level review**, as §2 sets out: `contacts/contacts.md` and
`automation/automation-rules.md` are faithful, not condensed and not incomplete.

**The most compressed pair in the corpus survives.** `commerce-order-action-did-not-apply.md` at 0.74 is
complete, as detailed in §2.

**Permission outcomes survive, despite a reshaped table.** `workspace/roles-and-permissions.md` was my
strongest lead: the EN capability matrix has 4 capability rows (`en:14-19`), the AR has 6 (`ar:13-20`). I
could not turn it into a permission divergence. The EN bundles "Settings and billing" into one row and
"Contacts, canned responses, macros" into another; the AR splits each into two
(`الإعدادات` / `الفواتير`, `جهات الاتصال` / `الردود الجاهزة وماكروس`). Every administrator/agent value is
the same in both; only row granularity and row order differ. The same applies to the Steps list: EN 4 steps,
AR 5, because `ar:69` makes "احفظ" ("Save") its own step where `en:69` ends step 2 with "Save." Same
procedure. The six custom-role permissions, their grants, the "hierarchy not a set" rule and the
"refunds and cancellations are never delegable" rule are identical. **The divergences in that file are R1's
AR-only claims, not the permission data.**

**`commerce-provider-support.md`'s extra rows are not extra claims.** EN 4 limit rows, AR 7, because the AR
gives WooCommerce, Zid and Shopify a row each for two statements the EN packs into one. The EN's negative
formulation ("A Read key gives you orders but no live updates and no order actions", `en:94`) and the AR's
positive one ("التحديث المباشر وإجراءات الطلبات تحتاج مفتاح قراءة/كتابة", `ar:91`) are logically equivalent,
and the EN states the positive form itself in `en/commerce/connect-woocommerce.md:12-24`. Not a divergence.

**Prose-to-list reformatting is not content loss.** Four pairs are REFORMATTED rather than DIVERGENT, each
checked claim by claim:

| pair | what differs | verdict |
|---|---|---|
| `whatsapp/whatsapp-template-lifecycle.md` | AR promotes the EN's two intro paragraphs into `## نصفا حياة القالب` (`ar:13`); AR renders the EN's prose worked example (`en:80-83`) as 3 numbered steps (`ar:79-82`) | content identical, including all 9 state-table rows and the "Disabled by WhatsApp / cannot be deleted" and "No longer at WhatsApp" rows |
| `whatsapp/whatsapp-templates.md` | AR promotes the EN's third intro paragraph (`en:15-16`) into `## متى تستخدم قالباً` (`ar:14`) | content identical |
| `audiences-and-campaigns/whatsapp-campaigns.md` | EN `## When to use it` is prose (`en:18-19`), AR is 2 bullets (`ar:17-18`) | content identical |
| `workspace/teams-and-agents.md` | AR splits the EN's macro clause (`en:64`) into its own bullet (`ar:67`) | content identical |

**One claim I initially recorded as AR-only was my own error, and the English has it.** I flagged
`ar/audiences-and-campaigns/whatsapp-campaigns.md:24` ("a WhatsApp campaign cannot be edited after creation,
only deleted") as AR-only. It is not: `en/audiences-and-campaigns/whatsapp-campaigns.md:25` says it, and
`en:131` repeats it. Recording the miss because the near-identical R1 claim in `roles-and-permissions.md` *is*
AR-only, and the difference between the two is only visible if you grep the whole file rather than the
section. Any agent auditing AR-only claims by reading windows will generate false positives.

## 6. Not checkable

**Whether the AR-only claims in R1 were once true.** The repository is not a git checkout here (`git log` is
unavailable), so I cannot tell whether `ar/workspace/roles-and-permissions.md:92` records behaviour that was
removed from the code, or an EN bullet that was deleted, or an invention. Needed: the history of that file
and of `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb`.

**Whether R1's reassignment path is reachable through the UI.** I proved the API endpoint has no capability
guard. The Vue layer renders a paywall instead of the Custom Roles page
(`CustomRolePaywall.vue`, cited in the controller comment at
`custom/app/controllers/api/v1/accounts/custom_roles_controller.rb:10-12`), and I did not trace whether the
agent edit page still offers an existing role in its selector on a downgraded account. Either way the Arabic
claim is wrong as written — it says the assignment *cannot* happen, and the server permits it — but whether an
administrator can reach it by clicking is unverified. Needed: `EditAgent.vue` role-selector behaviour under a
disabled `custom_roles` flag.

**Whether `الإنفاق الظاهر` is the correct label for the "visible spend" contact-filter condition.** I verified
`المدفوعات` against `ar/commerce.json:68` for the Commerce panel's "Spend", but found no
`VISIBLE_SPEND`-style i18n key for the filter condition that
`ar/audiences-and-campaigns/shared-audiences.md:53,59,63,68,69` and
`ar/commerce/commerce-overview.md:35` name. The two Arabic renderings may both be correct in their own
contexts. Needed: the filter-attribute label source for Commerce conditions.

**Arabic prose fidelity below the structural level, at scale.** I compared all 63 pairs structurally and on
links, numbers, identifiers and labels, and read 14 pairs sentence by sentence (the 8 structurally divergent
ones, the 2 flagged extreme-ratio ones, the 4 lowest-ratio ones). A claim that was silently reversed inside a
matching table cell or a matching paragraph in the other 49 pairs would not have been caught by the
structural pass. Needed: a fluent Arabic reader, or a line-level semantic diff, over the remaining 49.

**RTL rendering of the mixed-script content.** R9's Latin/Arabic mixing and the preserved Latin tokens
(`Account Health`, `REST API`, `4xx`, `+96522201234`) are bidirectional-text hazards in the rendered portal.
That is agent 061's and 072's ground and I did not render anything. Needed: the portal rendering the Arabic
articles.

## 7. What the orchestrator must arbitrate

1. **Every Arabic word count in Phase 1 is wrong**, including reports 031 and 036 and any other that used
   bare `wc -w` in this container. Reports quoting Arabic length need recomputing with
   `LC_ALL=C.UTF-8` or Python before Phase 2 builds a coverage matrix on them. The conclusion 031 and 036
   drew was right; the evidence they published is not, and the published numbers imply a truncated Arabic
   corpus that does not exist.
2. **R1 is a correctness defect in shipped content, not a translation defect.** `ar/workspace/roles-and-permissions.md:62`
   and `:92` state a restriction the code does not implement. Either the Arabic is corrected, or — if the
   restriction is intended — the gap in
   `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb` is a product bug and belongs to
   whoever owns custom roles. **Do not resolve it by adding the claim to the English.** Routing: agent 033
   (custom roles and permissions), agent 096 (authorization).
3. **Decision 4 in §8 of the charter needs an Arabic clause.** The corpus has no terminology authority. R2,
   R3, R4, R7, R9 and R10 are all one missing artefact: a locked EN→AR glossary, keyed to
   `app/javascript/dashboard/i18n/locale/ar/*.json` as the authority for anything that names a UI surface,
   plus a fixed Arabic form for each skeleton heading. The CLAUDE.md Crowdin-glossary rule already points at
   this; nothing enforces it. Without it, every article added in Phase 5 adds divergence.
4. **R4 blocks the IA reassessment in Phase 3.** The corpus cannot settle its own information architecture
   while `ar/getting-started/connect-your-first-channel.md` and `ar/workspace/set-up-an-inbox.md` assert
   incompatible models of channel and inbox, and while the English pair is itself in mild tension
   (inbox ≡ channel in one article, inbox ⊃ channel in the other). Fix the English definition first, then the
   Arabic. Routing: agent 062 (cross-corpus IA), agent 057 (workspace), agent 049 (getting-started).
5. **R8 is a decision, not a defect.** Someone must rule on whether "Customer 360" is a product name that
   stays Latin in Arabic or an editorial name that may be translated. It exists in no i18n string, so either
   ruling is defensible — but the ruling has to be made once and recorded in the glossary, because it also
   governs the article's `title` and `seo_description` and therefore its Arabic discoverability.
6. **R11 means Arabic cannot be assumed to be the derived corpus.** At least one UI label is correct in Arabic
   and wrong in English. Any Phase 5 workflow that treats English as automatically authoritative will
   propagate that error. Both corpora need checking against the locale files, not against each other.

## 8. Per-pair verdict table

`EN w` and `AR w` are body words (front matter excluded), counted correctly under UTF-8. `structure` reports
divergence in heading / table-row / bullet / ordered-step / link counts. Verdicts: **FAITHFUL** — no
divergence found; **REFORMATTED** — content equivalent, presentation differs; **DIVERGENT** — at least one
substantive divergence, per §4.

| # | pair | EN w | AR w | ratio | structure | verdict |
|---|---|---|---|---|---|---|
| 1 | `administration/audit-logs.md` | 1017 | 816 | 0.80 | identical | FAITHFUL |
| 2 | `audiences-and-campaigns/labels-or-shared-audiences.md` | 1262 | 1061 | 0.84 | identical | FAITHFUL |
| 3 | `audiences-and-campaigns/shared-audiences.md` | 1535 | 1331 | 0.87 | identical | DIVERGENT |
| 4 | `audiences-and-campaigns/whatsapp-campaigns.md` | 1676 | 1394 | 0.83 | bul 25/27 | REFORMATTED |
| 5 | `automation/agent-bots.md` | 1103 | 901 | 0.82 | identical | FAITHFUL |
| 6 | `automation/automation-or-flow-builder.md` | 955 | 780 | 0.82 | identical | FAITHFUL |
| 7 | `automation/automation-rules.md` | 977 | 852 | 0.87 | identical | FAITHFUL |
| 8 | `automation/flow-builder.md` | 1055 | 905 | 0.86 | identical | FAITHFUL |
| 9 | `commerce/commerce-overview.md` | 912 | 769 | 0.84 | identical | FAITHFUL |
| 10 | `commerce/commerce-provider-support.md` | 1036 | 985 | 0.95 | tr 27/30 | DIVERGENT |
| 11 | `commerce/connect-salla.md` | 837 | 696 | 0.83 | identical | FAITHFUL |
| 12 | `commerce/connect-shopify.md` | 846 | 713 | 0.84 | identical | FAITHFUL |
| 13 | `commerce/connect-woocommerce.md` | 930 | 781 | 0.84 | identical | FAITHFUL |
| 14 | `commerce/connect-zid.md` | 836 | 688 | 0.82 | identical | FAITHFUL |
| 15 | `commerce/customer-360.md` | 1092 | 971 | 0.89 | bul 11/14 | DIVERGENT |
| 16 | `contacts/bulk-actions.md` | 1303 | 1053 | 0.81 | identical | FAITHFUL |
| 17 | `contacts/contacts.md` | 1093 | 877 | 0.80 | identical | FAITHFUL |
| 18 | `contacts/custom-attributes.md` | 1250 | 1016 | 0.81 | identical | FAITHFUL |
| 19 | `contacts/import-contacts.md` | 1401 | 1155 | 0.82 | identical | FAITHFUL |
| 20 | `conversations/assign-and-prioritise.md` | 947 | 826 | 0.87 | identical | FAITHFUL |
| 21 | `conversations/canned-responses.md` | 916 | 736 | 0.80 | identical | FAITHFUL |
| 22 | `conversations/labels.md` | 1036 | 903 | 0.87 | identical | FAITHFUL |
| 23 | `conversations/macros-or-automation.md` | 1047 | 928 | 0.89 | identical | FAITHFUL |
| 24 | `conversations/macros.md` | 1006 | 801 | 0.80 | identical | DIVERGENT |
| 25 | `conversations/work-in-the-inbox.md` | 1033 | 936 | 0.91 | identical | FAITHFUL |
| 26 | `getting-started/connect-your-first-channel.md` | 979 | 806 | 0.82 | identical | DIVERGENT |
| 27 | `getting-started/invite-your-team.md` | 843 | 679 | 0.81 | identical | FAITHFUL |
| 28 | `getting-started/set-up-your-account.md` | 760 | 651 | 0.86 | identical | FAITHFUL |
| 29 | `getting-started/welcome-to-lynomia-chat.md` | 479 | 388 | 0.81 | identical | FAITHFUL |
| 30 | `getting-started/your-first-conversation.md` | 984 | 817 | 0.83 | identical | FAITHFUL |
| 31 | `integrations/integrations.md` | 896 | 735 | 0.82 | identical | FAITHFUL |
| 32 | `integrations/webhooks.md` | 1257 | 1039 | 0.83 | identical | FAITHFUL |
| 33 | `troubleshooting/commerce-keys-cannot-do-that.md` | 456 | 359 | 0.79 | identical | DIVERGENT |
| 34 | `troubleshooting/commerce-order-action-did-not-apply.md` | 601 | 436 | 0.73 | identical | DIVERGENT |
| 35 | `troubleshooting/commerce-store-address-refused.md` | 404 | 332 | 0.82 | identical | FAITHFUL |
| 36 | `troubleshooting/commerce-store-needs-reconnecting.md` | 460 | 355 | 0.77 | identical | DIVERGENT |
| 37 | `troubleshooting/commerce-store-unreachable.md` | 456 | 339 | 0.74 | identical | DIVERGENT |
| 38 | `troubleshooting/contact-lynomia-support.md` | 1000 | 806 | 0.81 | identical | FAITHFUL |
| 39 | `troubleshooting/troubleshooting.md` | 859 | 747 | 0.87 | identical | FAITHFUL |
| 40 | `whatsapp-errors/whatsapp-business-scoped-contacts.md` | 391 | 315 | 0.81 | identical | FAITHFUL |
| 41 | `whatsapp-errors/whatsapp-contact-info-requests.md` | 455 | 375 | 0.82 | identical | FAITHFUL |
| 42 | `whatsapp-errors/whatsapp-display-name.md` | 330 | 264 | 0.80 | identical | FAITHFUL |
| 43 | `whatsapp-errors/whatsapp-error-131042.md` | 463 | 393 | 0.85 | identical | FAITHFUL |
| 44 | `whatsapp-errors/whatsapp-error-131049.md` | 529 | 433 | 0.82 | identical | FAITHFUL |
| 45 | `whatsapp-errors/whatsapp-error-131053.md` | 405 | 321 | 0.79 | identical | DIVERGENT |
| 46 | `whatsapp-errors/whatsapp-error-131060.md` | 360 | 290 | 0.81 | identical | FAITHFUL |
| 47 | `whatsapp-errors/whatsapp-error-190.md` | 437 | 361 | 0.83 | identical | FAITHFUL |
| 48 | `whatsapp-errors/whatsapp-find-a-failed-message.md` | 571 | 463 | 0.81 | identical | FAITHFUL |
| 49 | `whatsapp-errors/whatsapp-nothing-arrives.md` | 522 | 423 | 0.81 | identical | DIVERGENT |
| 50 | `whatsapp-errors/whatsapp-number-already-connected.md` | 391 | 285 | 0.73 | identical | FAITHFUL |
| 51 | `whatsapp-errors/whatsapp-number-status.md` | 533 | 436 | 0.82 | identical | DIVERGENT |
| 52 | `whatsapp-errors/whatsapp-quality-and-limits.md` | 557 | 460 | 0.83 | identical | FAITHFUL |
| 53 | `whatsapp-errors/whatsapp-reconnect-a-number.md` | 529 | 442 | 0.84 | identical | FAITHFUL |
| 54 | `whatsapp/connect-whatsapp.md` | 1193 | 950 | 0.80 | identical | FAITHFUL |
| 55 | `whatsapp/the-whatsapp-24-hour-window.md` | 867 | 686 | 0.79 | identical | FAITHFUL |
| 56 | `whatsapp/whatsapp-business-coexistence.md` | 988 | 780 | 0.79 | identical | FAITHFUL |
| 57 | `whatsapp/whatsapp-template-lifecycle.md` | 1178 | 956 | 0.81 | h 9/10, bul 12/13, ol 0/3 | REFORMATTED |
| 58 | `whatsapp/whatsapp-templates.md` | 1327 | 1108 | 0.83 | h 11/12 | REFORMATTED |
| 59 | `whatsapp/whatsapp-troubleshooting.md` | 1223 | 997 | 0.82 | identical | FAITHFUL |
| 60 | `workspace/roles-and-permissions.md` | 893 | 804 | 0.90 | tr 12/14, bul 9/10, ol 4/5 | DIVERGENT |
| 61 | `workspace/set-up-an-inbox.md` | 853 | 826 | 0.97 | tr 5/15 | DIVERGENT |
| 62 | `workspace/teams-and-agents.md` | 910 | 767 | 0.84 | bul 14/15 | REFORMATTED |
| 63 | `workspace/your-own-help-centre.md` | 535 | 426 | 0.80 | identical | FAITHFUL |

