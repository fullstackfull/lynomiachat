---
agent: 072
scope: Arabic/RTL and accessibility on both sides — the public documentation portal and the Super Admin authoring surface
confidence: medium
---

# Arabic / RTL authoring and accessibility

Read-only, against `claude/documentation-v2`. Template EDITOR. Severities are `blocker | major | minor`.

Two sentences up front, because they govern everything below.

**The portal is not direction-unaware — it is direction-*late*.** `dir` is never emitted by the server; it is
written onto `<html>` by the portal JavaScript bundle at `turbo:load`. Everything downstream of that — every
`ltr:`/`rtl:` Tailwind utility in the layout — is inert until that moment, including the `ltr:` half.

**I could not run a browser.** Every RTL claim here is derived from source, and §3.9 names the test for each one
I could not settle by reading. "RTL must be tested, not assumed" applies to this report too.

---

## 1. What exists today

### 1.1 The direction mechanism

| Step | Where | What it does |
|---|---|---|
| Locale resolution | `app/controllers/public/api/v1/portals/base_controller.rb:38-64` | `around_action :set_locale`; an article page takes `@locale` from `article.category.locale` (`:58-62`) and wraps the action in `I18n.with_locale` |
| `lang` emission | `app/views/layouts/portal.html+documentation.erb:2` | `<html lang="<%= html_lang_attribute(I18n.locale) %>">` |
| BCP-47 shaping | `app/helpers/portal_helper.rb:40-42` | `locale.to_s.tr('_', '-')` |
| **`dir` emission** | *nowhere server-side* | `grep -rn 'dir=' app/views/` → **zero hits** |
| `dir` assignment | `app/javascript/portal/portalHelpers.js:153-162` | `setDirectionAttribute()` reads `html.lang`, sets `html.dir` to `rtl` or `ltr` |
| When it runs | `app/javascript/entrypoints/portal.js:9` → `portalHelpers.js:166-168` | `document.addEventListener('turbo:load', onLoad)`, and `setDirectionAttribute` is the second call in `initialize()` |
| RTL language list | `app/javascript/dashboard/components/widgets/conversation/advancedFilterItems/languages.js:746-749` | `['ar','as','fa','he','ku','ur'].includes(languageCode)` — exact match |
| Variant semantics | `node_modules/tailwindcss/lib/corePlugins.js:210-211` (Tailwind 3.4.19) | `ltr` → `&:where([dir="ltr"], [dir="ltr"] *)`; `rtl` → the same for `rtl` |

The docs portal is seeded with `allowed_locales = %w[en ar]`, no draft locales and `layout = 'documentation'`
(`custom/app/services/documentation/portal_seeder.rb:62-66`; `custom/app/services/documentation/library.rb:14-15`),
so `public_locale_codes.length == 2` and the topbar locale switcher does render (`_topbar.html.erb:44`).

### 1.2 The documentation layout

`app/views/layouts/portal.html+documentation.erb` → topbar, sidebar, `yield`, footer. Article body renders
through `ChatwootMarkdownRenderer#render_article` → `CustomMarkdownRenderer` with the `:table` extension
(`lib/chatwoot_markdown_renderer.rb:13-19`) into `app/views/public/api/v1/portals/articles/_content.html.erb`,
which applies `prose dark:prose-invert` plus explicit table styling.

Direction-relevant utility use in the documentation layout, measured file by file:

| File:line | Utility | Status |
|---|---|---|
| `documentation_layout/_topbar.html.erb:6,19,37,53` | `-ms-1`, `ms-4`, `ms-auto`, `end-0` | logical — correct |
| `documentation_layout/articles/_actions.html.erb:15` | `end-0` | logical — correct |
| `articles/_content.html.erb:14-16` | `!text-start`, `!border-e` | logical — correct |
| `documentation_layout/_sidebar.html.erb:15` | `ltr:left-0 rtl:right-0`, `ltr:border-r rtl:border-l`, `max-md:ltr:-translate-x-full max-md:rtl:translate-x-full` | variant-gated — dead until JS runs (F1) |
| `documentation_layout/_sidebar.html.erb:50,76` | `border-l` beside `ms-4 ps-3` | **physical** (F3) |
| `documentation_layout/_sidebar.html.erb:55,81` | `border-l-2 border-n-portal` beside `-ms-[13px] ps-3` | **physical** (F3) |
| `documentation_layout/_category_card.html.erb:15`, `categories/_header.html.erb:9`, `_avatar_group.html.erb:1` | `-ml-1.5` / `-ml-0.5` avatar overlap | **physical** (F3) |
| `articles/show.html+documentation.erb:23` | `-ml-3` | **physical** (F3) |
| `search/index.html+documentation.erb:50,56` | `rounded-l-md` / `rounded-r-md` | **physical** (F3) |
| `portal/components/TableOfContents.vue:40,49,98,104,109` | `ltr:ml-2 rtl:mr-2`, `ltr:pl-4 rtl:pr-4`, `ltr:border-l-2 rtl:border-r-2`, `ltr:-left-0.5 rtl:-right-0.5` | variant pairs — work, but against CLAUDE.md (F3) |

`@tailwindcss/typography` 0.5.19 is itself fully logical: `paddingInlineStart` ×60, `paddingInlineEnd` ×30,
`borderInlineStartWidth`, `borderInlineStartColor`, and `textAlign: 'start'`
(`node_modules/@tailwindcss/typography/src/styles.js:1629`), with **no** physical left/right properties. So
`prose` lists, blockquotes and cells flip by themselves once `dir` is present.

### 1.3 The Super Admin authoring surface

| Thing | Where |
|---|---|
| Layout | `app/views/layouts/super_admin/application.html.erb:16` — `<html lang="<%= I18n.locale %>">`, no `dir` |
| Form fields | `custom/app/dashboards/article_dashboard.rb:36` — `portal category title slug description content locale status position meta` |
| Content field | `article_dashboard.rb:19` — `Field::Text.with_options(rows: 28)` |
| Rendered by | `vendor/bundle/ruby/3.4.0/gems/administrate-0.20.1/app/views/fields/text/_form.html.erb:17-22` — `f.label` + `f.text_area field.attribute`, no options |
| Form chrome | `vendor/.../administrate-0.20.1/app/views/administrate/application/_form.html.erb:17-60` — not overridden in this repo |
| Field CSS | `app/assets/stylesheets/administrate/components/_field-unit.scss`, `.../base/_forms.scss` |
| `meta` field | `custom/app/fields/article_meta_field.rb`, `custom/app/views/fields/article_meta_field/_form.html.erb` |

There is no app-level or `custom/` override of Administrate's `text` field partial: `app/views/fields/` contains
no `text/` directory and `custom/app/views/fields/` holds only `article_meta_field` and `article_author_field`.

### 1.4 The corpus, measured

