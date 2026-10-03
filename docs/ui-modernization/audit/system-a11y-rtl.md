# Accessibility and RTL Conventions — Baseline Audit

**Area:** Accessibility and RTL/bidi conventions across the agent dashboard.
**Scope of files read:** `app/javascript/dashboard/**/*.{vue,js}` (1 098 `.vue` files), plus
`tailwind.config.js`, `app/javascript/dashboard/assets/scss/{_base,_woot}.scss`,
`app/javascript/entrypoints/dashboard.js`, `app/javascript/dashboard/store/modules/accounts.js`,
and `node_modules/floating-vue/dist/floating-vue.mjs` (to settle what `v-tooltip` actually emits).
**Mode:** read-only inventory. Nothing below is a proposal. This file is the permanent record of what
exists today and is the baseline that later modernization work is checked against.

**Counting method.** Direction-utility counts come from a tokenizer
(split on whitespace plus the characters `" ' { } ( ) , ; = < >`, then variant-chain stripping) over `app/javascript/dashboard/**/*.vue`,
**excluding** `*.story.vue`, `**/fixtures/**` and `**/specs/**`. Icon-only-button and label counts come
from a tag-level scan of the same tree (stories included where stated). Everything else is `rg`.
Counts are occurrences, not files, unless a column says otherwise.

**Nothing in `enterprise/` or `custom/` affects this area:** `find enterprise custom -name '*.vue'`
returns 0 files. All dashboard UI lives in the OSS tree.

---

## 0. Executive shape of what exists

| Question | Answer in this codebase |
|---|---|
| Is RTL supported? | Yes, deliberately and fairly thoroughly — but **not** via CSS logical properties. |
| What is the house RTL idiom? | Hand-written `ltr:` / `rtl:` Tailwind variant **pairs** (649 physical-utility occurrences). |
| Are logical utilities used? | Yes but in the minority (206 occurrences), concentrated in `components-next/sidebar/`. |
| Is there untreated physical CSS? | Yes — 241 bare physical occurrences with no direction handling at all. |
| How many ways to read direction? | **Four** (Vuex getter, DOM `#app[dir]` query, Tailwind `ltr:`/`rtl:` variants, raw `[dir='rtl']` CSS). |
| Is there a focus-ring convention? | No. Five competing conventions coexist; two global rules actively delete focus outlines. |
| Do icon-only buttons have names? | Mostly no. 221 of 249 icon-only buttons (89%) expose **no accessible name**. |
| Is `BaseTable` a real table? | Yes — real `<table>/<thead>/<th>/<tbody>/<tr>/<td>`, but with no `scope`, `caption` or `aria-sort`. |
| Are dialogs focus-trapped? | Only `components-next/dialog/Dialog.vue` (native `<dialog>.showModal()`). The other two families are not. |
| Are form labels associated? | 34 of 218 `<label>` elements use `for=`; 78 wrap their control; **106 are dangling**. |

---

# PART 1 — RTL and bidi

## 1.1 The direction source of truth

| Layer | File:line | What it does |
|---|---|---|
| Vuex getter | `app/javascript/dashboard/store/modules/accounts.js:34-43` | `isRTL` — prefers the **user** UI-setting locale, falls back to the **account** locale |
| RTL locale list | `app/javascript/dashboard/components/widgets/conversation/advancedFilterItems/languages.js:746-749` | `getLanguageDirection()`; the hard-coded set is `['ar','as','fa','he','ku','ur']` |
| Root `dir` attribute | `app/javascript/dashboard/App.vue:141` | `:dir="isRTL ? 'rtl' : 'ltr'"` on `#app` |
| Teleport bridge | `app/javascript/dashboard/components-next/TeleportWithDirection.vue:17-26` | re-applies `dir` to teleported content so `ltr:`/`rtl:` variants keep working outside `#app` |
| Tooltip/popper bridge | `app/javascript/entrypoints/dashboard.js:88-106` | `container: '#app[dir]'` — poppers are appended inside `#app` so they inherit `dir`. The comment at `:92-95` states the reason explicitly. |

The direction decision is therefore made **once**, from the locale, and published as a DOM attribute.
That part is sound and is the thing a redesign must keep.

### The four readers of that one decision

| # | Mechanism | Consumers |
|---|---|---|
| 1 | `useMapGetter('accounts/isRTL')` | `App.vue:63`, `TeleportWithDirection.vue:17`, `components-next/sidebar/Sidebar.vue`, `components-next/sidebar/SidebarCollapsedPopover.vue:25`, `components-next/preview-picker/CaretAnchoredPicker.vue`, `components/table/BaseCell.vue:11`, `components/widgets/conversation/TagAgents.vue:28`, `routes/dashboard/helpcenter/components/ArticleSearch/ArticleView.vue:15`, `routes/dashboard/settings/reports/components/overview/AgentCell.vue:13` |
| 2 | `document.querySelector('#app[dir]')?.getAttribute('dir') === 'rtl'` | `composables/useDropdownPosition.js:30-32`, `components-next/DraggableReorderList/DraggableReorderList.vue:43-44` |
| 3 | Tailwind `ltr:` / `rtl:` variants | 724 occurrences across 197 (`rtl:`) / 172 (`ltr:`) files |
| 4 | Raw `[dir='rtl']` CSS selectors | `tailwind.config.js:139-148`, `components-next/sidebar/Sidebar.vue:1521-1522`, `components-next/message/bubbles/Email/Index.vue:232`, `components/widgets/WootWriter/Editor.vue:1167`, `components/widgets/WootWriter/Editor.vue:1202`, `components/widgets/WootWriter/CopilotMenuBar.vue:269` |

Mechanisms 1 and 2 answer the same question with different machinery. Mechanism 2 is not reactive to
Vue state at all — it reads the DOM on each call.

## 1.2 Physical vs logical utilities — the numbers

Scope: `app/javascript/dashboard/**/*.vue`, excluding stories/fixtures/specs.

| Category | Occurrences | Share |
|---|---:|---:|
| Physical utility **wrapped in an explicit `ltr:`/`rtl:` variant** (the house idiom) | **649** | 59% |
| Physical utility **bare**, no direction handling | **241** | 22% |
| Logical utility (`ms/me/ps/pe/start/end/text-start/text-end/rounded-ss…/border-s/border-e/inset-s/inset-e`) | **206** | 19% |
| **Total direction-sensitive occurrences** | **1 096** | |

**The ratio the brief asks for, two ways:**

- **bare-physical : logical = 241 : 206** → 54% / 46%. This is the "untreated vs modern" ratio.
- **all-physical (bare + variant-paired) : logical = 890 : 206** → **81% / 19%**. This is the
  "how is direction actually expressed" ratio, and it is the more honest headline: the codebase
  overwhelmingly expresses direction by duplicating physical CSS, not by using logical CSS.

### Physical token totals (raw `rg` over `*.vue` + `*.js`, variants included)

| Token | Hits | Logical mirror | Hits |
|---|---:|---|---:|
| `left-` | 197 | `start-` | 37 (Tailwind-shaped) |
| `right-` | 189 | `end-` | 37 (shared row above) |
| `ml-` | 110 | `ms-` | 35 |
| `pl-` | 104 | `ps-` | 36 |
| `pr-` | 99 | `pe-` | 14 |
| `mr-` | 94 | `me-` | 6 |
| `border-r` | 49 | `border-e` | 4 |
| `border-l` | 30 | `border-s` | 13 |
| `text-left` | 32 | `text-start` | 50 |
| `text-right` | 21 | `text-end` | 9 |
| `rounded-l` / `rounded-tl`+`rounded-bl` | 26 / 18 | `rounded-ss`/`rounded-es` etc. | 10 |
| `rounded-r` / `rounded-tr`+`rounded-br` | 26 / 12 | — | — |

`text-start` (50) actually **outnumbers** `text-left` (32) — text alignment is the one axis where the
logical form has won. Margin/padding/inset have not.

### Top bare-physical tokens (no `ltr:`/`rtl:` wrapper)

