---
agent: 099
scope: Attack usability, accessibility and navigation of the public documentation from the reader's side
confidence: high
---

## What you attacked

Six reader journeys, walked against the code rather than against the design records. For each one I asked only
one question: *does the reader arrive at the answer, and what do they see on the way?*

| # | Journey | Verdict |
|---|---|---|
| 1 | An agent with a refused action or an error code on screen | **fails for WhatsApp and for everything outside Commerce** |
| 2 | A reader landing on `/docs` | **arrives, but to a blind, mislabelled home page** |
| 3 | A reader who searches | **works for codes; breaks on punctuation, lies about failure, destroys Back** |
| 4 | A reader in Arabic | **gets RTL — agent 069's claim is refuted — but never gets an Arabic answer from a product link** |
| 5 | A reader on a phone / with a keyboard / with a screen reader | **the worst of the six** |
| 6 | A reader following a link that no longer resolves | **three different 404s, and the one the product produces is a blank page** |

Specific claims attacked, from the arbitration ledger and from sibling reports:

- `_ARBITRATION.md:122` — "`DocsLink.vue` is consumed only by Commerce and Platform Support surfaces (038)."
- `_ARBITRATION.md:123` — "13 of 17 WhatsApp keys are registry-only; the 'cannot reply' banner links to
  `business.whatsapp.com/policy` rather than `whatsappWindow` (040)."
- `069-authoring-workflow-source-of-truth.md:333,531` — "the portal layouts set `lang` but never `dir` … so an
  Arabic article previews — and publishes — LTR."
- `064-editor-backend-model.md:212-214,413` — "`order_by_views` is a bare `reorder(views: :desc)` … the
  documentation home page's 'Recommended' block … is inverted."

I did not run a server or a browser. Everything below is read from the ERB, the Vue, the Tailwind config, the
built CSS in `public/vite/assets/`, the corpus and the registry; where a claim needs a runtime check I say so in
**Not checkable**.

---

## Refutations

### Journey 1 — a stuck user with an error on screen

**R-01 — The single most common WhatsApp refusal in the product sends the agent off-site, in English, past an
article that exists in both languages. `blocker`**

The banner an agent sees whenever the 24-hour window has closed resolves its "learn more" destination in
`app/javascript/dashboard/components/widgets/conversation/MessagesView.vue:227-240`, from
`app/javascript/shared/constants/links.js:7`:

```
WHATSAPP_CLOUD:
  'https://business.whatsapp.com/policy#:~:text=You%20may%20reply%20to%20a,...'
```

`REPLY_POLICY` is consumed by exactly one file (`MessagesView.vue:42`). The registry already holds
`whatsappWindow: 'the-whatsapp-24-hour-window'` (`documentationLinks.js:37`) and both corpus files exist
(`custom/db/documentation/en/whatsapp/the-whatsapp-24-hour-window.md`, and the `ar/` twin). The reader is sent to
a Meta marketing page with a text-fragment anchor instead. The ledger's phrasing understates it: this is not a
missing link, it is a link pointed somewhere worse than the one that was written for it.

**R-02 — 35 of the 62 registry keys render nowhere in the product. The ledger's count is low. `blocker`**

I enumerated the reachable set mechanically: literal `article-key="…"` props at the nine `DocsLink` call sites,
plus every `feature-name="…"` actually passed to `BaseSettingsHeader` resolved through `FEATURE_DOC_KEYS`
(`app/javascript/dashboard/helper/featureHelper.js:6-31`), plus the five `COMMERCE_ERROR_ARTICLES` targets and
the `'commerce'` fallback, plus the two WhatsApp codes the server classifies.

- **27 of 62 keys** are reachable.
- **35 are registry-only**: `accountSetup`, `assignAndPrioritise`, `automationOrFlows`, `bulkActions`,
  `campaigns`, `contactImport`, `contacts`, `conversations`, `customer360`, `firstChannel`, `firstConversation`,
  `flows`, `gettingStarted`, `inviteYourTeam`, `labelsOrAudiences`, `macrosOrAutomation`, `sharedAudiences`,
  `troubleshooting`, `whatsapp`, `whatsappBusinessScopedContacts`, `whatsappCoexistence`,
  `whatsappContactInfoRequests`, `whatsappDisplayName`, `whatsappError131053`, `whatsappError131060`,
  `whatsappError190`, `whatsappFindAFailedMessage`, `whatsappNothingArrives`, `whatsappNumberStatus`,
  `whatsappNumberTaken`, `whatsappQualityAndLimits`, `whatsappReconnect`, `whatsappTemplateLifecycle`,
  `whatsappTroubleshooting`, `whatsappWindow`.
- **18 of the 20 WhatsApp keys** are unreachable, not 13 of 17. Only `whatsappError131049` and
  `whatsappError131042` can ever appear, because those are the only two codes
  `Whatsapp::DeliveryFailure::CODES` classifies (`custom/app/services/whatsapp/delivery_failure.rb:28-31`).
  Three WhatsApp *error* articles — 131053, 131060, 190 — were written for a surface that can never link them.
- **All five `getting-started` keys** are unreachable. The onboarding section of the corpus has zero entry
  points from inside the product.

`DocsLink` being Commerce-and-Platform-Support-only (ledger `:122`) is **confirmed**: the nine importers are
`CommercePanel.vue:19`, `ProviderPicker.vue:8`, `ShopifyConnectDialog.vue:6`, `SallaConnectDialog.vue:7`,
`StoreDialog.vue:6`, `ZidConnectDialog.vue:6`, `PlatformSupportIndexPage.vue:11`,
`PlatformSupportNewPage.vue:7`, `PlatformSupportDetailPage.vue:10`.