| Measurement | Result |
|---|---|
| Markdown files | 126 (63 EN + 63 AR) |
| Files whose body contains a `#` h1 | **0** |
| First heading level | `##` in **all 126** files |
| Heading-level skips (counting the page `<h1>`) | **0** |
| Markdown images `![...]()` | **0** |
| Raw `<img>` tags | **0** |
| Pipe-table blocks | 193, **all 193** with a GFM separator row |
| Column-alignment markers (`:---`) | **0** |
| `[click here]` / `[here]` / `[read more]` / `[this]` / `[link]` link texts | **0** |
| Bare `http(s)://` outside backticks | **0** (all occurrences are example data in code spans) |

---

## 2. Constraints the existing system imposes

1. **The direction decision is client-side and locale-derived.** Anything that wants a correct `dir` before first
   paint has to put it on `<html>` in the ERB, next to `lang`. The precedent is right there: the dark-mode class
   is set by an inline `<head>` script explicitly "to avoid FOUC"
   (`app/views/layouts/_portal_head.html.erb:35-43`). Direction never got the same treatment.
2. **`data-turbo="false"` on the locale switcher is load-bearing.** Turbo Drive replaces `<body>` and merges
   `<head>`; it does not re-apply `<html>` attributes. `_topbar.html.erb:58` forces a full navigation for locale
   changes, which is why `lang`/`dir` stay coherent across a language switch today. Any redesign of the switcher
   must keep that, or re-set both attributes on `turbo:load`.
3. **Administrate's form CSS is physical throughout.** `_field-unit.scss:10-15` (`float: left; margin-left;
   text-align: right`), `:17-22`, `:26`, `_forms.scss:77`; `grep -E '(direction|unicode-bidi)'` over
   `app/assets/stylesheets/administrate/` returns nothing. "Make Super Admin RTL" is a stylesheet rewrite, not a
   `dir` flip. The achievable target is an **RTL-aware content field inside an LTR chrome**.
4. **The seeder is the content writer, not the editor.** `Documentation::ContentSeeder` overwrites `content`,
   `title`, `description` and `meta` from the Markdown file on every run
   (`custom/app/services/documentation/content_seeder.rb:94-104`). Any authoring affordance that stores data —
   an alt-text field, a `dir` hint, a per-article direction override — must round-trip through the front matter
   or it is erased on the next sync.
5. **Arabic slugs are ASCII by convention.** `slug_for(key, locale)` appends `-ar`
   (`content_seeder.rb:84-87`), and the public route constrains the slug to `/[a-z0-9][a-z0-9\-_]*/`
   (`config/routes/documentation.rb:26`). Heading anchors, by contrast, are transliterated at runtime in JS.
6. **The accent colour is operator data with no contrast floor.** `portal.color` is validated for hex *format*
   only (`app/models/portal.rb:63`), defaults to `#1f93ff` (`:31`), and is injected into CSS custom properties
   at `app/views/layouts/_portal_scripts.html.erb:30-32,39-41`. Any contrast remediation that assumes a known
   link colour is assuming something the model does not guarantee.
7. **`prose` already flips; the hand-written chrome does not.** Fixing direction in the layout is a bounded,
   enumerable job (§1.2) and does not require touching the article renderer.

---

## 3. Findings

### 3.1 Direction: the layout

**F1 — `dir` is set only by client JavaScript, so both `ltr:` and `rtl:` utilities are inert on first paint.
`blocker`.**
`app/views/layouts/portal.html+documentation.erb:2` emits `lang` and nothing else; `grep -rn 'dir=' app/views/`
returns zero hits. `dir` arrives from `portalHelpers.js:153-162`, called at `:168` inside `initialize()`, which
is bound to `turbo:load` (`app/javascript/entrypoints/portal.js:9`). Tailwind 3.4.19 compiles both variants to
`[dir="…"]` descendant selectors (`node_modules/tailwindcss/lib/corePlugins.js:210-211`), so with no `dir`
attribute **neither** matches. Three consequences:

- Every Arabic page paints LTR and then flips. The theme flip was engineered out of existence inline in `<head>`;
  the direction flip was not.
- A client that does not execute the bundle — JS off, bundle 404, CSP block, a non-executing crawler — gets a
  fully LTR Arabic page with no `dir` at all.
- On the first paint at phone width, `_sidebar.html.erb:15` is `fixed inset-y-0 … w-72 max-md:z-50` with
  `ltr:left-0`, `rtl:right-0` and `max-md:ltr:-translate-x-full` **all** unmatched — no horizontal inset and no
  off-screen translate. The drawer is laid out at its static position rather than parked off-canvas. See §3.9/T1.

**F2 — direction derives from an exact-match language list, so a regional RTL locale silently reads LTR.
`major`, latent.**
`getLanguageDirection` tests `['ar','as','fa','he','ku','ur'].includes(code)`
(`advancedFilterItems/languages.js:746-749`) against `html.lang`, which `html_lang_attribute` produces as
`locale.tr('_','-')` (`app/helpers/portal_helper.rb:40-42`). `ar` matches; `ar-SA`, `ar-EG`, `fa-IR` do not.
Unreachable for the documentation corpus today, because `Documentation::Library::LOCALES` is `%w[en ar]`
(`library.rb:14`). It becomes reachable the first time a regional Arabic, Farsi, Hebrew or Urdu locale is added
to that constant, and it fails silently — the page simply renders LTR with no error anywhere.

**F3 — physical direction utilities in the documentation layout, against the project's own rule. `major`.**
CLAUDE.md requires logical Tailwind utilities (`ms`/`me`/`start`/`end`). Enumerated in §1.2. The ones that
visibly break under RTL:

| Where | What breaks under `dir="rtl"` |
|---|---|
| `_sidebar.html.erb:50,76` `border-l` with `ms-4 ps-3` | the category tree's vertical rule sits opposite its own indent |
| `_sidebar.html.erb:55,81` `border-l-2 border-n-portal` with `-ms-[13px] ps-3` | the active-article indicator bar lands on the far side of the label it marks |
| `_category_card.html.erb:15`, `categories/_header.html.erb:9` `-ml-*` | contributor avatars overlap in the wrong z-order direction |
| `articles/show.html+documentation.erb:23` `-ml-3` | the back-to-category footer link hangs off the wrong edge |
| `search/index.html+documentation.erb:50,56` `rounded-l-md`/`rounded-r-md` | Previous/Next swap under RTL but their rounded corners do not |

`TableOfContents.vue` is the inverse case: `ltr:`/`rtl:` pairs that *work* (it mounts after
`setDirectionAttribute`, `portalHelpers.js:168` before `:175`) but still violate the rule and still double the
surface area of every future change.

**F4 — direction-bearing icons never flip. `major`.**
`_breadcrumb.html.erb:11,28` and `search/index.html+documentation.erb:16` use `i-lucide-chevron-right` as a
breadcrumb separator; `_sidebar.html.erb:48,74` use it as a disclosure chevron with `group-open:rotate-90`;
`_category_card.html.erb:21` uses `i-lucide-arrow-right` with `group-hover:translate-x-0.5` for "Browse";
`articles/show.html+documentation.erb:24` uses `i-lucide-arrow-left` with `group-hover:-translate-x-0.5` for
"back to category"; `_topbar.html.erb:7` uses `i-lucide-panel-left-open` for the drawer. Under RTL each points
the wrong way and each hover translation moves the wrong way. The codebase already knows how to handle this —
`app/javascript/widget/components/specs/RtlDirectionalIcons.spec.js` exists for the widget. The pattern was not
carried into the portal.