| Token | Occurrences |
|---|---:|
| `text-left` | 28 |
| `left-0` | 23 |
| `right-0` | 21 |
| `ml-0` | 9 |
| `ml-auto` | 8 |
| `mr-1` | 8 |
| `pr-2` | 7 |
| `text-right` | 6 |
| `mr-2` | 6 |
| `left-1/2` | 6 |

`left-1/2` and `left-0 right-0` pairs are symmetric and harmless. `text-left`, `ml-auto`, `mr-1`,
`pr-2`, `ml-0` are not.

## 1.3 Worst offending files

### Bare physical utilities per file (the real offenders)

| Occurrences | File |
|---:|---|
| 6 | `app/javascript/dashboard/components/Accordion/AccordionItem.vue` |
| 6 | `app/javascript/dashboard/components/widgets/forms/PhoneInput.vue` |
| 5 | `app/javascript/dashboard/components-next/Contacts/ContactsForm/ContactMergeForm.vue` |
| 4 | `app/javascript/dashboard/modules/widget-preview/components/WidgetBody.vue` |
| 4 | `app/javascript/dashboard/components/widgets/ThumbnailGroup.vue` |
| 4 | `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue` |
| 4 | `app/javascript/dashboard/components/widgets/conversation/MessagesView.vue` |
| 4 | `app/javascript/dashboard/components/widgets/conversation/ShopifyOrderItem.vue` |
| 4 | `app/javascript/dashboard/components-next/HelpCenter/Pages/ArticlePage/ArticleHeaderControls.vue` |
| 4 | `app/javascript/dashboard/components-next/year-in-review/YearInReviewModal.vue` |
| 4 | `app/javascript/dashboard/routes/dashboard/settings/inbox/FinishSetup.vue` |
| 3 | `components/CustomAttribute.vue`, `components/Modal.vue`, `components/widgets/WootWriter/Editor.vue`, `components/widgets/conversation/linear/{LinkIssue,SearchableDropdown}.vue`, `components-next/select/Select.vue`, `components-next/DraggableReorderList/DraggableReorderList.vue`, `components-next/sidebar/SidebarCollapsedPopover.vue`, `components-next/Contacts/ContactsSidebar/ContactCustomAttributes.vue`, `components-next/HelpCenter/Pages/ArticleEditorPage/{ArticleEditor,ArticleEditorControls}.vue`, `modules/contact/components/MergeContactSummary.vue`, `routes/dashboard/settings/billing/components/CreditPackageCard.vue`, `routes/dashboard/settings/integrations/Slack/SelectChannelWarning.vue` |

Concrete lines:

| File:line | Evidence | Why it is wrong in RTL |
|---|---|---|
| `components/widgets/forms/PhoneInput.vue:186` | `py-2 pr-1.5 pl-2 rounded-tl-lg rounded-bl-lg` | the country-code segment keeps its square/rounded corners on the physical left; in Arabic the segment moves to the right and the rounding is on the wrong side |
| `components/widgets/forms/PhoneInput.vue:205` | `!rounded-tl-none !rounded-bl-none` | the mating edge of the number field, same problem |
| `components/widgets/forms/PhoneInput.vue:248,255` | `mr-1`, `ml-1` | bare gaps inside the flag/dial-code row |
| `components/Accordion/AccordionItem.vue:38` | `rounded-bl-none rounded-br-none` | symmetric, harmless |
| `components/Accordion/AccordionItem.vue:43` | `py-0 pr-2 pl-0` | the chevron/label gutter does not mirror |
| `components/Accordion/AccordionItem.vue:57` | `rounded-br-lg rounded-bl-lg` | symmetric, harmless |
| `components/table/Table.vue:43` | `class="text-left py-3 px-5 …"` on `<th>` | **every TanStack-driven table header is left-aligned regardless of locale** |
| `routes/dashboard/settings/reports/components/CsatTable.vue:159` | `class="text-left py-3 px-5 …"` | same, CSAT report table |
| `components/Snackbar.vue:23` | `… py-3 text-left` | every toast/snackbar message is left-aligned in Arabic |
| `modules/search/components/RecentSearches.vue:98` | `… text-left text-base …` | recent-search rows |
| `components/widgets/conversation/ContentTemplates/ContentTemplatesPicker.vue:98` | `block p-2.5 w-full text-left …` | canned-response picker rows |
| `components/widgets/conversation/WhatsappTemplates/TemplatesPicker.vue:120` | `block p-2.5 w-full text-left …` | WhatsApp template picker rows |
| `components-next/sidebar/SidebarProfileMenu.vue:138` | `… p-1 text-left rounded-lg …` | profile menu rows |
| `components-next/Contacts/VoiceCallButton.vue:231` | `… px-4 py-2 text-left …` | call-destination picker rows |
| `components-next/captain/assistant/DocumentCard.vue:200` | `p-0 text-base text-left …` | Captain document titles |
| `routes/dashboard/settings/captain/components/ModelDropdown.vue:130` | `flex flex-col w-full text-left gap-1` | model picker rows |
| `routes/dashboard/settings/security/components/SamlAttributeMap.vue:20` | `… justify-between text-left …` | SAML attribute rows |
| `components/widgets/TableHeaderCell.vue:32` | `… py-2 text-xs font-medium text-right …` | bare `text-right` in a table header |
| `routes/dashboard/settings/inbox/channels/Facebook.vue:275` | `<div class="w-full text-right">` | bare `text-right` |
| `components/widgets/ThumbnailGroup.vue:34,36,41,43` | `ltr:-ml-2 rtl:-mr-2` / `ltr:-ml-1 rtl:-mr-1` returned from JS | correct, but a **class string computed in script** — invisible to any static sweep |

### `ltr:`/`rtl:`-pair density per file (how much manual mirroring a file carries)

| Pairs | File |
|---:|---|
| 21 | `components-next/Companies/CompaniesDetailsLayout.vue` |
| 21 | `components-next/Contacts/ContactsDetailsLayout.vue` |
| 16 | `routes/dashboard/settings/inbox/PreChatForm/PreChatFields.vue` |
| 16 | `routes/dashboard/conversation/contact/ContactInfoRow.vue` |
| 14 | `components/widgets/conversation/ConversationCard.vue` |
| 12 | `routes/dashboard/settings/inbox/settingsPage/CollaboratorsPage.vue` |
| 10 | `components/widgets/conversation/ReplyBox.vue`, `components-next/feature-spotlight/FeatureSpotlightPopover.vue`, `components-next/selectmenu/SelectMenu.vue`, `components-next/sidebar/Sidebar.vue`, `routes/dashboard/inbox/components/InboxListHeader.vue` |
| 8 | `components/CustomAttribute.vue`, `components/table/Table.vue`, `components/widgets/TableFooterPagination.vue`, `components-next/SharedAttachments/Media.vue`, `components-next/Conversation/ConversationCard/MessagePreview.vue`, `components-next/HelpCenter/Pages/ArticleEditorPage/{ArticleEditor,ArticleEditorHeader}.vue`, `components-next/label/LabelItem.vue`, `components-next/message/Message.vue` |

`ContactInfoRow.vue:81,127,136,163` is the canonical specimen — the same
`class="ltr:-ml-1 rtl:-mr-1"` is written out **four times** where `-ms-1` would do once.

### The three-utility manual-mirror idiom

Several files use a 3- or 4-class workaround where a single logical utility suffices:

| File:line | Written | Logical equivalent |
|---|---|---|
| `components/CustomAttribute.vue:294` | `ml-1 rtl:mr-1 rtl:ml-0` | `ms-1` |
| `components/widgets/conversation/conversationCardComponents/CardLabels.vue:89` | `mr-6 ml-0 rtl:ml-6 rtl:mr-0` | `me-6` |
| `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditor.vue:215` | `pl-3 … rtl:pr-3 rtl:pl-0` | `ps-3` |
| `components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditor.vue:237` | `pl-4 … rtl:pr-4 rtl:pl-0` | `ps-4` |
| `routes/dashboard/settings/reports/components/overview/MetricCard.vue:36` | `… rtl:mr-0 rtl:ml-0` | redundant pair |
| `components/CustomAttribute.vue:213` | `ltr:mr-2 ltr:ml-0 rtl:mr-0 rtl:ml-2` | `me-2` |