**R-03 — The documented general fallback for a WhatsApp failure is dead code. `major`**

`app/javascript/dashboard/components-next/message/MessageError.vue:70-77`:

```js
const learnMoreUrl = computed(() => {
  if (!props.deliveryFailure) return '';
  return docsLink(whatsappErrorArticle(props.deliveryFailure.code) ?? 'whatsappTroubleshooting');
});
```

The comment two lines above says "the general troubleshooting article otherwise", and
`documentationLinks.js:156-159` says "the caller falls back to the general troubleshooting article". Neither is
true. `delivery_failure` is only ever present in the payload when the code is classified:
`Whatsapp::DeliveryFailure#push_event_data` returns `nil` for anything else
(`delivery_failure.rb:64-68`), `Custom::Message#delivery_failure_data` passes that through
(`custom/app/models/custom/message.rb:13-17`), and `_message.json.jbuilder:20-21` omits the key when it is nil.
So `whatsappErrorArticle(code)` is only ever called with 131049 or 131042, both of which resolve — and the `??`
branch is unreachable.

Reader's loss: an agent looking at `131047: Re-engagement message` or `133010: Phone number not registered` sees
"Failed to send", the provider's English string, and **no link at all**. The product's own observed-in-production
codes 131047 and 131026 (ledger `XA-01`) appear nowhere in the corpus either — `grep -r '13[0-9]\{4\}'` over
`custom/db/documentation/en` returns only `131042 131049 131053 131060`. The journey dead-ends twice.

**R-04 — On this installation, four rendered settings headers silently lose their help link. `major`**

`featureHelper.js:66-80`: on a branded installation (`INSTALLATION_NAME` is `'Lynomia Chat'`,
`config/installation_config.yml:17-18`) the function returns `documentationArticleUrl(docs, FEATURE_DOC_KEYS[key])
|| undefined` — it never falls back to `FEATURE_HELP_URLS`. Four `feature-name` values are actually passed by
components and have no `FEATURE_DOC_KEYS` entry: `dashboard_apps`, `captain_billing`, `conversation-workflow`,
`assignment-policy`. Those four pages render no "learn more" at all. Conversely `channel_whatsapp`,
`contacts`, `campaigns`, `flows`, `shared_audiences`, `shopify`, `bulk_actions` have entries that no component
ever passes — dead table rows masquerading as coverage.

**Commerce is the one journey that works, and it is worth saying why.**
`CommercePanel.vue:414-417` resolves `commerceErrorArticle(panel.error) || 'commerce'`, so every one of the 31
`Commerce::Error` codes reaches *some* article. That is the pattern the other 35 keys need, and it exists in
exactly one file.

### Journey 2 — a reader who lands on /docs

The page is `app/views/public/api/v1/portals/show.html+documentation.erb` (35 lines): a hero with a search box
and three topic pills, a 12-card category grid, then a 6-card article block. Data comes from
`app/controllers/concerns/portal_home_data.rb:6-20`.

**R-05 — Every one of the 12 category icons is invisible. `blocker`**

`manifest.yml` gives each section a Lucide icon name (`rocket`, `messages-square`, `life-buoy`,
`alert-triangle`, `workflow`, `shopping-bag`, `building`, `plug`, `shield`, `users`, `megaphone`,
`message-circle`). `Documentation::ContentSeeder#upsert_category` stores it verbatim
(`content_seeder.rb:58-64`). `PortalHelper#render_emoji_or_icon` then prefixes **Remix Icon**:

```ruby
icon_class = value.start_with?('i-') ? value : "i-ri-#{value}"   # app/helpers/portal_helper.rb:107
```

None of those 12 names exists in `@iconify-json/ri` (checked against `node_modules/@iconify-json/ri/icons.json`
— Remix spells them `rocket-line`, `rocket-fill`, …). All 12 exist in `lucide`. And because the class string is
built at request time in Ruby, it appears in no file Tailwind scans
(`tailwind.config.js:25-41`), so the utility is never generated either. Confirmed against the shipped
stylesheet: `.i-ri-rocket-line{` is present in `public/vite/assets/portal-ePmMYiAs.css`, `.i-ri-rocket{` is
absent, and so are the other eleven.

What the reader sees: `_category_card.html.erb:5-7` renders a 44×44 bordered chip whose contents are an empty
`<span>` — the `📁` fallback never fires because `category.icon.present?` is true. Same empty span in the
sidebar (`_sidebar.html.erb:42-46`, where the `i-lucide-folder` fallback is likewise skipped), in the breadcrumb
(`_breadcrumb.html.erb:17,22`), in the hero pills (`_hero.html.erb:24`) and in every article card's category
chip (`_article_card.html.erb:6`). The only visual wayfinding device on the documentation home is blank on every
surface that uses it.

**R-06 — "Popular articles / What other people are reading right now" is false, and becomes inverted the moment
it could be true. Agent 064 is right about the mechanism and understates the effect. `major`**

`portal_home_data.rb:18` → `@featured = base_articles.order_by_views.limit(6)`, and `article.rb:87` →
`scope :order_by_views, -> { reorder(views: :desc) }`. `articles.views` is a nullable `integer` with no default
(`db/schema.rb:211`) and nothing in the seeding path writes it — only
`Article#increment_view_count` does, fired by the tracking pixel
(`articles_controller.rb:35-48`, `_portal_scripts.html.erb:1-24`).

