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
| FAITHFUL — no divergence found | 44 |
| REFORMATTED — content equivalent, presentation differs (prose↔list, section promotion) | 4 |
| DIVERGENT — at least one substantive divergence | 15 |

**Answer to the brief: the Arabic corpus is at parity in content volume and at parity in structure for 48 of
63 pairs, but 15 pairs carry substantive divergences, and the divergences are concentrated in exactly the
places where being wrong costs most — navigation paths in troubleshooting articles, the permissions matrix,
and the corpus's central domain term.** Parity of presence is not parity of meaning, and neither is parity
of length.

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