### Pairing discipline — and the two places it broke

Of 335 `ltr:`-prefixed tokens whose base utility has a physical mirror, only **5** lack an `rtl:`
counterpart on the same line, and 3 of those are regex artefacts from a trailing `;` in a `<style>`
block. The two genuine defects:

| File:line | Code | Defect |
|---|---|---|
| `components-next/captain/pageComponents/customTool/CustomToolCard.vue:136` | `class="mt-1 ltr:right-0 rtl:right-0 top-full"` | **both branches say `right-0`** — the custom-tool action menu stays pinned to the physical right in Arabic instead of flipping to the start edge; it will overflow the card |
| `components-next/captain/assistant/ResponseCard.vue:193` | `class="mt-1 ltr:right-0 rtl:right-0 top-full"` | identical copy-paste defect on the Captain response card menu |

Both are `DropdownMenu` anchors and both would be one `end-0` with a logical utility.

### JS-driven direction flips that logical CSS would delete

| File:line | Code | Note |
|---|---|---|
| `components/table/BaseCell.vue:17` | `:class="{ 'text-right': isRTL }"` | reads a Vuex getter to do what `text-start` does for free |
| `routes/dashboard/settings/reports/components/overview/AgentCell.vue:19-20` | `class="items-center flex text-left"` + `:class="{ 'flex-row-reverse': isRTL }"` | **both wrong**: `flex-row` already follows writing direction, so `flex-row-reverse` in RTL re-reverses it back to LTR; and `text-left` is bare |
| `components-next/sidebar/SidebarCollapsedPopover.vue:114` | ``[isRTL ? 'right' : 'left']: `${sidebarWidth + 8}px` `` | inline-style key chosen in JS; `inset-inline-start` would be static |
| `composables/useDropdownPosition.js:35` | `const anchorLeft = computed(() => (align === 'start') !== isRTL.value)` | the composable's own documented contract (`:17`) is "flips automatically for RTL" — the logic is correct, but it reimplements what `start-0`/`end-0` give declaratively |

### RTL keyboard behaviour is inconsistent

| File:line | Behaviour | RTL-aware? |
|---|---|---|
| `components/widgets/conversation/TagAgents.vue:97` | `const step = (event.key === 'ArrowRight') !== isRTL.value ? 1 : -1;` | **Yes** — the one correct implementation in the tree |
| `components/widgets/conversation/components/GalleryView.vue:146-163` | `ArrowLeft` → index − 1, `ArrowRight` → index + 1 | **No**. And the file's own chevrons *are* flipped (`:266` `icon="ltr:i-lucide-chevron-left rtl:i-lucide-chevron-right"`), so in Arabic the visual "previous" arrow and the Left key move in opposite directions |
| `components-next/year-in-review/YearInReviewModal.vue:174` | `ArrowRight: { action: nextSlide }` | **No** |
| `routes/dashboard/settings/reports/components/ReportDrilldownDrawer.vue:124-132` | `ArrowLeft` → `navigate(-1)`, `ArrowRight` → `navigate(1)` | **No** |

## 1.4 Every explicit `dir=` attribute, and why it is there

33 non-test occurrences. They fall into four intentional groups.

### Group A — the root and its bridges (3)

| File:line | Value | Reason |
|---|---|---|
| `App.vue:141` | `:dir="isRTL ? 'rtl' : 'ltr'"` | the single source of DOM direction |
| `components-next/TeleportWithDirection.vue:24` | `:dir="contentDirection"` | teleported content leaves `#app`, so it would lose `dir` and every `ltr:`/`rtl:` variant with it. The component's own header comment says exactly this. |
| `entrypoints/dashboard.js:96` | `container: '#app[dir]'` | same reason for floating-vue poppers |

### Group B — `dir="ltr"` to pin machine-readable, LTR-only data (14)

These are correct bidi practice: identifiers, URLs, keys and numbers must not be reordered by an RTL
paragraph.

| File:line | What is pinned |
|---|---|
| `routes/dashboard/settings/commerce/StoreDialog.vue:170` | store base URL input |
| `routes/dashboard/settings/commerce/StoreDialog.vue:184` | WooCommerce consumer key (`ck_…`) |
| `routes/dashboard/settings/commerce/StoreDialog.vue:192` | WooCommerce consumer secret (`cs_…`) |
| `routes/dashboard/settings/commerce/SallaConnectDialog.vue:148` | Salla credential input |
| `routes/dashboard/settings/commerce/ShopifyConnectDialog.vue:83` | Shopify credential input |
| `routes/dashboard/settings/commerce/Index.vue:362` | provider name + store base URL line |
| `components/widgets/conversation/commerce/CommerceOrderActions.vue:403` | refund amount (`inputmode="decimal"`) |
| `components/widgets/conversation/commerce/CommerceOrderActions.vue:446` | order number in the review summary |
| `components/widgets/conversation/commerce/CommerceOrderItem.vue:98` | copyable order number button |
| `components/widgets/conversation/commerce/CommercePanel.vue:524` | `email · phone` candidate line |
| `components-next/captain/assistant/PlaygroundRunDetails.vue:85` | `<pre>` of tool-call JSON arguments |
| `routes/dashboard/settings/flows/components/TestPanel.vue:166` | `<ol>` of flow node-ID path steps |
| `routes/dashboard/settings/flows/FlowBuilder.vue:421` | the **VueFlow canvas** — node coordinates are physical, so the whole graph is pinned LTR |

`FlowBuilder.vue:421` is the structurally interesting one: the flow canvas is a hard LTR island
inside an RTL app. A redesign must preserve that or the graph layout inverts.

### Group C — `dir="auto"` / `<bdi>` for user-generated text of unknown direction (14)

| File:line | Element | Content |
|---|---|---|
| `routes/dashboard/settings/inbox/Index.vue:171` | `<bdi dir="auto">` | inbox channel identifier (phone/handle/page name) |
| `components-next/sidebar/ChannelLeaf.vue:57` | `<bdi dir="auto">` | sidebar channel identifier |
| `components/widgets/SettingIntroBanner.vue:31` | `<bdi dir="auto">` | settings header identifier |
| `routes/dashboard/settings/flows/components/FlowNode.vue:81` | `<p dir="auto">` | node summary text |
| `routes/dashboard/settings/flows/components/FlowNode.vue:93` | `<span dir="auto">` | node output branch label |
| `routes/dashboard/settings/flows/components/TestPanel.vue:121` | `<p dir="auto">` | flow test chat transcript bubble |
| `routes/dashboard/settings/flows/components/TemplateEditor.vue:191` | `<p dir="auto">` | message-template preview |
| `routes/dashboard/settings/flows/FlowBuilder.vue:468` | `<ul dir="auto">` | validation error list |
| `components-next/recipes/RecipeDialog.vue:133` | `<span dir="auto">` | recipe description |

Note the pattern: all three identifier sites use `<bdi>` **and** `dir="auto"`, and all three put the
separator in `<span aria-hidden="true">` so a screen reader does not read the punctuation
(`routes/dashboard/settings/inbox/Index.vue:169`, `components-next/sidebar/ChannelLeaf.vue:53`).
That is the most careful bidi code in the repo.

### Group D — raw `[dir='rtl']` CSS (6)