**F5 — Arabic typography is actively damaged, and no Arabic font is specified. `blocker`.**
`app/javascript/portal/application.scss:11-17` sets `letter-spacing: 0.2px` on `html, body`, unconditionally,
with no `:lang(ar)` exception. Arabic is a cursive script whose letters join; positive tracking inserts gaps at
the joins. Separately, the documentation layout's `<body>` is `font-inter`
(`portal.html+documentation.erb:6`), whose stack is `Inter` → `-apple-system` → `system-ui` →
`BlinkMacSystemFont` → `Segoe UI` → `Roboto` → `Helvetica Neue` → `Tahoma` → `Arial` → `sans-serif !important`
(`tailwind.config.js:43,10-20`). Inter has no Arabic coverage, so Arabic resolves per-glyph to whatever the
platform supplies — `Tahoma` on Windows, SF Arabic via `system-ui` on recent macOS, and on Linux the stack has
no Arabic-covering entry at all before the generic fallback. There is no `@font-face` for an Arabic family
anywhere and no `:lang(ar)` or `[dir="rtl"]` font override. This is the one finding where a 63-article Arabic
corpus is read in a font nobody chose.

**F6 — code blocks have no `dir="ltr"`. `major`.**
`grep -rni 'unicode-bidi|plaintext'` over `app/javascript` returns nothing relevant; nothing sets `direction` on
`pre`/`code`. Under `dir="rtl"` a `<pre>` inherits RTL, so `text-align: start` resolves to the right edge, the
`overflow-x` scroll (`tailwind.config.js:207-212`; `_content.html.erb` relies on `prose`) begins from the right,
and bidi-neutral characters reorder. The Arabic corpus does contain such blocks — e.g.
`custom/db/documentation/ar/integrations/webhooks.md:76`,
`sha256=HMAC_SHA256(secret, "<timestamp>.<raw body>")`, which is entirely LTR/neutral and full of mirrored
bracket pairs. That is the worst case for an unisolated `pre` in an RTL context.

**F7 — tables: correct markup, logical CSS, two real gaps. `major` (keyboard) / `minor` (alignment).**
Good news first, because it is load-bearing for the editor decision: all 193 pipe blocks in the corpus carry a
GFM separator row, so CommonMark's `:table` extension emits a real `<thead>`/`<th>` for every one of them —
programmatic table headers exist corpus-wide. The cell styling in `_content.html.erb:14-16` is logical
(`!text-start`, `!border-e`), and `@tailwindcss/typography` is logical throughout (§1.2).

The gaps:
- The scrollable wrapper `<div class="tableWrapper">` emitted at `lib/custom_markdown_renderer.rb:37,86,88` has
  **no `tabindex="0"`, no `role="region"` and no accessible name**, while `_content.html.erb:12` makes it
  `overflow-x-auto`. A keyboard-only user cannot scroll a table wider than the column. The WhatsApp-error
  tables are the widest in the corpus.
- `_content.html.erb:14-15` forces `!text-start` on `th`/`td` with `!important`, which discards any author
  column alignment. Zero alignment markers exist today, so this is unexercised — but it is a silent override an
  editor upgrade would surface immediately.

**F8 — mixed-direction runs have no isolation anywhere. `minor` today, `major` once dates and numbers matter.**
No `dir="auto"`, no `<bdi>`, no `unicode-bidi: isolate` exists in the portal. Three live instances:
`documentation_layout/articles/_header.html.erb:2,25` interpolates
`article.updated_at.strftime("%b %-d, %Y")` → `Oct 13, 2026` into the Arabic string
`آخر تحديث في %{last_updated_on}` (`config/locales/ar.yml`); `articles/_release_meta.html.erb:19` interpolates
the raw ISO `release_date` into `released_on`; `search/_results.html.erb:38` repeats the pattern with
`%b %d, %Y`. English month abbreviation plus digits plus a comma, unisolated, inside an RTL sentence. The date
is also not localized at all (hard-coded `strftime`, no `l()`) and carries no `<time datetime>`.

### 3.2 Locale correctness on the portal

**F9 — the locale switcher always loses the reader's place. `blocker`.**
`_topbar.html.erb:57` links each language to `/hc/<portal>/<code>/` — the locale **home page**. An Arabic reader
on `whatsapp-templates-ar` who switches to English lands on the English documentation home, not on
`whatsapp-templates`. The data to do better is already computed on the same page: `portal_locale_alternates`
emits the full hreflang set in `documentation_layout/articles/_meta_head.html.erb:19-21`, and
`associated_article_id` links the siblings (`content_seeder.rb:77,90-92`). The switcher consults neither. The
switcher itself *is* reachable and correct in every other respect — `<details>/<summary>` is natively
keyboard-operable, it marks the current locale with a check icon, and `data-turbo="false"` at `:58` correctly
forces a full navigation so `lang`/`dir` stay coherent (constraint 2).

**F10 — every contextual-help link from the product reaches the English article, never the Arabic one.
`blocker`.**
`documentationArticleUrl(base, key)` builds `${base}/${slug}` with no locale
(`app/javascript/dashboard/helper/documentationLinks.js:101-106`). The route carries no locale segment:
`get 'docs/:article_slug'` (`config/routes/documentation.rb:25-26`). So `params[:locale]` is nil in
`DocumentationController#article` (`custom/app/controllers/documentation_controller.rb:22`), and
`Library.article_for(key, locale: nil)` evaluates `by_key.find_by(locale: nil)` → nil, then
`by_key.find_by(locale: 'en')` → the English row (`custom/app/services/documentation/library.rb:54-57`).
87 registry keys, 63 Arabic articles, **zero of them reachable from any in-product help link**. The resolution
chain was written for exactly this case; the locale just never arrives.

**F11 — untranslated chrome on the Arabic portal. `major`.**
In `config/locales/ar.yml`, still English: `public_portal.search.results_for`, `search.no_results`, **all six**
`search.found_results` plural forms, `sidebar.recommended`, `sidebar.recommended_subtitle`,
`sidebar.recommended_label`, `header.visit_website`, `header.recommended`, and all three `not_active.*`. The
visible effect: the Arabic search page's `<h1>` and `<title>` are both English
(`search/index.html+documentation.erb:2,22`), and so is the result count.

**F12 — hand-rolled binary plurals applied to Arabic. `major`.**
`documentation_layout/categories/_header.html.erb:1` does
`I18n.t(articles.size == 1 ? '…common.article' : '…common.articles')` and `:4` concatenates the bare count next
to it. Arabic has six CLDR plural categories; this is an English two-form rule. The correct mechanism is
demonstrated *in the same file* — `ar.yml`'s `public_portal.search.found_results` already carries
`zero/one/two/few/many/other`. `app/helpers/portal_helper.rb:119-128` has the same problem twice over:
`names.to_sentence` applies English conjunction rules to Arabic names, and `authors_others` hard-codes
`%{count} آخرون`.