In Postgres `DESC` sorts NULLs **first**, and `reorder` discards the position order with no secondary key. So:

- On a freshly seeded install every article has `views = NULL`, every row ties, and the "6 most popular
  articles" are six arbitrary rows the planner happened to return. Re-seeding can change the set.
- Once views accumulate, the block shows the articles that have **never been read**, because they are the ones
  still NULL, and genuinely-read articles sink below them. The heading says
  `"What other people are reading right now."` (`en.yml` → `public_portal.sidebar.popular_articles_subtitle`).
  It is the opposite.

One correction to 064's wording for the record: the block a real reader gets is headed **"Popular articles"**,
not "Recommended articles". `show.html+documentation.erb:22-28` picks `recommended`/`popular` strings on
`@recommended_articles.present?`, and `recommended_articles` reads `popular_article_ids`
(`portal_home_data.rb:40-43` → `portal.rb:173-175` → `config['popular_content']`), which
`Documentation::PortalSeeder` never sets. So the "Recommended" branch is unreached on a default install and the
mislabelled "Popular" branch is what ships.

**R-07 — "Popular topics:" in the hero is just the first three manifest positions. `minor`**

`portal_home_data.rb:17` → `@popular_topics = @recommended_categories.presence || @visible_categories.first(3)`,
and `@visible_categories` is ordered by `position: :asc` (`:12-16`). With no curation that is Getting started,
Conversations, Contacts — and `_hero.html.erb:20` labels them `popular_label` = `"Popular topics:"`. A second
label asserting popularity the data cannot support.

**R-08 — Curating the Recommended block is destroyed by the next `documentation:setup`. `major`**

`Documentation::PortalSeeder#create_or_update` (`portal_seeder.rb:49-58`) on an existing portal does:

```ruby
portal.update!(platform_owned: true, account: nil,
               config: portal_config.merge(portal.config.to_h.slice('layout')))
```

`portal_config` holds only `allowed_locales`, `default_locale`, `layout`, `article_order`. Everything else in
`config` is replaced — including `popular_content`, which is the only place an admin's Recommended picks live
(`portal.rb:169-175`), and `social_profiles`, which the documentation footer reads (`_footer.html.erb:3`). The
file's own comment at `:4-6` promises "an operator who has renamed a portal in Super Admin does not lose that";
for curation and social links the promise is not kept. This matters because R-06 means the *only* way to make
the home page's second block honest today is to curate it by hand.

**What survived here.** The category grid order is meaningful and stable (manifest `position`, 10…110), and a
category with no published articles is correctly hidden (`portal_home_data.rb:13-14`). There is a path from the
home page to every section.

### Journey 3 — a reader who searches

**R-09 — The dropdown search drops everything after `#`, `&` or `+`. A reader typing `#131049` searches for
nothing. `major`**

`app/javascript/portal/api/article.js:8-11`:

```js
let baseUrl = `${this.baseUrl}/hc/${portalSlug}/${locale}/articles.json?query=${query}`;
```

No `encodeURIComponent`, no `URLSearchParams`. `#131049` truncates at the fragment and the server receives an
empty `query`; `pre-approved & sent` loses everything after the ampersand and injects a junk parameter; `c++`
becomes `c  `. Meta renders codes with a leading `#` in several of its own surfaces, so this is the first thing a
reader is likely to paste. They get `"No results found."` and no indication that their query was mangled.
The results *page* escapes this because the query arrives via a real form GET (`search/_form.html.erb:10-16`) —
so the same query behaves differently in the two search boxes on the same site.

**R-10 — A broken search is presented as an empty corpus. `major`**

`app/javascript/portal/components/PublicArticleSearch.vue:135-137`:

```js
} catch (error) {
  // Show something wrong message
} finally { this.isLoading = false; }
```

`searchResults` was cleared at `:128`, so any failure — 500, timeout, offline, a `pg_search` error — renders
`SearchSuggestions`' `showEmptyResults` branch: *"No results found."* The reader is told the documentation does
not cover their problem. The TODO comment has been there long enough to be load-bearing.

**R-11 — Typing in the search-results box navigates, so Back no longer returns the reader to where they came
from. `major`**

`app/views/public/api/v1/portals/search/_search_handler.html.erb:14-26` submits the form 500 ms after each
typing pause: `form.requestSubmit()`. Turbo is started (`entrypoints/portal.js:7`) and treats a form GET as an
advancing visit, so every intermediate query becomes a history entry. Typing "whatsapp error" yields two to four
entries. Pressing Back then walks back through *"whatsapp"*, *"whats"* … instead of returning to the article the
reader left. Each navigation also re-fires `autofocus` (`_form.html.erb:15`) and the cursor is re-placed by
`setSelectionRange` (`_search_handler.html.erb:8-12`) — focus is taken from the reader on every keystroke burst.

**R-12 — Zero results is a dead end. `minor`**

`search/index.html+documentation.erb:30-32` renders `_empty_state.html.erb`: a dashed box containing one
sentence, `"No results found for '%{query}'"`. No spelling suggestion, no "browse by topic", no link to the
categories, no link to support, no popular articles. The sidebar is the only remaining way out.

**R-13 — The dropdown is slow and unbounded. `minor`**

1000 ms debounce before the request is even made (`PublicArticleSearch.vue:90-92`), on a box that advertises
`⌘K`. And `ArticlesAPI.searchArticles` sends no `per_page`, so `limit_results` returns early
(`articles_controller.rb:52-58`) and the endpoint returns **every** match — rendered in full into a
`max-h-96` list with no count and no "see all results" affordance.