| File:line | Rule | Reason |
|---|---|---|
| `tailwind.config.js:139-148` | `blockquote` border/padding swap inside the `prose-bubble` typography variant | Tailwind Typography emits `border-left`/`padding-left`, which have no logical form in the plugin output |
| `components-next/sidebar/Sidebar.vue:1521-1522` | `[dir='rtl'] .sidebar-nav :deep(a:hover) { transform: translateX(-3px) }` | mirrors the hover nudge. The comment at `:1520` records a real bug it fixes: "Vue compiles `:global(X) …` to `X` alone: the ancestor selector must stay plain, or every `[dir=rtl]` element moves." |
| `components-next/message/bubbles/Email/Index.vue:232` | `[dir='rtl'] .letter-render [dir='ltr'] { direction: inherit }` | the comment at `:230-231` explains it: Gmail/Outlook hard-code `dir="ltr"` on their wrappers, which would force received email content LTR in an RTL dashboard |
| `components/widgets/WootWriter/Editor.vue:1167` | ProseMirror internals | editor chrome has no logical equivalent |
| `components/widgets/WootWriter/Editor.vue:1202` | ProseMirror internals | as above |
| `components/widgets/WootWriter/CopilotMenuBar.vue:269` | Copilot menu bar | as above |

### What is *missing* from the `dir` inventory

Message bubbles themselves carry **no** `dir="auto"`. `components-next/message/bubbles/Text/Index.vue`,
`FormattedContent.vue` and `Base.vue` contain no `dir` attribute at all — `Base.vue:61,63` only
mirrors the bubble tail (`ltr:rounded-bl-sm rtl:rounded-br-sm`). So an Arabic message viewed in an
LTR dashboard — or an English message in an RTL dashboard — renders with the wrong base paragraph
direction: trailing punctuation, brackets and mixed-script runs land on the wrong side. The pattern
to fix this already exists three times over in Group C.

## 1.5 Tailwind's RTL affordances that are configured, and the ones that are not

- `darkMode: 'class'` (`tailwind.config.js:23`); `ltr:`/`rtl:` variants are Tailwind 3 built-ins and
  need no plugin — there is **no** RTL plugin in `tailwind.config.js`.
- `theme.extend.typography` (`tailwind.config.js:54+`) is the one place logical CSS is used
  deliberately: `paddingInlineStart` at `:120,126`, `marginBlockEnd` at `:124`,
  `textAlign: 'start'` on `th` at `:177`.
- `prefers-reduced-motion` is honoured in exactly **2** places
  (`routes/dashboard/conversation/ConversationView.vue:704`,
  `components-next/sidebar/Sidebar.vue:1544`) against 69 `animate-*` and 220 `transition-*`
  occurrences — including the `sidebar-aurora` keyframe animation at `Sidebar.vue:1526+`.

---

# PART 2 — Accessibility

## 2.1 Icon-only buttons

Scanned tags: `<Button>`, `<NextButton>`, `<woot-button>`, `<ConfirmButton>` across
`app/javascript/dashboard/**/*.vue`. "Icon-only" = has an `icon`/`:icon` attribute and has neither a
`label`/`:label` nor any text in the default slot.

| Metric | Count |
|---|---:|
| Total button tags | 843 |
| Icon-only | **249** (30%) |
| Icon-only with `aria-label` | 24 |
| Icon-only with `title=` | 4 |
| Icon-only with `v-tooltip` only | 84 |
| Icon-only with **nothing** | **137** |

### `v-tooltip` is not an accessible name

floating-vue 5.2.2 applies `aria-describedby` to the trigger **only while the popper is shown**
(`node_modules/floating-vue/dist/floating-vue.mjs:612`) and removes it on hide (`:639`). It never
writes `aria-label`. So the 84 tooltip-only buttons have **no accessible name at rest** — only a
description, and only once the tooltip is already visible. A screen reader announces them as
"button".

**Effective total with no accessible name: 137 + 84 = 221 of 249 icon-only buttons (89%).**

The gap is worse for *disabled* icon-only buttons, which do not fire `mouseenter` in most browsers,
so the tooltip never appears at all. `components-next/pagination/PaginationFooter.vue:82,91,110,119`
and `components/table/Pagination.vue:124,133,158,167` are exactly this case — the first/last-page
buttons are disabled at the boundaries and are then both nameless and descriptionless.

### Nameless icon-only buttons per file

| Count | File |
|---:|---|
| 8 | `components/widgets/conversation/components/GalleryView.vue` |
| 5 | `components-next/table/BaseTable.story.vue` *(story, not shipped)* |
| 4 | `components/table/Pagination.vue` |
| 4 | `components/widgets/TableFooterPagination.vue` |
| 4 | `components-next/pagination/PaginationFooter.vue` |
| 4 | `routes/dashboard/settings/flows/FlowBuilder.vue` |
| 4 | `routes/dashboard/conversation/contact/ContactInfoRow.vue` |
| 3 | `components-next/Contacts/ContactsHeader/ContactHeader.vue` |
| 3 | `components-next/NewConversation/components/ActionButtons.vue` |
| 3 | `components-next/CustomAttributes/OtherAttribute.vue` |
| 3 | `components-next/CustomAttributes/DateAttribute.vue` |
| 3 | `components-next/button/Button.story.vue` *(story)* |
| 2 | `components/ui/DatePicker/components/CalendarAction.vue`, `components/widgets/WootWriter/ReplyTopPanel.vue`, `components/widgets/conversation/linear/IssueHeader.vue`, `components-next/HelpCenter/Pages/PortalSettingsPage/DNSConfigurationDialog.vue`, `components-next/Campaigns/CampaignCard/CampaignCard.vue`, `components-next/captain/assistant/ScenariosCard.vue`, `components-next/captain/assistant/RuleCard.vue`, `components-next/NewConversation/components/AttachmentPreviews.vue`, `components-next/CustomAttributes/ListAttribute.vue`, `components-next/message/bubbles/Image.vue`, `components-next/ConversationWorkflow/AttributeListItem.vue`, `routes/dashboard/settings/flows/components/TestPanel.vue`, `routes/dashboard/settings/flows/components/SessionsPanel.vue`, `routes/dashboard/inbox/components/PaginationButton.vue` |
| 1 | 50 further files |

### The named worst cases

| File:line | Control | Consequence |
|---|---|---|
| `components/widgets/conversation/components/GalleryView.vue:224,231,238,245,252,260,266,334` | the **entire attachment lightbox toolbar** — zoom in, zoom out, rotate CCW, rotate CW, download, close, prev, next | eight consecutive buttons all announced as "button"; the lightbox is unusable with a screen reader |
| `components-next/pagination/PaginationFooter.vue:82,91,110,119` | first / prev / next / last page | the shared pagination footer; disabled at boundaries so no tooltip either |
| `components/table/Pagination.vue:124,133,158,167` | first / prev / next / last page | a second, parallel pagination implementation with the same defect |
| `components/widgets/TableFooterPagination.vue:54,66,86,98` | first / prev / next / last page | a **third** pagination implementation, same defect |
| `routes/dashboard/inbox/components/PaginationButton.vue:45,53` | prev / next notification | a **fourth** |
| `routes/dashboard/conversation/contact/ContactInfoRow.vue:122,131,158,167` | copy value, edit value (×2, duplicated for the link and non-link branches) | every row of the contact sidebar; the edit button is also `opacity-0` until row hover, so it is invisible *and* nameless |
| `components/Modal.vue:89-96` | the legacy modal's close button | affects all 52 `<woot-modal>` instances |
| `routes/dashboard/settings/flows/FlowBuilder.vue:331,442,443,450` | back, zoom in, zoom out, fit-to-view | the flow-builder canvas controls |
| `components-next/CustomAttributes/{DateAttribute,ListAttribute,OtherAttribute,CheckboxAttribute}.vue` (e.g. `OtherAttribute.vue:162,170,196`) | edit / delete / confirm per attribute | repeated once per custom attribute row, so the count scales with data |
| `components-next/captain/assistant/{RuleCard,ScenariosCard}.vue:82,84 / 189,191` | edit / delete | and the identical `i-lucide-ellipsis-vertical` overflow trigger is nameless in 7 card components (`AssistantCard.vue:93`, `DocumentCard.vue:210`, `InboxCard.vue:90`, `ResponseCard.vue:183`, `CustomToolCard.vue:126`, `ArticleCard.vue:239`, `CategoryCard.vue:112`, `LocaleCard.vue:126`) |
| `components-next/message/bubbles/Image.vue:74,75` | expand / download on every image message | in the message stream, so once per image |