**F13 — bare English fallback in the Arabic hero. `minor`.**
`documentation_layout/_hero.html.erb:8`:
`portal.localized_value('header_text', @locale).presence || 'How can we help?'` — a bare untranslated string in
a template, against CLAUDE.md's no-bare-strings rule. In practice the seeded `header_text` is English-only
anyway (`portal_seeder.rb:13`), so the Arabic home page's `<h1>` reads
"Guides for setting up and running Lynomia Chat."

### 3.3 Accessibility — the rendered article

**F14 — heading order inside articles is correct, corpus-wide. `minor` (clean).**
I tried to break this and could not. All 126 files begin at `##`, no file contains a body `#`, and there are
zero level skips measured across the whole corpus (§1.4). With `documentation_layout/articles/_header.html.erb:6`
supplying the page `<h1>`, every article's chain is h1 → h2 → h3. `portalHelpers.js:17` collects `h1, h2, h3`
from `#cw-article-content` only, so the page `<h1>` is correctly excluded from the TOC.

**F15 — heading-level skip on the category and search pages. `major`.**
`documentation_layout/categories/_header.html.erb:21` is the `<h1>`; the article list below it is made of
`_article_card.html.erb:10` `<h3>` with no intervening `<h2>`. Identical on search:
`search/index.html+documentation.erb:21` `<h1>` → cards `<h3>`. The home page is correct only because
`documentation_layout/_section_header.html.erb:2` happens to supply the `<h2>`
(`show.html+documentation.erb:4,25`).

**F16 — heading permalinks are unreachable by keyboard or touch, and all share the accessible name "#".
`major`.**
`portalHelpers.js:23-29` appends an `<a class="permalink">` with `textContent = '#'` to every heading.
`app/javascript/portal/application.scss:46-56` hides it with `visibility: hidden`, revealed only under
`.heading:hover` — there is no `:focus-within`. `visibility: hidden` removes the element from the accessibility
tree *and* the tab order, so it cannot be focused at all, and a touch device has no hover to trigger it. Even if
it could be reached, a link's accessible name comes from its content before its `title`, so an article with ten
headings has ten links all named "#" (WCAG 2.4.4).

**F17 — duplicate heading ids, and Arabic collides more readily. `major`.**
`portalHelpers.js:7` imports `@sindresorhus/slugify`'s **default** export under the local name
`slugifyWithCounter`; the real counter is a separate named export. So `:19` runs the plain, non-deduplicating
`slugify`. Arabic headings do transliterate to usable anchors — verified against the installed package:
`نظرة عامة` → `nzrt-eamt`, `إعداد واتساب للأعمال` → `iedad-watsab-llaemal`, `الخطوة 1: ربط الحساب` →
`alkhtwt-1-rbt-alhsab` — which is genuinely good news for Arabic TOC anchors. But transliteration *collapses*
distinctions that Arabic orthography keeps (hamza forms, ta marbuta vs ha), so two distinct Arabic headings
collide into one slug more easily than two English ones. Two elements then share an `id`, `getElementById` in
`TableOfContents.vue:69` finds only the first, and the second TOC entry jumps to the wrong place.

**F18 — image alt text: confirmed, there are no images. `minor` today, `blocker` the moment one is added.**
Confirming the brief: **zero** images in the corpus — 0 markdown `![...]()` and 0 `<img>` across
`custom/db/documentation/**` and `custom/db/changelog/**` (§1.4). So there is no alt-text defect to report. There
is also no enforcement point anywhere: `lib/custom_markdown_renderer.rb:61-71` unconditionally emits
`alt="<children>"`, so `![](url)` produces a silent `alt=""` indistinguishable from a deliberate decorative
image; `content_seeder.rb` validates nothing about images; and `lib/tasks/documentation_seo_audit.rake` audits
titles, descriptions, canonicals and hreflang but no media. **There is also no caption mechanism at all** — the
only carrier is `title=` (`custom_markdown_renderer.rb:67`), which renders as a tooltip, is invisible to most
users and is not a caption; no `<figure>`/`<figcaption>` path exists in the renderer or the Markdown dialect. So
"what happens to an image caption" has a definite answer: nothing can produce one.

**F19 — link text quality in the corpus is good. `minor` (clean).**
Zero `[click here]`, `[here]`, `[read more]`, `[more]`, `[this]`, `[link]` or `[learn more]` link texts across
all 126 files; every bare `http(s)://` occurrence is example data inside a code span, never a link target. The
Arabic link texts are descriptive noun phrases matching their English counterparts (e.g. `الأدوار والصلاحيات`,
29 occurrences). This area needs no work.

### 3.4 Accessibility — layout, landmarks and keyboard

**F20 — two `<main>` landmarks. `major`.**
`app/views/layouts/portal.html+documentation.erb:9` opens `<main class="…" role="main">` around the whole page,
and `:16` opens a second `<main>` inside it around the yielded content. A document has one main landmark; a
screen reader's "jump to main" becomes ambiguous.

**F21 — no skip link. `major`.**
There is none anywhere in the portal. Every article page puts the topbar and then the entire category/article
tree (`_sidebar.html.erb:22-89` — on this corpus, 12 categories and up to 63 article links) ahead of the article
in the tab order. The only `sr-only` elements in the whole portal are the two search submit buttons
(`search/_form.html.erb:17`, `PublicArticleSearch.vue:171`).

**F22 — the mobile navigation drawer is not keyboard-operable. `blocker` at phone width.**
It is a CSS checkbox hack. `_sidebar.html.erb:13`:
`<input type="checkbox" id="sidebar-drawer-checkbox" class="peer/sb hidden">`. Tailwind's `hidden` is
`display: none`, which removes the input from the tab order entirely. The two triggers are `<label for=…>`
elements (`_topbar.html.erb:6`, `_sidebar.html.erb:17`) and labels are not focusable. So a keyboard or
switch-access user on a phone can neither open nor close the navigation. There is no `aria-expanded`, no
`aria-controls`, no focus trap while open, and no Escape handler. Compounded by F1: on first paint the drawer may
render open, covering the article.

**F23 — `aria-current` appears nowhere; "current" is colour-only in four places. `major`.**
`grep -rn 'aria-current'` over `app/views/public/` and `app/javascript/portal/` returns nothing. The current
page or position is conveyed by `text-n-portal` alone at: the active sidebar article
(`_sidebar.html.erb:55,81`), the active sidebar category (`:41`), the active topbar nav item
(`_topbar.html.erb:21`), and the active TOC heading (`TableOfContents.vue:82,88`). The last breadcrumb crumb is a
plain `<span>` with no `aria-current="page"` (`_breadcrumb.html.erb:29`). WCAG 1.4.1 and 4.1.2 — and the colour
in question is the one that fails contrast (F28).