**What survived here, and this matters.** Error codes *are* findable. Every coded article carries the number in
its `title`, which `pg_search` weights `A` (`article.rb:91-105`), in **both** locales — `الخطأ 131049 — رفض
واتساب الرسالة لهذا الشخص وحده`. Prefix matching is on, so partial codes match. The failure in journey 1 is a
corpus gap (131047, 131026 are not written) and a link gap, not a search gap.

### Journey 4 — a reader in Arabic

**R-14 — REFUTED. Agent 069's claim that "an Arabic article … publishes LTR" is wrong. `069-…:333,531`**

069 is right on the narrow fact and wrong on the consequence. The ERB really never emits `dir`: I confirmed
`grep -rn 'dir=' app/views/` returns **nothing**, and `app/views/layouts/portal.html+documentation.erb:2` is

```erb
<html lang="<%= html_lang_attribute(I18n.locale) %>">
```

with the same at `portal.html.erb:2` and `portal.html+plain.erb:2`. But the direction is applied client-side:

```js
setDirectionAttribute: () => {                       // app/javascript/portal/portalHelpers.js:153-162
  const localeFromHtml = htmlElement.lang;
  htmlElement.dir = localeFromHtml && getLanguageDirection(localeFromHtml) ? 'rtl' : 'ltr';
},
```

called unconditionally from `InitializationHelpers.initialize()` at `portalHelpers.js:168` — *before* the
`isPlainLayoutEnabled` branch, so it runs in the plain layout too — which is wired to `turbo:load` in
`app/javascript/entrypoints/portal.js:9`. `getLanguageDirection` returns true for `'ar'`
(`advancedFilterItems/languages.js:746-749`), and `html_lang_attribute(:ar)` is exactly `"ar"`
(`portal_helper.rb:40-42`). `ar` is an available locale (`config/locales/ar.yml`,
`config/initializers/languages.rb:51`), and `switch_locale_with_article` resolves the locale from the article's
category (`base_controller.rb:53-64`), so an Arabic article page serves `lang="ar"` and the browser sets
`dir="rtl"`.

The Super Admin preview is also RTL, for the same reason: `preview` is a plain redirect to
`?show_plain_layout=true` (`custom/app/controllers/super_admin/articles_controller.rb:22-25`), not an
`IframeLoader`, so `data-dir-applied` is never set and `setDirectionAttribute` runs. 069's "previews LTR" and
"publishes LTR" are both incorrect. The `dir` gap is real; its stated effect is not.

**R-15 — The real defect: `dir` exists only after JavaScript, so the first paint of every Arabic page is LTR and
then flips. `major`**

`vite_client_tag` / `vite_javascript_tag 'portal'` are in `<head>` (`_portal_head.html.erb:6-7`) as deferred
modules, and `setDirectionAttribute` waits for `turbo:load`. So the HTML the browser first lays out has no `dir`
at all, and in that window **neither** `ltr:` **nor** `rtl:` Tailwind variants match — both compile to
`:where([dir="ltr"], [dir="ltr"] *)` / `:where([dir="rtl"], …)` in Tailwind 3.4.19
(`node_modules/tailwindcss/src/corePlugins.js:209-212`). The Arabic reader sees a left-aligned page that then
jumps to right-aligned, with the sidebar animating across (`transition-transform duration-200`,
`_sidebar.html.erb:15`). With JS unavailable — blocked, a stale bundle after deploy, a CSP mistake — the Arabic
page stays LTR permanently and every direction-aware class in the layout is inert. This is a layout-shift and
robustness defect, which is a different and smaller thing than 069 claimed, and it is the real one.

**R-16 — Compound with mobile: until `dir` is set, the phone nav drawer is open on top of the article.
`blocker` (shared with journey 5)**

`_sidebar.html.erb:15` hides the drawer off-canvas with `max-md:ltr:-translate-x-full` and positions it with
`ltr:left-0 rtl:right-0`. Below `md` there is no other transform. With no `dir` on `<html>` the `ltr:` variant
does not match, so on first paint the `fixed`, `h-[100dvh]`, `w-72` (18rem), opaque `bg-white` aside sits over
the content — 288 px of a 360 px phone viewport — with no backdrop (the backdrop label is `hidden
peer-checked/sb:block`, `:14`) and no way to dismiss it. JS then applies `dir="ltr"` and it slides away. If JS
never runs, it never slides away and the documentation is unreadable on a phone.

**R-17 — A contextual-help link cannot carry a locale, so an Arabic agent always lands on English. `major`**

Three independent facts compose:

1. `documentationArticleUrl(base, key)` takes no locale (`documentationLinks.js:102-107`); it emits
   `${base}/${slug}` where `slug` is the registry value — always the English key.
2. The route has no locale segment: `get 'docs/:article_slug', to: 'documentation#article'`
   (`config/routes/documentation.rb:25-26`).
3. So `params[:locale]` is always `nil` at `custom/app/controllers/documentation_controller.rb:22`, and
   `Documentation::Library.article_for(key, locale: nil)` (`library.rb:54-57`) evaluates
   `by_key.find_by(locale: nil)` — `WHERE locale IS NULL` against a `NOT NULL DEFAULT 'en'` column
   (`db/schema.rb:217`), which can never match — then falls through to `find_by(locale: DEFAULT_LOCALE)`.

The comment at `library.rb:50-51` ("the article in the reader's language") describes behaviour no caller can
reach. Every "Learn more" in the product resolves to the English article, and the reader is redirected to the
English slug (`documentation_controller.rb:25`). The Arabic half of the corpus — 63 files, seeded, published,
in the sitemap — has **no product entry point at all**.