### The component already knows

`components-next/button/Button.vue:209` computes `isIconOnly` and `:213` uses it to pick the
`iconOnly` size map. The information needed to require or warn about a missing name is already
present in the primitive; nothing acts on it. `EXCLUDED_ATTRS` in
`components-next/button/constants.js` filters attrs, and `aria-label` passes through
`filteredAttrs` (`Button.vue:49-59`) untouched — so the plumbing works, it is simply not used.

## 2.2 Focus-visible styling — five competing conventions, two global deletions

| Convention | Representative file:line | Where it is used |
|---|---|---|
| **A.** `focus-visible:ring-{1,2} ring-n-brand` | `components-next/Accordion/Accordion.vue:30` | Accordion, `components-next/radioCard/RadioCard.vue:58` (via `focus-within:has-[:focus-visible]:ring-2 ring-n-strong`) |
| **B.** `focus-visible:` background/brightness tint, **no ring** | `components-next/button/Button.vue:104-154` (`focus-visible:bg-n-alpha-2`, `focus-visible:brightness-110`), `components-next/sidebar/SidebarGroupSeparator.vue:92` | the whole `Button` system |
| **C.** `focus:outline-{colour}` (not `focus-visible:`) | `components-next/input/Input.vue:58`, `assets/scss/_base.scss:69`, `components-next/combobox/ComboBox.vue:109` | all text inputs |
| **D.** `focus:ring-1 … focus:ring-offset-2` | `components-next/switch/Switch.vue:22` | Switch only |
| **E.** `focus:outline-none` / `outline-none` with **no replacement** | `components-next/dropdown-menu/DropdownMenu.vue:153`, `components-next/combobox/ComboBoxDropdown.vue:87`, `components-next/Accordion/Accordion.vue:30` (`outline-none` then re-added as a ring) | 48 `outline-none` + 15 `focus:outline-none` occurrences |

Raw counts across `app/javascript/dashboard/**/*.{vue,js}`: `focus-visible` 62, bare `focus:` (not
`focus-visible`) 51, `outline-none` 48, `focus:outline-none` 15, `ring-offset` 6.

### Convention B produces no focus ring at all

`components-next/button/Button.vue:194` sets the base `outline-1 outline`, and then **every** colour
variant sets the outline colour to `outline-transparent` (`:104,106,109,110,114,116,120,121,125,127,130,132,138,141,143,147,149,152,154`).
The only `focus-visible:` effects are background tint and `brightness-110`. So for a keyboard user,
focusing a ghost or solid `Button` produces the **same visual change as hovering it** — and no
outline. With 843 button instances this is the single highest-reach focus defect.

### Two global rules delete focus outlines

| File:line | Rule | Effect |
|---|---|---|
| `assets/scss/_base.scss:60-64` | `// Focus outline removal` → `.button, textarea { outline: none; }` | every `.button` and every bare `<textarea>` loses its UA focus ring, with no replacement in the same rule |
| `assets/scss/_woot.scss:263` | `outline: none;` inside the `.bg-n-brand\/10` Lynomia gradient-button override (`:252-271`) | the gradient-skinned brand buttons lose their outline too |

### Errored inputs have no focus indicator

`components-next/input/Input.vue:53-60`: the `default` branch includes
`focus:outline-n-brand dark:focus:outline-n-brand`; the `error` branch (`:56`) sets hover and
disabled outline colours but **no `focus:` rule**. An input in the error state therefore shows no
focus change whatsoever — the ruby outline looks identical focused and unfocused.

### `DropdownMenu` items have hover styling and no focus styling

`components-next/dropdown-menu/DropdownMenu.vue:182-189`: menu item buttons carry
`hover:bg-n-alpha-1 dark:hover:bg-n-alpha-2` and no `focus:` or `focus-visible:` class. A keyboard
user tabbing through the menu sees nothing move. The file contains **zero** occurrences of
`focus-visible`, `focus:` (outside `searchInput.value.focus()` at `:133`) and `outline-*`.
41 files import this component.

### `Checkbox` has no focus indicator

`components-next/checkbox/Checkbox.vue:33`: the `<input type="checkbox">` sets `ring-transparent`,
`appearance-none` and a custom border, with no `focus:` or `focus-visible:` rule anywhere in the
file. Native appearance is removed and nothing replaces the focus ring.

### No skip link

`rg 'skip-to|skip-link|Skip to'` over the dashboard returns nothing. There is no skip-to-content
affordance, so keyboard users traverse the whole sidebar on every page.

## 2.3 Dialog focus management — three families, three behaviours

| Family | File | Focus trap | Esc | Focus restore | `role`/`aria-modal` | Accessible name | Teleported |
|---|---|---|---|---|---|---|---|
| **Native dialog** | `components-next/dialog/Dialog.vue` | **Yes** — `dialogRef.showModal()` at `:90` gives the browser's own trap + inert backdrop | native (`@close.prevent` at `:127`) | native | implicit on `<dialog>`; no explicit `aria-modal` | **No `aria-labelledby`** — the `<h3>` at `:137` is not referenced | yes, via `TeleportWithDirection` `:118` |
| **Side panel** | `components-next/side-panel/SidePanel.vue` | **No** — Tab escapes into the page behind; nothing is `inert` | `onKeyStroke('Escape')` `:75-82`, correctly deferring to a nested `dialog[open]` `:78` | **Yes** — `previousActiveElement` captured `:48-52`, restored `:65` | `role="dialog"` `:118`, `aria-modal="true"` `:119`, `:aria-label="title"` `:120` | **Yes** | yes `:89` |
| **Legacy modal** | `components/Modal.vue` | **No** | manual `document` keydown `:50-58` | **No** | **none** — plain `<div class="modal-mask">` `:72` | **No** | **No** — `// [TODO] Use Teleport to move the modal to the end of the body` at `:2` |

- `components-next/dialog/Dialog.vue` is used by 60 files; `<woot-modal>` (the legacy `Modal.vue`)
  still has 52 instances across 40 files. Both families are live.
- `SidePanel.vue` is the only component in the dashboard that saves and restores focus. It is also
  the only one with a complete `role`/`aria-modal`/`aria-label` trio.
- There is **no** focus-trap dependency in `package.json` — no `focus-trap`, `@vueuse`-based trap,
  Headless UI, Radix Vue or Reka UI. `inert` appears exactly once in the dashboard
  (`routes/dashboard/settings/flows/components/NodeConfigPanel.vue:123`, `:inert="readOnly"`), and
  not for modality.
- `useKeyboardNavigableList.js:8` records the gap in its own TODO list: *"The focus should be
  trapped within the list."*

## 2.4 Table semantics

### `BaseTable` is a real table

`components-next/table/BaseTable.vue` emits genuine semantics:

| Element | Line |
|---|---|
| `<table class="min-w-full table-auto divide-y divide-n-weak">` | `:31` |
| `<thead v-if="showHeaders">` | `:32` |
| `<th v-for="(header, index) in headers" class="… text-start …">` | `:34-42` |
| `<tbody>` | `:45` |
| empty-state `<tr><td :colspan="headers.length || 1">` | `:49-56` |

`BaseTableRow.vue:11` is `<tr>`; `BaseTableCell.vue:12` is `<td>` with `text-start/center/end`
(`:14-18`). The header uses `text-start` (`:37`) — correctly logical.

What is missing: no `scope="col"` on the `<th>`, no `<caption>`, no `aria-sort`, no `aria-rowcount`,
and the empty-state row is not `aria-live`, so a filter that empties the table announces nothing.
The `ltr:pr-4 rtl:pl-4` at `:37` and `:13` is the manual-mirror idiom again (`pe-4` would do).

### The other table is worse