**F24 — four unlabelled navigation landmarks, and the breadcrumb is not a list. `minor`.**
`_breadcrumb.html.erb:2` is a bare `<nav>` with no `aria-label`, built from `<a>`/`<span>` rather than
`<ol>`/`<li>`. `search/index.html+documentation.erb:8-18` hand-copies the same markup, also unlabelled.
`_sidebar.html.erb:22` `<nav>` is unlabelled. `TableOfContents.vue:101` `<nav>` is unlabelled. Only
`_topbar.html.erb:19` carries `aria-label` (`public_portal.sidebar.primary_nav`, which *is* translated in
`ar.yml`). Separator chevrons are correctly `aria-hidden="true"` throughout.

**F25 — the TOC heading string is computed, shipped to the browser and never rendered. `minor`.**
`public_portal.toc_header` ("في هذه الصفحة" / "On this page") is interpolated into
`window.portalConfig.tocHeader` at `app/views/layouts/_portal_scripts.html.erb:93`, and `TableOfContents.vue`
never reads it. The TOC therefore has neither a visible heading nor an accessible name — which is also F24's
fourth unlabelled landmark.

**F26 — invalid interactive nesting in the sidebar. `major`.**
`_sidebar.html.erb:47` places `<a href="<%= category_url %>">` inside the `<summary>` of a `<details>`.
`<summary>` is itself the disclosure's activation control; an interactive element nested inside it is invalid
HTML, and activating the inner link both navigates and toggles the disclosure. Keyboard behaviour here is
browser-dependent, which is exactly the problem.

**F27 — search is an unlabelled input that navigates on every keystroke. `major`.**
`search/_form.html.erb:10-16` is `<input type="text" name="query">` with a `placeholder` and **no `<label>`**
(WCAG 1.3.1, 3.3.2 — a placeholder is not a label and vanishes on input), plus `autofocus`, which moves focus
past the page heading on load. `search/_search_handler.html.erb:14-26` then calls `form.requestSubmit()` 500 ms
after each keystroke — a full page navigation triggered by typing (WCAG 3.2.2). Lines 8-12 restore the caret
afterwards, which mitigates the typing experience but does not change the fact that the page reloads, the
landmark structure is re-announced, and the result count (`search/index.html+documentation.erb:34-36`) is a
plain `<p>` with no `aria-live`/`role="status"`.

### 3.5 Colour contrast, documentation layout

Computed from the token definitions, not measured in a browser (§3.9/T8). Light mode is `#ffffff`
(`portal.html+documentation.erb:6,12`); dark mode is `--slate-2` `#18191b`
(`app/javascript/dashboard/assets/scss/_next-colors.scss:177-178`).

| Token | Hex | Ratio | Where it is used | Verdict |
|---|---|---|---|---|
| `--dynamic-portal-color` (default) | `#1f93ff` | **3.15:1** | **every article-body link** (`articles/show.html+documentation.erb:18` `prose-a:text-n-portal`), active sidebar item, active TOC item | **fails 1.4.3 (4.5:1)** |
| same, dark on `#18191b` | `#1f93ff` | 5.59:1 | ditto | passes |
| `--slate-10` | `#80838d` | **3.78:1** | sidebar `CATEGORIES` label (`_sidebar.html.erb:29`, 12px), article counts (`categories/_header.html.erb:3`, 14px), hero "Popular:" (`_hero.html.erb:20`), footer branding (`_footer.html.erb:27`, 12px) | **fails 1.4.3** |
| `--slate-10` dark | `#777b84` | **4.15:1** | ditto | **fails 1.4.3** |
| `--slate-11` | `#60646c` | 5.94:1 | breadcrumbs, table body cells (`_content.html.erb:15`) | passes |
| `--slate-9` | `#8b8d98` | 3.30:1 | breadcrumb chevrons (decorative, `aria-hidden`) | passes 1.4.11 |
| `--border-weak` | `#eaeaea` | **1.20:1** | **every table cell border** (`_content.html.erb:12,14,15,16`), card borders, sidebar and topbar borders, dropdown borders | **fails 1.4.11 (3:1)** |
| `--border-weak` dark | `#1f1f25` | **1.07:1** | ditto | **fails 1.4.11** |
| `--slate-2` as `th` background | `#f9f9fb` | 1.05:1 | `[&_th]:!bg-n-slate-2` (`_content.html.erb:14`) | header row visually indistinct from body |

Two structural points on top of the numbers.

- **Links in article bodies are identified by colour alone.** `articles/show.html+documentation.erb:18` passes
  `prose-a:no-underline hover:prose-a:underline`. At rest there is no underline; the only cue is a hue at
  3.15:1 against the page and 3.28:1 against the surrounding `prose` body text. The underline returns on
  `hover` but **not on `focus`**, so the keyboard user never gets the non-colour cue the mouse user gets. WCAG
  1.4.1 plus 1.4.3.
- **The failing colour is operator data.** `portal.color` is validated for hex format only
  (`app/models/portal.rb:63`) and injected straight into `--dynamic-portal-color`
  (`_portal_scripts.html.erb:30,39`). There is no contrast floor anywhere in the code, so no remediation that
  assumes a known link colour is safe. Severity: **blocker** for link contrast, **major** for table borders.

**F29 — the positive baseline, for the editor decision. `minor` (clean).**
Worth naming so the upgrade copies it rather than reinventing it.
`app/javascript/portal/components/SidebarThemeToggle.vue:98-106` is a real `<button>` with `aria-label`,
`aria-expanded` and a logical `end-0` popover — the one fully correct interactive component in the portal. The
topbar locale menu and `documentation_layout/articles/_actions.html.erb` use `<details>/<summary>`, which is
natively keyboard-operable and focusable, with logical `end-0`. `_footer.html.erb:45-46` gives every social icon
both `aria-label` and `title`. Decorative icons carry `aria-hidden="true"` consistently across the layout
(`_breadcrumb.html.erb:7,11,28`, `_sidebar.html.erb:18,25,45,48`, `_actions.html.erb:10,12,19,22`, and others).
`documentation_layout/_user_avatar.html.erb:15` gives avatar images a real `alt`.

### 3.6 Super Admin: the Arabic authoring reality

**F30 — the content field has no `dir`, and no override exists to give it one. `blocker` for Arabic authoring.**
`app/views/layouts/super_admin/application.html.erb:16` emits `<html lang="<%= I18n.locale %>">` with no `dir`,
so the admin is UA-default LTR, as the brief states. The content editor is Administrate's stock partial,
`vendor/bundle/ruby/3.4.0/gems/administrate-0.20.1/app/views/fields/text/_form.html.erb:17-22`:

```erb
<div class="field-unit__label"><%= f.label field.attribute %></div>
<div class="field-unit__field"><%= f.text_area field.attribute %></div>
```

`f.text_area` is called with **no options at all** — no `dir`, no `lang`, no `spellcheck`, no `rows`. There is no
override: `app/views/fields/` contains no `text/` directory, and `custom/app/views/fields/` holds only
`article_meta_field` and `article_author_field`. **So the answer to "what `dir` does the content field get" is:
none, and the paragraph direction is LTR.**