**R-18 — The language switcher throws away the reader's place, although the translation link exists. `major`**

`_topbar.html.erb:55-66` renders each locale as `href="/hc/<slug>/<code>/"` — the portal **home** of the other
language. From the middle of an Arabic error article, choosing English returns the reader to the front page.
There is no "read this in English / اقرأ بالعربية" control on any article page: `grep -rn 'associated_article'`
over `app/views/public/api/v1/portals/` hits only `index.json.jbuilder:9` and `sitemap.xml.erb:14`. The data is
there — `ContentSeeder` sets `associated_article_id` on every non-default-locale article
(`content_seeder.rb:77`) and `_meta_head.html.erb:19-24` already emits the hreflang pair from it. The reader
just never gets the link the crawler gets.

**R-19 — An English date inside the Arabic sentence, on every Arabic article. `minor`**

`documentation_layout/articles/_header.html.erb:2`:

```erb
<% last_updated_on = article.updated_at.strftime("%b %-d, %Y") %>
```

Hard-coded, not `I18n.l`. So the Arabic "آخر تحديث" line reads `… Oct 13, 2026`. Worse for the changelog:
`public_portal.common.released_on` is one of only two `public_portal` keys **missing from `ar.yml`** (the other
is `draft_preview`), so `_release_meta.html.erb:19` renders the English "Released on 2026-10-13" verbatim on an
Arabic changelog entry. Everything else in the chrome is translated — 66 EN keys, 68 AR keys.

**R-20 — Physical-direction utilities left in a layout that is meant to be bidirectional. `minor`**