`components/table/Table.vue` (the TanStack Table wrapper) is also a real `<table>` (`:29`) with
`<thead>/<tr>/<th>/<tbody>/<td>`, but:

| File:line | Problem |
|---|---|
| `components/table/Table.vue:42` | `class="text-left …"` on `<th>` — bare physical alignment on every header |
| `components/table/Table.vue:43` | `@click="header.column.getCanSort() && header.column.toggleSorting()"` — **sorting is a click handler on the `<th>` itself**. There is no `<button>`, no `tabindex`, no key handler: column sorting is mouse-only. |
| `components/table/Table.vue:43` | no `aria-sort`, so the current sort direction is not exposed |
| `components/table/SortButton.vue:17` | the sort indicator is a bare `<span :class="sortIconMap[...]" />` — a decorative icon with no `aria-hidden`, no `role`, no text, inside a non-interactive element |
| `components/table/Table.vue:34-42` | no `scope="col"` |

There are **7** files containing a literal `<table>` in the dashboard
(`components-next/table/BaseTable.vue`, `components/table/Table.vue`,
`routes/dashboard/settings/reports/components/CsatTable.vue`,
`routes/dashboard/settings/inbox/PreChatForm/Settings.vue`,
`routes/dashboard/settings/inbox/components/WeeklyAvailability.vue`,
`routes/dashboard/settings/customRoles/component/CustomRolePaywall.vue`, plus one story), and
**zero** occurrences of `role="table"`, `role="grid"`, `role="row"`, `role="cell"`,
`role="columnheader"`, `role="rowheader"` or `role="rowgroup"`. So nothing fakes a table with
divs — that is genuinely good news.

## 2.5 Form label association

| Category | Count | Valid? |
|---|---:|---|
| `<label>` with `for=` | 34 | yes |
| `<label>` without `for=` but **wrapping** its `<input>/<select>/<textarea>` | 78 | yes (implicit association) |
| `<label>` without `for=` and **not wrapping a control** | **106** | **no — dangling** |
| **Total `<label>` elements** | **218** | |

The dominant legacy idiom is the wrapping form, e.g.
`routes/dashboard/settings/inbox/channels/Twilio.vue:122-128` —
`<label :class="{ error: … }">{{ $t('…LABEL') }}<input v-model="channelName" …></label>`.
That is valid. Dangling labels appear wherever the control is a **Vue component** rather than a raw
element, because the `for`/`id` cannot be guessed:

| File:line | Dangling label | Control it should point at |
|---|---|---|
| `routes/dashboard/conversation/contact/ContactForm.vue:309-311` | avatar label | `<Avatar>` at `:312` |
| `routes/dashboard/conversation/contact/ContactForm.vue:394-396` | country label | `<ComboBox>` at `:397` |
| `routes/dashboard/conversation/contact/ContactForm.vue:419` | social profiles label | a `v-for` div at `:420` |
| `components-next/HelpCenter/Pages/PortalSettingsPage/PortalBaseSettings.vue` | 7 dangling labels — the worst single file | |
| `components-next/captain/assistant/PlaygroundTestSetup.vue` | 5 | |
| `routes/dashboard/settings/flows/components/NodeConfigPanel.vue` | 5 | |
| `components/widgets/conversation/ReplyEmailHead.vue`, `components-next/HelpCenter/Pages/LocalePage/LocaleContentDialog.vue`, `components-next/Companies/CompanyDetail/CompanyContactsSidebar.vue`, `components-next/AssignmentPolicy/components/ExclusionRules.vue`, `components-next/captain/pageComponents/customTool/CustomToolForm.vue`, `routes/dashboard/settings/agentBots/components/AgentBotModal.vue`, `routes/dashboard/settings/data/NewImportDialog.vue`, `routes/dashboard/settings/assignmentPolicy/pages/components/AgentAssignmentPolicyForm.vue`, `routes/dashboard/settings/inbox/Settings.vue` | 3 each | |

### The primitives differ on label plumbing

| Primitive | File:line | Label handling |
|---|---|---|
| `Input` | `components-next/input/Input.vue:36-37`, `:108-114,118` | **Correct.** `uniqueId` falls back to `'input-' + uid` and `<label :for="uniqueId">` / `<input :id="uniqueId">`. 82 consumers pass `label` without `id` and are all fine. |
| `TextArea` | `components-next/textarea/TextArea.vue:14` (`id: { default: '' }`), `:143-149` (`<label :for="id">`), `:171` (`<textarea :id="id">`) | **Broken when `id` is omitted** — renders `<label for="">` + `<textarea id="">`, i.e. no association. **19 call sites** do exactly that (see below). |
| `Checkbox` | `components-next/checkbox/Checkbox.vue:2-11,28-35` | **No `id`, no `label`, no `aria-label` prop at all.** The component is a bare unlabelled `<input type="checkbox">` wrapped in a `<div>`; there is no way to associate a label through the component. |
| `Switch` | `components-next/switch/Switch.vue:20-28` | **Best in class** — `<button type="button" role="switch" :aria-checked="modelValue">` plus `<span class="sr-only">{{ t('SWITCH.TOGGLE') }}</span>`. The name is generic ("Toggle") rather than contextual, but the pattern is right. |

`TextArea` sites with `label` and no `id` (unassociated labels):

`components-next/HelpCenter/Pages/CategoryPage/CategoryForm.vue:260`,
`components-next/Campaigns/Pages/CampaignPage/SMSCampaign/SMSCampaignForm.vue:123`,
`components-next/captain/pageComponents/response/FaqSuggestionReviewDialog.vue:171`,
`components-next/captain/pageComponents/customTool/CustomToolForm.vue:193,267,276`,
`components-next/captain/assistant/AddNewScenariosDialog.vue:108`,
`components-next/captain/assistant/PlaygroundTestSetup.vue:253,505`,
`components-next/captain/assistant/ScenariosCard.vue:249`,
`routes/dashboard/settings/flows/components/NodeConfigPanel.vue:203,291,469`,
`routes/dashboard/settings/inbox/components/WhatsappManualMigrationDialog.vue:406`
(plus 5 in `components-next/textarea/TextArea.story.vue`).

### Validation messages are not announced

`components-next/input/Input.vue:146-152` renders the `message` in a `<p>` with no `id` and no
`aria-describedby` link back to the input, and nothing sets `aria-invalid` when
`messageType === 'error'`. Same shape in `components-next/textarea/TextArea.vue:199+`. Across the
whole dashboard there is exactly **1** `aria-describedby` and **1** `aria-labelledby`. Validation
errors are therefore visual-only.

## 2.6 ARIA and role inventory

| Attribute | Occurrences | Attribute | Occurrences |
|---|---:|---|---:|
| `aria-label` | 69 (67 bound, 2 are `:hours-aria-label`/`:minutes-aria-label` props at `components-next/captain/pageComponents/assistant/settings/AssistantSystemSettingsForm.vue:214,219`) | `aria-current` | 3 |
| `aria-hidden` | 12 | `aria-busy` | 2 |
| `aria-expanded` | 9 | `aria-multiselectable` | 1 |
| `aria-selected` | 5 | `aria-modal` | 1 |
| `aria-pressed` | 5 | `aria-labelledby` | 1 |
| `aria-controls` | 4 | `aria-haspopup` | 1 |
| `aria-live` | 3 | `aria-describedby` | 1 |
| | | `aria-checked`, `aria-autocomplete`, `aria-activedescendant` | 1 each |

Discipline note: 67 of 69 `aria-label`s are bound expressions (i.e. i18n-backed), with no
hard-coded English strings. That is a genuinely good convention worth preserving.