What that costs an Arabic author, specifically — these are CommonMark constructs in the existing corpus:
- `[نص](/docs/slug)` — `[`, `]`, `(`, `)` are bidi *mirrored* pairs. In an LTR paragraph containing an RTL run,
  they render mirrored, so the author cannot see whether the brackets balance or which bracket belongs to which
  link. The Arabic corpus contains hundreds of these (§1.4: the Arabic link-text histogram).
- `- عنصر` and `1. خطوة` — the list marker is bidi-neutral/EN and takes the paragraph direction, so the marker
  and its Arabic text sit at opposite visual ends of the line.
- Sentence-final `.`, `،`, `؟` — trailing neutrals take the paragraph direction and jump to the far edge.
- `| عنوان | وصف |` table rows — pipes are neutral; a mis-aligned Arabic table is unverifiable by eye.

`dir="auto"` on this one textarea would set direction from the first strong character, which for a corpus file
beginning `## عنوان` is Arabic. It is the cheapest material improvement in this entire report.

**F31 — `rows: 28` is a no-op, which contradicts `01-current-system.md` §6. `major`.**
`custom/app/dashboards/article_dashboard.rb:19` declares
`content: Field::Text.with_options(rows: 28)`. `Administrate::Field::Text`
(`vendor/.../administrate-0.20.1/lib/administrate/field/text.rb`) implements only `truncate`/`truncation_length`
and knows nothing about `rows`; the form partial passes no options; and `grep -rn 'rows'` over the gem's
`app/views/` and `lib/` returns **nothing**. The textarea's size therefore comes entirely from
`app/assets/stylesheets/administrate/base/_forms.scss:41-49,70-72` (`width: 100%`, `padding: 0.5em`,
`resize: vertical`) over the browser's default two rows, inside a `max-width: 31.15rem` column
(`_field-unit.scss:17-22`).

`docs/documentation-v2/01-current-system.md:210` (§6) states: *"The editor is
`content: Field::Text.with_options(rows: 28)` (`article_dashboard.rb:19`). A 28-row textarea."* It is not a
28-row textarea. **Agent 000 and Agent 063 should arbitrate this**, since
the editor evaluation's baseline description of the current state is wrong in the direction that flatters it.

**F32 — labels are correct; error association is not. `major`.**
Labels are fine: Administrate's partials all emit `f.label field.attribute`
(`fields/text/_form.html.erb:18`, `fields/string/_form.html.erb:19`, `fields/select/_form.html.erb:19`), giving
a properly associated `<label for>` for every attribute in `FORM_ATTRIBUTES` (`article_dashboard.rb:36`), and
the custom meta partial does the same per key (`article_meta_field/_form.html.erb:7,16`).

Errors are not. `vendor/.../administrate/application/_form.html.erb:18-34` renders all errors once, at the top
of the page, as `<div id="error_explanation">` containing an `<h2>` and a `<ul>` of `full_messages`. There is:
no `aria-invalid` on any field; no `aria-describedby` from a field to its message; no `role="alert"` or
`aria-live` on the container; no per-field inline error; no link from a message to the field it concerns; and no
focus management after the re-render. A screen-reader user who submits an Arabic article with an invalid slug
gets a silently re-rendered page and no route to the offending field. Relatedly, the required marker is
CSS-generated content — `_field-unit.scss:40-45`, `.field-unit--required label::after { content: ' *' }` — so it
is not in the accessibility tree, and the inputs carry no `required`/`aria-required`.

**F33 — focus visibility is removed from exactly the controls an author types in. `major`.**
`app/assets/stylesheets/administrate/base/_forms.scss:55-58`, applied to every text input **and `textarea`**:

```scss
&:focus {
  border-color: $action-color;
  outline: none;
}
```

Meanwhile `:88-96` gives `select`, checkbox, radio and file a real `outline: $focus-outline`. So the locale,
status, portal and category selects get a 3 px ring and **the article body textarea gets none**. Its only focus
cue is a 1 px border recolour from `$base-border-color` `#f0f4f5` (**1.11:1** vs white) to `$action-color`
`#1f93ff` (3.15:1) — and the `:hover` state at `:51-53` changes the same border, so hover and focus are
distinguishable only by hue. `outline: none` also erases the indicator under forced-colors/High Contrast. And
the ring that *does* exist is `transparentize($action-color, 0.4)`
(`app/assets/stylesheets/administrate/library/_variables.scss:42-45`) = `rgba(31,147,255,.6)`, which composites
over white to `#79beff` = **1.98:1, failing 1.4.11's 3:1**. So the focus indicator is absent where it matters
most and non-compliant where it is present.

**F34 — the `meta` field: an orphan label, unassociated hints, inline styles, no `dir`. `major`.**
`custom/app/views/fields/article_meta_field/_form.html.erb:2` renders
`f.label field.attribute, 'Metadata'` → `<label for="article_meta">`, but **no element has `id="article_meta"`**
(the inputs are `article_meta_title`, `article_meta_description`, `article_meta_version`,
`article_meta_release_date`, `article_meta_feature_image`, `article_meta_tags`). A label with a dangling `for`
is an accessibility error and clicking it focuses nothing. The hints at `:12,20` are `<p>` siblings with **no
`aria-describedby`**, so the only SEO guidance in the whole authoring surface — "Around 150 characters reads
best in search results" (`custom/app/fields/article_meta_field.rb:26`) — never reaches a screen reader; and at
`font-size: 12px; opacity: .7` over `$base-font-color` `#293f54` the effective `#697987` is **4.48:1, a hairline
fail of 1.4.3's 4.5:1**. Lines 6, 12, 15 and 20 are inline `style=` attributes, against CLAUDE.md's
Tailwind-only rule. And neither `article_meta_title` nor `article_meta_description` carries `dir`/`lang`, so the
Arabic SEO description that ends up in `<meta name="description">`
(`documentation_layout/articles/_meta_head.html.erb:28`) is authored in the same bidi-blind input as the body.

**F35 — `meta['feature_image']` is authored and never read. `minor`.**
It is declared, labelled "Feature image URL" and documented as "the image shown with the release"
(`custom/app/fields/article_meta_field.rb:13,21,30`), and
`grep -rn feature_image app/ custom/app/ lib/` finds **no reader anywhere** — not in
`documentation_layout/articles/_meta_head.html.erb`, not in `_release_meta.html.erb`, not in any jbuilder. So
the only image-shaped field in the authoring surface renders nothing, which is also why F18's alt-text question
has no current answer: there is no `<img>` to attach alt text to, and no alt field beside the URL field.

**F36 — Administrate's form chrome is physical, so RTL admin is out of scope by construction. Constraint.**
`_field-unit.scss:10-15` (`float: left; margin-left: .625rem; text-align: right` for the label column), `:17-22`
(`float: left; margin-left: 1.25rem`), `:26` (`margin-left: 7.5%`), `_forms.scss:77` (`margin-right` on
checkbox/radio); and `grep -E '(direction|unicode-bidi)'` over `app/assets/stylesheets/administrate/` returns
nothing. Setting `dir="rtl"` on the admin `<html>` would not flip this layout, it would break it. See §4,
Option A.