Against this repository's own rule ("use logical Tailwind utilities (`ms`, `me`, `start`, `end`)"):
`_sidebar.html.erb:50,76` `border-l` (the article tree's indent rail) and `:55,81` `border-l-2 border-n-portal`
(the "you are here" marker) — both land on the wrong side of right-aligned Arabic;
`articles/show.html+documentation.erb:23-24` `-ml-3` plus `i-lucide-arrow-left` on "Back to <category>";
`search/index.html+documentation.erb:50,56` `rounded-l-md` / `rounded-r-md` on Previous/Next, so in RTL the
corners are rounded on the wrong ends; `_avatar_group.html.erb:1` and `_category_card.html.erb:15` `-ml-1.5`
avatar overlap.

**R-21 — Both escape hatches drop an Arabic reader into English. `minor`**

`error/404.html.erb:8` builds its one link as `generate_home_link(@portal.slug, @portal.config['default_locale']
|| params[:locale], …)` — default locale first, so an Arabic reader who mistypes an Arabic category URL is sent
to the English home page. And `documentation.not_set_up` exists only in `en.yml:77`
(`documentation_controller.rb:37`).

### Journey 5 — a phone, a keyboard, a screen reader

**R-22 — Two nested `<main>` elements, no `banner`, no `contentinfo`, and no skip link anywhere. `blocker`**

`app/views/layouts/portal.html+documentation.erb`:

```erb
 9  <main class="flex flex-col min-h-screen main-content" role="main">
10    <%= render '…/documentation_layout/topbar', … %>     <!-- a <header> -->
14      <%= render '…/documentation_layout/sidebar', … %>  <!-- an <aside> -->
16      <main class="flex-1 min-w-0 flex flex-col">
17        <%= yield %>
18        <%= render '…/documentation_layout/footer', … %> <!-- a <footer> -->
```

Two `main` landmarks, which is invalid and makes landmark navigation ambiguous. Because the topbar `<header>`
and the `<footer>` are *inside* `main`, neither is a landmark at all — HTML only maps them to `banner` /
`contentinfo` when they are not scoped to a sectioning element. So the documentation portal exposes: two
`main`s, one `complementary`, two unnamed `nav`s, and nothing else. `grep -rn 'skip'` over
`app/views/public/api/v1/portals/` and `app/views/layouts/portal*` returns nothing — there is **no skip link**,
so a keyboard user traverses the whole topbar and sidebar on every page, with no landmark to jump to.

**R-23 — The search input has no accessible name, and its role is overridden. `blocker`**

`app/javascript/portal/components/PublicSearchInput.vue:78-89`:

```html
<input ref="inputRef" :value="searchTerm" type="text"
       :placeholder="searchPlaceholder" role="search" … />
```

`role="search"` is a **landmark** role for a container. Applied to an `<input>` it replaces the implicit
`textbox` role, so a screen reader announces a search landmark rather than an editable field. There is no
`<label>`, no `aria-label` and no `aria-labelledby` — the only accessible name available is the placeholder,
which the overridden role suppresses the use of. Search is the primary way into a 126-article corpus, and for a
screen-reader user it is an unnamed landmark they cannot tell is typable. The results-page input has the same
hole without the role bug: `search/_form.html.erb:10-16` has a placeholder and nothing else.

**R-24 — The phone navigation drawer has no keyboard path. `major`**

`_sidebar.html.erb:13` is `<input type="checkbox" id="sidebar-drawer-checkbox" class="peer/sb hidden">` —
`hidden` is `display:none`, so the control is not focusable and not in the tab order. The trigger is a `<label
for="sidebar-drawer-checkbox">` in `_topbar.html.erb:6-8` with an `aria-label` but no `role="button"`, no
`tabindex` and no `aria-expanded`. Labels are not keyboard-activatable and do not receive focus. A keyboard-only
user on a narrow viewport cannot open the navigation at all. (Touch screen readers can, by dispatching a click
on the clickable label — so the loss is specifically for physical keyboards.)

**R-25 — A link nested inside a `<summary>`, twelve times. `major`**

`_sidebar.html.erb:41-49`: each category's `<summary>` contains `<a href="<%= category_url %>">`. `summary` is
exposed as a button; an interactive element inside it is not independently reachable, Enter/Space on the summary
toggles rather than navigates, and a pointer click both navigates and toggles. So the sidebar offers no reliable
way to reach a *category* page — only to expand it and pick an article.

**R-26 — On a phone, an article page has no in-page navigation and no search box. `major`**

- The table of contents is `hidden lg:block` twice over: the mount point's wrapper
  (`articles/show.html+documentation.erb:31`) and the component root
  (`TableOfContents.vue:98`). Below 1024 px — every phone and most tablets — a long article has no section
  navigation.
- The topbar search is `hidden md:block` (`_topbar.html.erb:33`). The only other search box is the hero's
  (`_hero.html.erb:15`), which renders only on the portal home. So on a phone, from an article or a category
  page, **there is no way to search** without first navigating back to the home page.
- The `<nav>` holding the TOC has no accessible name, and the string written for it —
  `public_portal.toc_header` ("On this page"), passed through `window.portalConfig.tocHeader`
  (`_portal_scripts.html.erb:93`) — is rendered nowhere.

**R-27 — The search dropdown's ARIA is wired to nothing, and Enter does not open a result. `major`**

`SearchSuggestions.vue:87-96` declares `role="listbox"` with `role="option"` children. The input is not a
`combobox`, has no `aria-expanded`, no `aria-controls`, no `aria-activedescendant`, and there is no live region.
`useKeyboardNavigableList` is called **without `onSelect`** (`SearchSuggestions.vue:43-47`), and
`createKeyboardEvents` only registers `Enter` when `onSelect` is a function
(`useKeyboardNavigableList.js:50-52`). So arrow keys move a background tint that no assistive technology is told
about, and **Enter does nothing**; the reader must Tab, which moves a second, independent focus cursor through
the `<a>` elements. Each option's `id` is `article.id`, a bare integer (`:90`) — not a valid HTML id. And
`adjustScroll` hard-codes a 102 px row height (`:35`) against rows that are roughly 60 px, so arrow-key
scrolling overshoots.

**R-28 — Text contrast fails, and article links are distinguished by colour alone. `major`**

Tokens resolve through `theme/colors.js:107-120` to the variables in
`app/javascript/dashboard/assets/scss/_next-colors.scss:14-17,176-178`:

| Token | Light | On `#ffffff` | Dark | On `n-slate-2` | AA 4.5:1 |
|---|---|---|---|---|---|
| `text-n-slate-10` | `rgb(128 131 141)` | **3.78:1** | `rgb(119 123 132)` | **4.15:1** | fails both |
| `text-n-slate-11` | `rgb(96 100 108)` | 5.94:1 | `rgb(176 180 186)` | 8.45:1 | passes |
| `text-n-portal` | `#1f93ff` (`portal.rb:31,143-145`) | **3.15:1** | — | 5.59:1 | fails light |

`text-n-slate-10` carries real text at `text-sm`/`text-xs` in the category-page meta row
(`categories/_header.html.erb:3`), the sidebar's "Categories" heading (`_sidebar.html.erb:29`), the hero's
"Popular topics:" label (`_hero.html.erb:20`) and the footer branding (`_footer.html.erb:27`).

The worse one is `text-n-portal`. `articles/show.html+documentation.erb:18` passes
`link_class: 'prose-a:text-n-portal prose-a:no-underline hover:prose-a:underline'`, so **every link in every
article body** is `#1f93ff` at 3.15:1 on white, with no underline. Against the surrounding body text
(`--tw-prose-body`, `#374151`) the only cue is hue — which fails WCAG 1.4.1 unless a non-colour cue appears on
both hover *and* focus. Here it appears on hover only: there is no `focus:underline`. On a touch screen there is
no hover at all, so on a phone the internal cross-links in 126 articles are visually indistinguishable from the
prose around them. That is the corpus's entire internal-linking strategy, invisible.

**R-29 — Every section heading ends in a link called "#". `minor`**

`portalHelpers.js:14-37` walks `#cw-article-content` and, for each `h1/h2/h3`, appends

```js
permalink.className = 'permalink text-slate-600 ml-3';
permalink.textContent = '#';
```

with no `aria-hidden` and no accessible name beyond `#`. The corpus has **519 `##` headings in EN and 521 in
AR**, so a screen-reader user hears "… , link, number sign" at the end of roughly every heading on the site.
The same loop does `element.className = 'scroll-mt-24 heading'`, replacing the heading's class list outright,
and the heading `id`s exist only after JS — so a deep link to a section is inert in the served HTML.

**R-30 — Wide tables cannot be scrolled from the keyboard, and tables are the corpus's main format. `minor`**

`CustomMarkdownRenderer#table` wraps every table in `<div class="tableWrapper">`
(`lib/custom_markdown_renderer.rb:29-41`) and `articles/_content.html.erb:12` makes it `overflow-x-auto`. The
wrapper has no `tabindex="0"` and no `role="region"` + name, so a keyboard-only user cannot scroll it
(WCAG 2.1.1). **54 of the 63 EN articles contain at least one table.**

**R-31 — `sr-only` buttons are invisible focus stops. `minor`**

`PublicArticleSearch.vue:171-173` and `search/_form.html.erb:17-19` both use `class="sr-only"` without
`focus:not-sr-only`, so the submit button is focusable and invisible: a keyboard user Tabs out of the search
field and focus disappears. `_form.html.erb:15` also carries `autofocus`, which — combined with R-11 — takes
focus on every auto-submitted navigation.

**R-32 — There is not one image in the entire corpus. `major`**

`grep -rhn '!\[' custom/db/documentation/{en,ar}/*/*.md` → 0. `grep -rn '<img\|<figure\|<picture'` over the
corpus → 0. There is exactly one fenced code block in 63 EN files. 126 Markdown files documenting a visual,
multi-step product with no screenshot, no diagram and no annotated UI anywhere. For a stuck reader trying to
match prose ("open the Commerce panel and choose Reconnect") to a screen they are looking at, there is no visual
anchor at any point. The authoring surface has no media insertion either (program charter §1.4), so this is
structural rather than an oversight — but the loss is the reader's.

**What survived here.** Heading order is correct: no corpus body contains an `h1`
(`grep -rl '^# '` → 0 files), so the page is `h1` (title) → `h2` with a single `###` and no skipped level, and
no article has two identically-worded `h2`s, so the generated ids do not collide. Arabic headings transliterate
rather than vanish — I ran `@sindresorhus/slugify` 2.2.1 against real Arabic headings and got
`ma-yghtyh-hdha-almqal`, not `""`, so Arabic anchors work. `prose` spacing uses logical properties throughout
(`@tailwindcss/typography` 0.5.19 emits `borderInlineStartWidth` for `blockquote`,
`node_modules/@tailwindcss/typography/src/styles.js:1489-1490`), and the table header/cell alignment is forced
to `text-start` (`articles/_content.html.erb:14-16`), so RTL tables and quotes are correct once `dir` is set.
Decorative icons are consistently `aria-hidden` (`portal_helper.rb:109`). Collapsed `<details>` correctly hide
their links from assistive technology, so the 63-link sidebar is not traversed in full. `pre` is
`overflow-x: auto` and the body is `break-words`, so content does not force horizontal page scroll.

One piece of dead code worth recording, since it looks like an RTL fix and is not: the
`'[dir="rtl"] &'` blockquote override at `tailwind.config.js:183-192` sits inside the **`bubble`** typography
variant (indentation confirms: `typography:` at `:98`, `bubble:` at `:99`, `css:` at `:100`, `blockquote:` at
`:179`). There is no `DEFAULT` typography customisation at all, so nothing in that block reaches an article
page.

### Journey 6 — a reader who followed a link that no longer resolves

**R-33 — The 404 a product link produces is an empty page. `blocker`**

`custom/app/controllers/documentation_controller.rb:18-26`:

```ruby
article = Documentation::Library.article_for(params[:article_slug], locale: params[:locale])
return head :not_found if article.blank?
```

`head :not_found` is an explicit, successful render with **no body**. A reader who follows a `DocsLink`,
a bookmark or a support-ticket link to a retired or renamed slug gets zero bytes — the browser's own interstitial.
No documentation chrome, no search, no "try the documentation home", nothing in Arabic. The comment at `:16-17`
calls this failing "safely"; from the reader's side it is the least recoverable of the three 404s this system has.

**R-34 — `/hc/<portal>/articles/<missing>` renders the portal 404 and then throws it away. `major`**

`app/controllers/public/api/v1/portals/base_controller.rb:38-64`:

```ruby
def set_locale(&)
  switch_locale_with_portal(&) if params[:locale].present?
  switch_locale_with_article(&) if params[:article_slug].present?

  yield                                   # :42
end

def switch_locale_with_article(&)
  article = Article.find_by(slug: params[:article_slug])
  Rails.logger.info "Article: not found for slug: #{params[:article_slug]}"
  render_404 && return if article.blank?  # :56
  …
end
```

`render_404 && return` returns from `switch_locale_with_article`, not from `set_locale`, so the `yield` at `:42`
still runs the rest of the chain. `ArticlesController#set_article` then calls
`@portal.articles.published.find_by!(slug: …)` (`articles_controller.rb:80-83`), which raises
`RecordNotFound`; the exception escapes the controller and the rendered portal 404 is replaced by the generic
static `public/404.html` — `lang="en"`, no portal chrome, no search, and its single link is `/`, which for a
documentation reader is the product root rather than `/docs`.

Two further consequences of the same `yield`:

- `render_404` runs *before* `ArticlesController`'s own `set_portal_layout`, so `@portal_layout` is nil and
  `set_view_variant` picks no variant (`base_controller.rb:22-32,70-75`) — the portal 404 would render in the
  **classic** layout even if it survived. And there is no `error/404.html+documentation.erb` at all
  (`ls app/views/public/api/v1/portals/error/` → one file), so the documentation portal has no documentation-layout
  404. (The *category* 404 does survive, because `set_category` is an ordinary `before_action` that halts the
  chain — `categories_controller.rb:24-29` — but it inherits R-21's English escape link.)
- On **every** portal page the second `yield` re-runs the whole remaining callback chain and the action a second
  time: the portal lookup, `load_home_data`'s queries, and `ChatwootMarkdownRenderer#render_article`
  (`articles_controller.rb:109-111`) all execute twice per request. Nothing renders twice — `performed?` is
  already true — so it is invisible, which is why it has survived. It is pure duplicated work on the reader's
  critical path.

The existing specs cannot see any of this: `spec/controllers/public/api/v1/portals/articles_controller_spec.rb:140-143`
asserts only `have_http_status(:not_found)`, which both outcomes satisfy.

**R-35 — Nothing can ever be renamed or retired without breaking the reader. `major`**

There is no redirect mechanism: no redirect table in `db/schema.rb`, no redirect model, no catch-all route. The
slug is the canonical URL (`_meta_head.html.erb:7,11`), it is in the sitemap (`sitemap.xml.erb:16`), it is the
contract the registry depends on (`documentationLinks.js:5-6`), and it is freely editable in Super Admin
(`custom/app/dashboards/article_dashboard.rb:36`, ledger `PD-50`). So a rename produces a permanent dead link
*and* — because `ContentSeeder` upserts on `slug_for(key, locale)` (`content_seeder.rb:73,85-87`) — a duplicate
article at the old slug on the next seeder run, which nothing deletes. Three outcomes for one editorial action,
all of them the reader's problem.

**What survived here.** All 62 registry slugs resolve to a real corpus file in **both** locales today — I
checked every value in `DOC_ARTICLES` against `custom/db/documentation/{en,ar}/*/` and found no miss. There is no
`DOC_ARTICLES` key pointing at nothing. The `commerceErrorArticle` and `whatsappErrorArticle` lookups both
return `undefined` for an unmapped code rather than fabricating a slug (`documentationLinks.js:150-152,163-168`),
so an unknown code cannot produce a broken URL. And `/docs` itself resolves correctly, via
`Documentation::Library.docs_portal` and the portal's own locale redirect
(`documentation_controller.rb:8-10,30-34`, `portals_controller.rb:30-35`).

---

## Survived

Collected for the orchestrator, because a refuter's negative results are evidence too. Each of these is
something I tried to break and could not.

| Claim / behaviour | What I tried | Outcome |
|---|---|---|
| Arabic articles publish LTR (069) | traced `dir` from ERB through `portalHelpers.js:153-168` and `entrypoints/portal.js:9`; checked `getLanguageDirection('ar')`, `html_lang_attribute(:ar)`, `ar.yml` availability, and the Super Admin preview path | **refuted** — RTL is applied client-side on every layout including the plain preview |
| A registry key points at nothing | matched all 62 `DOC_ARTICLES` values against both corpus trees | no misses |
| An error code cannot be found by search | checked all five coded articles' `title` (weight `A`) in EN and AR; `prefix: true` is on | codes are findable in both languages |
| Arabic headings produce empty anchors | ran `@sindresorhus/slugify` 2.2.1 on real Arabic `##` text | transliterates to usable Latin slugs |
| Duplicate heading ids within an article | listed and de-duplicated every `##` line in all 126 files | none |
| Heading order is broken | searched for `^# ` in bodies and for skipped levels | `h1`→`h2` throughout, one `###`, no `h1` in any body |
| RTL tables / blockquotes are mirrored wrong | read `@tailwindcss/typography` 0.5.19 source and `articles/_content.html.erb:14-16` | logical properties and forced `text-start`; correct once `dir` is set |
| Portal brand colour is unset, killing link colour | checked `Portal#color` | `DEFAULT_COLOR = '#1f93ff'` guards it (`portal.rb:31,143-145`) — the colour renders, it just fails contrast (R-28) |
| Content forces horizontal scroll on a phone | checked `pre`, `.tableWrapper`, `break-words`, long inline code | contained; the phone problem is the sidebar (R-16), not the content |
| Chrome is untranslated in Arabic | diffed `public_portal` keys: 66 EN vs 68 AR | only `common.released_on` and `draft_preview` missing |
| Commerce error → article journey is broken | traced all 31 `Commerce::Error` codes through `commerceErrorArticle` and `CommercePanel.vue:414` | every code reaches an article; this is the one journey that works end to end |
| The category grid order is arbitrary | traced `position` from `manifest.yml` through `upsert_category` to `portal_home_data.rb:12-16` | meaningful and stable |

---

## Not checkable

- **Which 404 a reader actually receives for a missing article slug.** R-34's mechanism is certain from the
  code; which of the two responses reaches the browser depends on `config.action_dispatch.show_exceptions` and
  on whether the already-committed response can be replaced in the deployed environment. Needs one request
  against a running instance asserting the *body*, not the status. Either outcome is not the documentation-layout
  404, which is the finding.
- **Arabic search relevance.** `pg_search`'s `tsearch` default dictionary is `simple`, which does no stemming,
  so a reader typing `الرسالة` (with the definite article) should not match a corpus occurrence of `رسالة`,
  while `prefix: true` rescues some shared-prefix cases. I could not confirm the Postgres text-search
  configuration actually in use without a database. Routed to 078.
- **Whether `includes(:category)` plus `left_outer_joins(:category)` plus `pg_search`'s ranked subquery produce
  a correct paginated count** on the search results page (`search_controller.rb:11-16`, `article.rb:115-122`).
  Reasoning alone cannot settle it; needs one query log.
- **Real contrast of `text-n-portal` on a tenant portal.** `#1f93ff` is the platform default; a tenant that sets
  `portals.color` gets a different ratio. The documentation portal uses the default, which is what I measured.
- **Actual Core Web Vitals cost of the double-executed action** (R-34) and of the two first-paint flashes
  (R-15, plus the `<style>` block carrying `--dynamic-portal-color` being emitted at the *end* of `<body>`,
  `portal.html+documentation.erb:25` → `_portal_scripts.html.erb:25-75`). Needs measurement; routed to 080.
- **Screen-reader announcement order** for the two-`main` landmark structure (R-22) across NVDA / VoiceOver /
  TalkBack. The HTML facts are settled; the per-reader behaviour is not, and I was told not to run a browser.