| `role` | Occurrences | Where |
|---|---:|---|
| `button` | 14 | see below |
| `tab` / `tablist` | 3 / 2 | only `components/widgets/conversation/TagAgents.vue`, `components/widgets/conversation/commerce/CommercePanel.vue` |
| `status` | 2 | `routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue:423`, `components-next/preview-picker/PreviewPicker.vue:165` |
| `alert` | 2 | `components-next/captain/assistant/PlaygroundTestSetup.vue:169`, `components-next/captain/pageComponents/response/FaqSuggestionReviewDialog.vue:242` |
| `presentation` | 2 | incl. `components-next/side-panel/SidePanel.vue:103` (overlay) |
| `listbox` / `option` | 2 / 2 | only `components-next/combobox/ComboBoxDropdown.vue:93,103` |
| `list` | 2 | |
| `dialog` | 2 | `components-next/side-panel/SidePanel.vue:118`, `components-next/emoji-icon-picker/EmojiIconPicker.vue` |
| `switch`, `radiogroup`, `link`, `img`, `combobox` | 1 each | `components-next/switch/Switch.vue:24` etc. |

Only 7 live regions exist in the entire dashboard (`aria-live` ×3 + `role="status"` ×2 +
`role="alert"` ×2). Notably `components/Snackbar.vue` — the global toast surface — has **none**, so
every success/failure toast is silent to a screen reader.

### `role="button"` on non-buttons: 8 of 14 are mouse-only

| File:line | `tabindex` in file | key handlers in file | Verdict |
|---|---:|---:|---|
| `routes/dashboard/inbox/components/MenuItem.vue:11-13` | 0 | 0 | **mouse-only**; `role="button"` with no `tabindex`, no `@keydown`, and not even a `@click` on the element itself |
| `components-next/Conversation/ConversationCard/ConversationCard.vue:96-100` | 0 | 0 | **mouse-only** — this is the conversation list row, the single most-used control in the product |
| `components-next/Inbox/InboxCard.vue:159` | 0 | 0 | **mouse-only** |
| `components-next/sidebar/SidebarGroupHeader.vue:42,51` | 0 | 0 | **mouse-only** |
| `components/widgets/conversation/contextMenu/menuItem.vue:18` | 0 | 0 | **mouse-only** |
| `routes/dashboard/inbox/components/InboxDisplayMenu.vue:145` | 0 | 0 | **mouse-only** |
| `components-next/captain/assistant/ResponseCard.vue:294` | 0 | 0 | **mouse-only** |
| `components-next/captain/AnimatingImg/{Guardrails,ResponseGuidelines}.vue:14,15` | 0 | 0 | decorative animation, low impact |
| `routes/dashboard/settings/templates/TemplateCard.vue:37-41` | yes | `@keydown.enter`, `@keydown.space.prevent` | **correct — the reference implementation** |
| `components-next/SharedAttachments/Media.vue:187` | yes | 6 | correct |
| `components-next/SharedAttachments/Files.vue:118` | yes | 6 | correct |
| `routes/dashboard/settings/data/Index.vue:298` | yes | 2 | correct |

### Tabs are not tabs

`components/ui/Tabs/TabsItem.vue:46-58` renders `<li><a class="… cursor-pointer" @click="onTabClick">`.
The file contains **zero** occurrences of `tabindex`, `role=` or `aria-`. The `<a>` has no `href`, so
it is not focusable at all: the `woot-tabs` pattern (4 consumer files) is entirely mouse-driven.
`components/ui/Tabs/Tabs.vue:33-36` passes the active index down via `provide`, with no
`aria-selected` / `aria-controls` plumbing. The two files that *do* use `role="tab"`
(`TagAgents.vue`, `CommercePanel.vue`) hand-roll it rather than using this component.

### Positive `tabindex`

`components/auth/MfaVerification.vue:218,242,255,265,283` sets `:tabindex="1"`, `"2"`, `"2"`, `"3"`,
`"4"`. Positive tabindex values reorder the whole document's tab sequence, not just the component's.

## 2.7 The brand overlay styles an accessibility primitive

`app/javascript/dashboard/assets/scss/_woot.scss:223-233`:

```scss
.bg-n-alpha-3 ul grid div button.bg-n-brand,
ul.grid div button.bg-n-brand ,button:has(span.sr-only)
{
    background: #111 !important;
    animation: none !important;
    width: 27px;
    height: 17px;
    &:before, &:after { display: none !important; }
}
```

The selector `button:has(span.sr-only)` matches **any button containing a screen-reader-only label**.
Today the only such element in the dashboard is `components-next/switch/Switch.vue:20-28`, so the rule
functions as an (undocumented) brand skin for the Switch: it forces `#111` background with
`!important`, overriding the `bg-n-brand` / `bg-n-slate-6` on/off states at `Switch.vue:23`, and pins
the size to 27×17px over the component's `h-4 w-7`.

This couples a **visual** override to an **accessibility** affordance. The `sr-only` class appears in
only 4 places today (`Switch.vue:28`,
`routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue:430`,
`routes/dashboard/settings/billing/components/CreditPackageCard.vue:54`, and
`components-next/captain/assistant/PlaygroundTestSetup.vue:211` as a `custom-label-class`), so the
blast radius is small — but it means the natural fix for the 221 nameless icon-only buttons (adding
`<span class="sr-only">`) would silently restyle each of them into a black 27×17px pill. Anyone
touching either file needs to know this.

## 2.8 Keyboard infrastructure that already exists

| File | What it provides |
|---|---|
| `composables/useKeyboardEvents.js` | `tinykeys`-based global keybinding registration with `shouldIgnoreEvent` (`:17-29`) so shortcuts do not fire inside typeable elements, and Escape blurs the field instead |
| `composables/useKeyboardNavigableList.js` | ArrowUp/ArrowDown + `Control+KeyP`/`Control+KeyN` list navigation, `allowOnFocusedInput: true`, `preventDefault` only when items exist (`:21-27`). Its header TODO (`:5-9`) already names the missing focus trap and the missing scroll handling. |
| `composables/useDetectKeyboardLayout.js` + `shared/helpers/KeyboardHelpers` | QWERTZ remapping, `isActiveElementTypeable`, `isEscape` |
| `composables/useDropdownPosition.js` | viewport-aware flip/anchor with documented RTL flipping (`:17,30-35`) |

---

## 3. Summary of concrete defects, ranked by reach