### 3.7 What an RTL-aware editor would need

Derived from F30–F36, in dependency order rather than wish order.

| # | Requirement | Why, from the findings |
|---|---|---|
| 1 | `dir="auto"` (or an explicit `dir` bound to the record's `locale`) on the content field and on the `meta` title/description inputs | F30, F34 — the single highest-value change, and it works inside the existing LTR chrome |
| 2 | A real editing height, declared somewhere that takes effect | F31 — `rows: 28` does nothing today |
| 3 | A rendered preview that uses the **public** `dir`, `lang`, font stack and `prose` styles | F1, F5, F6 — a preview in the admin's LTR Inter chrome would not show the author what a reader sees. `SuperAdmin::ArticlesController#preview` already redirects to the real public page (`custom/app/controllers/super_admin/articles_controller.rb:22-25`), which is the right primitive to build on |
| 4 | Bidi-safe affordances for the constructs that are unreadable as source: links, list markers, table cells | F30 — these are the specific CommonMark constructs that break, not "markdown is hard" |
| 5 | LTR-locked code-block editing and rendering | F6 — code must be `dir="ltr"` on both sides |
| 6 | Per-field error association and focus management | F32, F33 |
| 7 | An alt-text field that round-trips to front matter, and a caption carrier | F18, F35, and constraint 4 — anything the editor stores outside the Markdown file is erased by the next `documentation:content` run |
| 8 | A contrast floor on `portal.color`, or a non-colour link cue | F28 — currently the link colour is unvalidated operator data |

### 3.8 Adjacent observations (not mine to own, but they touch locale)

- **`set_locale` yields twice.** `app/controllers/public/api/v1/portals/base_controller.rb:38-43` calls
  `switch_locale_with_portal(&)` or `switch_locale_with_article(&)` — each of which invokes the block inside
  `I18n.with_locale` — and then calls `yield` again at `:42`, outside it. The rendered output appears to be
  correct, because Rails' implicit render happens inside the first yield and `performed?` guards the second. But
  the whole callback chain and action body run twice per request, the second time at `I18n.default_locale`. This
  is the mechanism that makes the `lang` attribute right, and it is fragile. Needs a request spec to settle
  (§3.9/T9). Severity: `minor` for correctness, unknown for performance. Owner: whoever holds the portal
  controller.
- **`switch_locale_with_article` looks up the article unscoped.** `:54` is
  `Article.find_by(slug: params[:article_slug])` across all portals and all accounts, so a tenant article whose
  slug collides with a docs slug would set `@locale` — and therefore `lang` and `dir` — from the wrong record.
  `:55` also logs "Article: not found" unconditionally, even on success. Severity: `minor`.

### 3.9 What I could not test by reading — and the test for each

Nothing below is a verdict. Each is a claim derived from source that needs a browser, and each names the check.

| # | Claim at risk | The test |
|---|---|---|
| T1 | F1 — the FOUD, and the mobile drawer on first paint | Load `/hc/lynomia-docs/ar/` and an `-ar` article at 390 px width with the Vite bundle blocked (DevTools request blocking) and screenshot; then unblocked on Slow-3G throttling, recording the first 2 s. Check whether the `<aside>` overlays the article before `dir` lands. |
| T2 | F5 — letter-spacing breaking Arabic letter-joining, and which font actually resolves | Render the same Arabic article on macOS, Windows and Linux; read back `getComputedStyle(el).fontFamily` and the resolved face via DevTools' Rendering → Font panel; compare glyph joining with `letter-spacing: normal` forced. |
| T3 | F6 — code-block reordering under RTL | Open `custom/db/documentation/ar/integrations/webhooks.md`'s rendered page and compare the `sha256=HMAC_SHA256(...)` line against the Markdown source character by character; repeat with `dir="ltr"` forced on the `<pre>`. |
| T4 | F8 — bidi reordering of the interpolated English date | Screenshot `آخر تحديث في Oct 13, 2026` as rendered in the Arabic article header and check where the comma and the digits land; repeat wrapped in `<bdi>`. |
| T5 | F30 — what an Arabic author actually sees in the textarea | Paste `custom/db/documentation/ar/whatsapp/whatsapp-templates.md` into the Super Admin content field and screenshot; repeat with `dir="auto"` set via DevTools. Specifically check a `[نص](/docs/slug)` line and a `1. خطوة` line. |
| T6 | F17 — real Arabic slug collisions | Run the installed `@sindresorhus/slugify` over every `##`/`###` heading in all 63 Arabic files and count duplicate outputs per file. (I verified the transliteration works; I did not enumerate collisions across the corpus.) |
| T7 | F22, F16 — keyboard operability | Tab through an article page at 390 px and at 1440 px with a screen reader running; confirm the drawer cannot be opened, the permalinks cannot be focused, and record the tab-stop count before the article body. |
| T8 | F28 — contrast | The ratios are computed from the token definitions, not sampled from a rendered page. Confirm with axe-core or Lighthouse against a live `-ar` and `-en` article in both colour schemes, and against a portal whose `color` an operator has changed. |
| T9 | §3.8 — the double yield | A request spec on `GET /hc/lynomia-docs/articles/<slug>` counting invocations of `ChatwootMarkdownRenderer#render_article`, and asserting the response body's `<html lang>`. |
| T10 | F2 — regional RTL locales | Add `ar_SA` to `Documentation::Library::LOCALES` on a scratch install and assert `html.dir`. Not run: it requires a database. |

---

## 4. Options

### Decision 1 — where `dir` comes from (F1, F2)

| Option | Trade-off |
|---|---|
| **A. Emit `dir` in the ERB beside `lang`** — a `html_dir_attribute(locale)` helper next to `html_lang_attribute` (`app/helpers/portal_helper.rb:40-42`), applied in all three portal layouts | Correct before first paint, correct without JS, correct for crawlers. Needs a server-side RTL locale set, which duplicates the JS list unless the JS is changed to read the attribute it already reads (`portalHelpers.js:159`) — and it already reads `html.lang`, so making the server authoritative and the JS a no-op for direction is a strict simplification. One file per layout. **Recommended.** |
| B. Keep JS, move it inline into `<head>` | Matches the existing theme-FOUC pattern (`_portal_head.html.erb:35-43`), so it is a familiar shape. But it still fails with JS off and for non-executing crawlers, and it keeps direction in a dashboard module (`advancedFilterItems/languages.js`) that has nothing to do with the portal. |
| C. Do nothing; accept the flip | Already the status quo. Every Arabic page visibly flips and the mobile-drawer first paint stays wrong. Not defensible for a documentation portal shipping 63 Arabic articles. |

Whichever is chosen, **the RTL locale set must stop being an exact-match array** (F2): match on the primary
subtag, so `ar-SA` and `ar` behave the same.

### Decision 2 — physical vs. `ltr:`/`rtl:` vs. logical (F3, F4)

| Option | Trade-off |
|---|---|
| **A. Logical utilities everywhere** — `border-s`, `start-0`, `-ms-*`, `border-s-2`; direction-neutral or mirrored icons | Matches CLAUDE.md. Halves the class surface. Works without any `dir` at all for the margin/padding/border cases, because logical properties resolve from the inherited `direction`, which `dir="rtl"` sets — so Decision 1 and this one are independent and this one is safe to do first. The 11 sites are enumerated in §1.2. **Recommended.** |
| B. Finish the `ltr:`/`rtl:` pairs | Lower apparent risk (it is what `TableOfContents.vue` already does) but doubles every class, leaves F1's "neither variant matches" failure mode intact, and keeps a rule CLAUDE.md asks against. |

Icons are a separate sub-case: `chevron-right`/`arrow-right`/`arrow-left`/`panel-left-open` need either a
mirrored sibling under `rtl:` or an `rtl:-scale-x-100` wrapper. The widget's existing
`RtlDirectionalIcons.spec.js` is the precedent to extend rather than a new pattern to invent.

### Decision 3 — the authoring field (F30, F31)

| Option | Trade-off |
|---|---|
| **A. Override Administrate's `text` field partial** at `app/views/fields/text/_form.html.erb` (or a `custom/` field class) adding `dir: 'auto'`, `rows:`, `spellcheck` | Smallest production-ready change that solves the current problem. Uses Administrate's documented override mechanism. Fixes F30 and F31 together. Does not pre-empt any editor decision Agent 067 makes. **Recommended as the floor, independent of the editor choice.** |
| B. Wait for the editor upgrade and let the new editor own direction | Any CommonMark editor will need F30's requirements anyway (§3.7), so this is not wasted work — but it leaves the current reality unimproved for however long the upgrade takes, and the current reality is that Arabic authoring is bidi-blind. |
| C. Per-locale `dir` bound to the record's `locale` column rather than `dir="auto"` | More deterministic than `auto` and better for an Arabic article that opens with a code span or an English product name. Needs the field to see the record's locale, which `Administrate::Field::Base` does expose via `resource`. Worth preferring over `auto` if the field is being overridden anyway. |

Option A or C is a precondition for evaluating any editor against "RTL" honestly: today there is no baseline to
compare against.

### Decision 4 — contrast (F28, F33)

The link colour is the blocker and it is operator data. Two independent moves, both needed:

1. **A non-colour link cue in article bodies** — change `prose-a:no-underline hover:prose-a:underline`
   (`articles/show.html+documentation.erb:18`) to underline at rest, or at minimum add the underline on `focus`
   as well as `hover`. This removes the 1.4.1 failure regardless of what colour an operator picks, and it is a
   one-line change in one file.
2. **A contrast floor on `portal.color`** — either validate it in `app/models/portal.rb:63` against the
   portal's own background, or derive a text-safe variant (a darker `--dynamic-portal-color-text`) for text use
   while keeping the raw colour for fills. The second preserves operator intent, which the first does not.

`--border-weak` at 1.20:1 (1.07:1 dark) is a design-token decision that reaches far beyond documentation; the
narrowest defensible fix is a stronger border specifically for **table cells** in `_content.html.erb:14-16`,
where the border carries structural meaning, leaving decorative card borders alone. `--slate-10` at 3.78:1 is
likewise a token-wide issue; the documentation-scoped fix is to stop using it for body-sized text in the five
sites listed in §3.5.

### Decision 5 — locale reach (F9, F10)

F10 is a two-line fix with disproportionate value: pass the reader's locale into `documentationArticleUrl` and
accept it in the route, so `Library.article_for`'s existing fallback chain (`library.rb:54-57`) can do the job
it was written for. 63 Arabic articles become reachable from 87 product surfaces. F9 is larger — the switcher
needs the sibling article, which `portal_locale_alternates` already computes on the same page
(`documentation_layout/articles/_meta_head.html.erb:19-21`) — but it is the difference between a bilingual
portal and two monolingual ones sharing a domain.

---

## 5. Risks

1. **Turning `dir="rtl"` on properly will expose breakage currently hidden by F1.** Today the `rtl:` utilities
   never fire, so nobody has seen the RTL layout. The moment `dir` lands before paint, the physical utilities in
   §1.2 become visibly wrong rather than invisibly wrong. Decision 2 should land **with or before** Decision 1,
   not after. This is the central reason "RTL must be tested, not assumed": there is no evidence anywhere in the
   repository that the RTL documentation layout has ever been looked at — no spec asserts `dir`, direction or any
   RTL behaviour for the portal (`spec/helpers/portal_helper_spec.rb` covers `html_lang_attribute` only;
   `grep -rln 'setDirectionAttribute|getLanguageDirection'` over `spec/` and `app/javascript/portal/specs/`
   returns nothing).
2. **Any `dir` change must keep the Turbo contract.** Turbo Drive does not re-apply `<html>` attributes.
   `data-turbo="false"` on the locale switcher (`_topbar.html.erb:58`) is what keeps `lang`/`dir` coherent
   across a language change today. A switcher redesign for F9 that drops it, or that uses Turbo navigation to
   reach the sibling article, will leave `lang` and `dir` stale on the new page.
3. **Anything the editor stores outside the Markdown file is erased.** `ContentSeeder` overwrites `content`,
   `title`, `description`, `category`, `position`, `meta` and forces `status` on every run
   (`content_seeder.rb:94-104`). Alt text, captions, a per-article direction override and any structured
   component the editor introduces must round-trip through the front matter, or the next `documentation:content`
   run deletes the author's work. This is the same two-writers problem `01-current-system.md` §3 raises, seen
   from the editor side.
4. **`01-current-system.md:210` (§6) overstates the current editor (F31).** `rows: 28` is a no-op. The editor
   evaluation's "what we have today" baseline is better than reality, which biases any comparison against a
   candidate editor. Agent 000 / Agent 063 to arbitrate.
5. **F10 and F9 together mean the Arabic corpus is largely unreachable today.** Before measuring Arabic article
   traffic, SEO performance or corpus quality, note that no in-product link reaches an Arabic article and the
   locale switcher cannot reach an Arabic article from its English sibling. Any Arabic usage data gathered now
   measures the routing defect, not the content. This matters to agents 061, 073–080 and 094.
6. **The accent-colour contrast failure is not fixable inside the documentation layout alone.** `portal.color` is
   per-portal operator data with format-only validation. A documentation-scoped fix (Decision 4.1) removes the
   1.4.1 failure but not the 1.4.3 one; the 1.4.3 fix requires either a model-level constraint or a derived
   text-safe token, both of which affect every Help Center portal in the installation, not just the two platform
   ones.
7. **Low confidence on the magnitude of the RTL rendering defects, high confidence on their existence.** Every
   RTL finding here is read from source. F1, F5, F6, F8, F22, F30 are structurally certain — the attribute is
   absent, the property is set, the element is `display: none` — but *how bad each looks* is unmeasured. §3.9
   names the ten tests. Do not treat any severity in this report as validated until T1–T8 have been run.