| # | Defect | Reach | Anchor |
|---:|---|---|---|
| 1 | `Button` focus-visible produces no outline — every variant forces `outline-transparent` | 843 button instances | `components-next/button/Button.vue:194` + `:104-154` |
| 2 | 221 of 249 icon-only buttons have no accessible name (137 with nothing, 84 relying on `v-tooltip`, which emits only `aria-describedby`-while-shown) | 89% of icon-only buttons | scan; `floating-vue.mjs:612,639` |
| 3 | `DropdownMenu` has zero `role`/`aria-*` and zero focus styling on its items | 41 consumer files | `components-next/dropdown-menu/DropdownMenu.vue:166-189` |
| 4 | 106 dangling `<label>` elements; `TextArea` drops the association when `id` is omitted (19 sites); `Checkbox` has no label plumbing at all | all forms | `components-next/textarea/TextArea.vue:14,145,171`; `components-next/checkbox/Checkbox.vue:28-35` |
| 5 | `ConversationCard` (and 7 other `role="button"` divs) are mouse-only — no `tabindex`, no key handler | the conversation list | `components-next/Conversation/ConversationCard/ConversationCard.vue:96-100` |
| 6 | `woot-tabs` is a non-focusable `<a>` with no tab ARIA | 4 files | `components/ui/Tabs/TabsItem.vue:46-58` |
| 7 | Legacy `Modal.vue` has no `role`, no `aria-modal`, no name, no trap, no focus restore, no teleport, and a nameless close button | 52 instances / 40 files | `components/Modal.vue:2,72,89-96` |
| 8 | 241 bare physical direction utilities, incl. 28 bare `text-left` on table headers, toast text and 7 picker-row surfaces | dashboard-wide | `components/table/Table.vue:42`, `components/Snackbar.vue:23` et al. |
| 9 | `SidePanel` and native `Dialog` do not trap Tab; no focus-trap dependency exists in the project | 60 + N dialogs | `components-next/side-panel/SidePanel.vue`; `package.json` |
| 10 | Column sorting is a bare `@click` on `<th>` with no `aria-sort` and no focusable control | every TanStack table | `components/table/Table.vue:43`; `components/table/SortButton.vue:17` |
| 11 | Two RTL dropdown anchors say `ltr:right-0 rtl:right-0` | 2 Captain cards | `CustomToolCard.vue:136`, `ResponseCard.vue:193` |
| 12 | Arrow-key navigation is RTL-aware in 1 of 4 places; `GalleryView` flips its chevron icons but not its keys | lightbox, year-in-review, report drilldown | `GalleryView.vue:146-163` vs `TagAgents.vue:97` |
| 13 | Errored inputs lose their focus indicator entirely | all form error states | `components-next/input/Input.vue:53-60` |
| 14 | Validation messages are not linked by `aria-describedby`; no `aria-invalid` anywhere | all forms | `components-next/input/Input.vue:146-152` |
| 15 | Message bubbles carry no `dir="auto"`, so mixed-script message text takes the wrong base direction | the message stream | `components-next/message/bubbles/{Base,Text/Index,Text/FormattedContent}.vue` |
| 16 | Global toast surface has no live region | all toasts | `components/Snackbar.vue` |
| 17 | `_base.scss:60-64` and `_woot.scss:263` delete focus outlines globally with no replacement | `.button`, `textarea`, gradient buttons | as cited |
| 18 | `button:has(span.sr-only)` makes a brand visual override fire on an a11y primitive | Switch today; any future `sr-only` button | `_woot.scss:224` |
| 19 | Positive `tabindex` 1–4 reorders the document tab sequence | MFA screen | `components/auth/MfaVerification.vue:218-283` |
| 20 | No skip link; `prefers-reduced-motion` honoured in 2 places against 69 `animate-*` / 220 `transition-*` | dashboard-wide | `ConversationView.vue:704`, `Sidebar.vue:1544` |
| 21 | Four pagination implementations, all with the same nameless-icon-button defect | 4 surfaces | `PaginationFooter.vue`, `table/Pagination.vue`, `TableFooterPagination.vue`, `inbox/.../PaginationButton.vue` |

---

## 4. What a modernization should REUSE rather than rebuild

These already exist and work. Replacing them would be a regression.

| Asset | File:line | Why it is the right base |
|---|---|---|
| The one-source direction decision | `store/modules/accounts.js:34-43` + `App.vue:141` | locale → `#app[dir]`, with a documented user-over-account precedence. Keep the getter as the single reader; retire mechanism 2 (`useDropdownPosition.js:30-32`, `DraggableReorderList.vue:43-44`) into it rather than adding a fifth. |
| `TeleportWithDirection.vue` | `components-next/TeleportWithDirection.vue` | the non-obvious fix for teleported content losing `dir`. Any new overlay must go through it (or through the floating-vue `container: '#app[dir]'` config at `entrypoints/dashboard.js:96`). |
| The logical-utility reference implementation | `components-next/sidebar/SidebarGroupSeparator.vue:43,45,49,63-65,81`, `components-next/sidebar/SidebarGroupLeaf.vue` | already fully logical (`ms-5`, `pe-14`, `end-2`, `start-[-0.5rem]`, `border-s-2`, `rounded-es`) including pseudo-element positioning. Use it as the pattern for converting the other 649 `ltr:`/`rtl:` pairs. |
| The bidi-safe identifier pattern | `components-next/sidebar/ChannelLeaf.vue:53-59`, `routes/dashboard/settings/inbox/Index.vue:169-176`, `components/widgets/SettingIntroBanner.vue:31` | `<span aria-hidden="true">` separator + `<bdi dir="auto">` value. Extend this to message bubbles rather than inventing something. |
| The LTR-pinning convention for machine data | the 14 Group-B sites, esp. `FlowBuilder.vue:421` (whole canvas) and `CommerceOrderItem.vue:98` | these `dir="ltr"` attributes are load-bearing, not legacy. Removing them inverts URLs, keys, order numbers and the flow graph. |
| `components-next/side-panel/SidePanel.vue` | `:48-52, 59, 65, 75-82, 118-120` | the only complete focus lifecycle in the repo: capture → move in → Escape (deferring to nested `dialog[open]`) → restore, plus `role`/`aria-modal`/`aria-label` and `useScrollLock`. Add a trap here; do not start a new panel component. |
| `components-next/dialog/Dialog.vue` | `:90, 101-108, 118` | native `<dialog>.showModal()` already gives trap + inert + Escape + backdrop for free, and `:101-108` already solves nested-dialog Escape/click-outside. It needs `aria-labelledby`, not a rewrite. |
| `components-next/switch/Switch.vue` | `:20-28` | the only control with `role` + `aria-checked` + `sr-only` name + a real focus ring. Use it as the template for Checkbox and for naming icon-only buttons — **after** dealing with `_woot.scss:224`. |
| `components-next/Accordion/Accordion.vue` | `:30-32` | the clearest focus + disclosure pattern: `text-start`, `focus-visible:ring-1 ring-n-brand`, `:aria-expanded`, `:aria-controls`. Promote this ring to the project focus convention. |
| `components-next/radioCard/RadioCard.vue` | `:58` | `focus-within:has-[:focus-visible]:ring-2` — the pattern for giving a card the focus ring of the input inside it. |
| `components-next/combobox/ComboBoxDropdown.vue` | `:93-104` | the only correct listbox: `role="listbox"`, `:aria-multiselectable`, `role="option"`, `:aria-selected`. `DropdownMenu` should adopt this, not grow its own. |
| `components-next/table/BaseTable.vue` family | `:31-57`, `BaseTableRow.vue:11`, `BaseTableCell.vue:12-18` | real table semantics with `text-start` already in place. Add `scope="col"`, `aria-sort` and a live empty-state; keep the slot API. |
| `components-next/input/Input.vue` label plumbing | `:36-37, 108-114, 118` | `uniqueId = props.id \|\| 'input-' + uid` is the fix `TextArea` and `Checkbox` need. Copy it rather than asking 19 call sites to pass `id`. |
| `Button`'s existing `isIconOnly` | `components-next/button/Button.vue:209, 213` | the primitive already detects icon-only; the accessible-name requirement can hang off this computed instead of a new prop or a lint rule. |
| `composables/useKeyboardEvents.js` + `useKeyboardNavigableList.js` | incl. `shouldIgnoreEvent` at `useKeyboardEvents.js:17-29` and the TODO at `useKeyboardNavigableList.js:5-9` | the typeable-element guard and the Arrow/Ctrl-P/Ctrl-N bindings are already correct. The focus trap belongs *here*, as the TODO says. |
| `composables/useDropdownPosition.js` | `:17, 30-35, 37-46` | viewport flip + RTL anchor flip + container constraint, already documented. The two broken `ltr:right-0 rtl:right-0` anchors should route through it or through `end-0`. |
| `TemplateCard.vue`'s activation pattern | `routes/dashboard/settings/templates/TemplateCard.vue:37-41` | `role="button"` + `tabindex="0"` + `@keydown.enter` + `@keydown.space.prevent`. Apply verbatim to the 8 mouse-only `role="button"` divs. |
| The bound-`aria-label` convention | 67 of 69 sites | every accessible name already goes through i18n. Keep it; do not introduce literal English `aria-label`s. |
| The `prose-bubble` logical typography | `tailwind.config.js:120,124,126,177` | `paddingInlineStart`, `marginBlockEnd`, `textAlign: 'start'` are already logical; only `blockquote` (`:136-148`) needs the `[dir]` escape hatch. |
| The 6 raw `[dir='rtl']` CSS rules | `Sidebar.vue:1520-1522`, `message/bubbles/Email/Index.vue:230-232`, `Editor.vue:1167,1202`, `CopilotMenuBar.vue:269` | each carries a comment explaining a real third-party constraint (Vue `:global` compilation, Gmail/Outlook hard-coded `dir="ltr"`, ProseMirror internals). These are not cleanup candidates. |
