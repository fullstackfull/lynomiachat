---
agent: 075
scope: JSON-LD / structured data on the public documentation (what is emitted, whether it is valid and honest, what else the planned corpus would justify)
confidence: medium
---

Read-only. Repository findings below are from reading source, specs and the corpus; nothing was rendered, no rake task
was run, and no production data was read. Two classes of claim are **unverified here**, and the brief did not
authorise network reads: (a) schema.org vocabulary details (recalled, high confidence), (b) Google Search Central
behaviour (recalled; marked "recalled" wherever it appears). Neither is a Meta claim. Whoever acts on a Google-policy
statement should re-read the Google page first.

## 1. What exists today

**One helper, one call site, two blocks per article page, nothing else.** A search for `ld+json`, `schema.org`,
`itemscope`, `itemprop` and `json_ld` over `app custom lib config` finds only the following (the mailer's
`itemtype="http://schema.org/EmailMessage"` at `app/views/layouts/mailer/base.liquid:99,106` is email markup, not
documentation).

| Piece | Where |
|---|---|
| `documentation_breadcrumb_schema(portal, article)` → `BreadcrumbList` | `custom/app/helpers/documentation_helper.rb:64-75` |
| `documentation_article_schema(portal, article)` → `TechArticle` | `custom/app/helpers/documentation_helper.rb:83-95` |
| `documentation_structured_data(payload)` → one `<script type="application/ld+json">` | `custom/app/helpers/documentation_helper.rb:99-101` |
| The only place it is called | `app/views/public/api/v1/portals/documentation_layout/articles/_meta_head.html.erb:64-65` |
| How that partial reaches `<head>` | `articles/show.html+documentation.erb:1-4` (`content_for :head`) → `app/views/layouts/_portal_head.html.erb:16-17` |
| Gate: only the `documentation` variant | `app/controllers/public/api/v1/portals/base_controller.rb:26-32`; the seeder sets `'layout' => 'documentation'` (`custom/app/services/documentation/portal_seeder.rb:62-66`) |
| The audit that "covers" it | `lib/tasks/documentation_seo_audit.rake:67-81` calls `audit_structured_data` at `:118-129` |
| The only spec | `spec/requests/documentation/seo_spec.rb:73-89` (one fixture: category and description present) |
| Design record | `docs/product-refinement/03-documentation-seo.md` §3.3; before that phase `docs/global-documentation/FINAL-CHECKPOINT.md:26` records "no JSON-LD" |

Where there is **no** structured data: portal home (`portals/show.html+documentation.erb` has no `content_for :head`,
so `_portal_head.html.erb:16-20` prints only `<title>`), category pages (`categories/_meta_head.html.erb:1-33`),
search, 404, the classic variant (`articles/_meta_head.html.erb:1-21`) and the plain variant. The only emitter is
`documentation_layout/articles/_meta_head.html.erb` and nothing else.

## 2. Measured behaviour

### 2.1 What the code emits

Built from the helper and the `seo_spec.rb:14-27` fixture, not captured from a live page. Host is `custom_domain`, else
`HELPCENTER_URL`, else `FRONTEND_URL` (`documentation_helper.rb:29-33`, `lib/chatwoot_app.rb:35-37`).

```json
{"@context":"https://schema.org","@type":"BreadcrumbList","itemListElement":[
 {"@type":"ListItem","position":1,"name":"Lynomia Chat Documentation","item":"https://H/hc/lynomia-docs/en"},
 {"@type":"ListItem","position":2,"name":"Commerce","item":"https://H/hc/lynomia-docs/en/categories/commerce"},
 {"@type":"ListItem","position":3,"name":"Connect WooCommerce","item":"https://H/hc/lynomia-docs/articles/connect-woocommerce"}]}
{"@context":"https://schema.org","@type":"TechArticle","headline":"Connect WooCommerce","description":"…","inLanguage":"en",
 "url":"https://H/hc/lynomia-docs/articles/connect-woocommerce","datePublished":"2026-10-13T09:12:44Z",
 "dateModified":"2026-10-13T09:12:44Z","author":{"@type":"Organization","name":"Lynomia Chat Documentation"},
 "publisher":{"@type":"Organization","name":"Lynomia Chat Documentation"}}
```

Dates are `created_at&.iso8601` / `updated_at&.iso8601` (`documentation_helper.rb:90-91`); `config/application.rb` and
`config/environments/*.rb` set no `time_zone`, so Rails' UTC default gives the `Z` form above.

### 2.2 Are the values valid for the types

| Property | Source | Valid? | Note |
|---|---|---|---|
| `@context` | literal `https://schema.org` | yes | |
| `@type` TechArticle | literal | yes | schema.org subtype of `Article` |
| `headline` | `article.title` (`:86`) | yes | longest EN title is 66 chars, longest AR 56, none near 110 (checked over `custom/db/documentation/{en,ar}`) |
| `description` | `meta['description']` else `description` (`:87`) | yes; **key is dropped when both blank** by `.compact` (`:94`) | same expression as the page's meta description (`_meta_head.html.erb:9`) so they cannot disagree |
| `inLanguage` | `locale.tr('_','-')` (`portal_helper.rb:40-42`) | yes (`en`, `ar`) | |
| `url` | canonical (`:89`) | yes if the host is real, see D8 | |
| `datePublished`, `dateModified` | row timestamps | **format** valid ISO 8601; **meaning** questionable, see D1/D2 | |
| `author`, `publisher` | `Organization{name}` = `portal.display_title(locale)` | valid shape; no `url`, `logo`, `@id` | name is the portal's, not an organisation's, see D4 |
| BreadcrumbList items | `position` Integer, `name`, `item` absolute URL | yes; ≥2 items always (home + article) | last item carries `item`, which is permitted |

Absent but available in the schema: `image`, `mainEntityOfPage`, `articleSection`, `keywords`, `isPartOf`.

Injection: payload goes through `to_json` then `json_escape` (`documentation_helper.rb:97-100`), which in Rails escapes
`<`, `>`, `&`, U+2028/2029, so a `</script>` in a title cannot close the block. Correct by reading; **no spec asserts it**
(the only `</script>` spec is `search_spec.rb:131-136`, for article bodies).

### 2.3 Does the breadcrumb match the real hierarchy

URL shape is flat: article `/hc/:slug/articles/:article_slug` (`config/routes.rb:519`), category
`/hc/:slug/:locale/categories/:category_slug` (`:514`), home `/hc/:slug/:locale` (`:510`). The article address is
therefore not a path-descendant of its category, so the trail is a **taxonomy** trail, not a URL-path trail. That is
legitimate for BreadcrumbList (recalled: Google does not require breadcrumbs to mirror the URL path) and it **does**
match the page a reader sees: the visible trail (`documentation_layout/_breadcrumb.html.erb:2-31`) is Home › category
› title, with the same three hrefs the helper builds (`public_portal_locale_path`, `public_portal_category_path`,
canonical). Locale agrees: `ensure_locale_in_article` forces `article.locale = category.locale` (`app/models/article.rb:200-206`)
and the page's `@locale` is the category's (`base_controller.rb:58-62`). Two differences: crumb 1's **label** (D3), and
the trail ignores `Category#parent_category` in both the markup and the partial (consistent, but see §4).

### 2.4 Edge cases

| Case | BreadcrumbList | TechArticle | Audit |
|---|---|---|---|
| normal | home › category › article | all keys | pass |
| no `meta.description`, has `description` | unchanged | `description` taken from the column | pass |
| neither (possible via Super Admin: `description` is a free `Field::Text`, `article_dashboard.rb:18,36`) | unchanged | **`description` key absent**, block still valid | **ERROR** `rake:84-86`; also no `<meta name=description>` (`_meta_head.html.erb:27-29`) |
| no category (possible: `belongs_to :category, optional: true`, `article.rb:54`) | **2 items** (home › article): valid, meets the 2-item minimum (recalled) | unchanged; no `articleSection` exists to lose | **no finding at all** |
| blank title / blank category name | cannot happen (`article.rb:67`, `category.rb:61`) | | |
| Arabic article | same shape; crumb 1 and `author`/`publisher` fall back to the English portal name because `Portal#localized_value` falls back to the default locale (`portal.rb:154-159`) and the seeder writes no `locale_translations` (`portal_seeder.rb:8-22`) | `inLanguage: ar`, Arabic `headline` | pass |
| draft previewed by a signed-in super admin | emitted | `datePublished` from `created_at` of an unpublished row (`articles_controller.rb:80-83`) | not crawler-reachable, no impact |
| changelog entry (`lynomia-changelog` portal, same layout) | home › category › entry | **dates are row timestamps, page shows `release_date`** | pass, see D1 |

### 2.5 What the audit proves

`audit_structured_data` (`rake:118-129`) proves three things: no crumb has a blank `name`/`item`, `schema['url']` is
non-blank, and `[breadcrumb, schema].to_json` round-trips. It does not parse the dates, check `@type`, `inLanguage`,
that crumb URLs carry a host, or that the rendered `<script>` equals the hash it audited. `rake:71` checks the
canonical only with `start_with?('http')`.

## 3. Defects

No **blocker**: what ships parses, is correctly typed, leaks no staff identity (`documentation_helper.rb:80-82`), and
claims nothing the page contradicts, except D1.

| # | Sev | Defect | Evidence | Impact |
|---|---|---|---|---|
| D1 | major | **Changelog entries state a date the page does not show.** Markup and `article:published_time` use `created_at`/`updated_at`; the page shows `meta['release_date']` and suppresses "last updated" when one is set. `meta['version']` is shown but not in the markup. | `documentation_helper.rb:90-91`, `_meta_head.html.erb:42-43` vs `_header.html.erb:3,23,31`, `_release_meta.html.erb:5-6,16-19`; the one entry says `release_date: '2026-10-05'` (`custom/db/changelog/en/releases/first-release-note.md:5`) while its row was created on the seed day | For a release note the date is the content. Markup that contradicts visible text is the dishonest kind of structured data. One entry today; one more per release. |
| D2 | minor | `datePublished` is the **row creation time**, i.e. the day an operator ran the seeder, not an authored fact. It is not shown on the page (only "Last updated", `_header.html.erb:2,23-35`), so it is unverifiable by a reader. Re-creating a row (retire and re-add, restore to another environment) resets it. | `documentation_helper.rb:90`; `content_seeder.rb:73` (`find_or_initialize_by`) | Honest as "first published on this site"; fragile as a freshness signal. |
| D3 | minor | Crumb 1 **name** is `portal.display_title` ("Lynomia Chat Documentation"); the visible crumb is the i18n word "Home". On Arabic pages crumb 1 is the English portal name. Two independent builders (partial and helper) already disagree. | `documentation_helper.rb:65` vs `_breadcrumb.html.erb:8`, `config/locales/en.yml:664` | Search result shows a different trail from the page. Low risk; first symptom of drift. |
| D4 | minor | `author`/`publisher` is "Lynomia Chat Documentation", which is a site, not an organisation; no `url`, `logo` or `@id`. | `documentation_helper.rb:92-93`; asserted as intended at `seo_spec.rb:88` | Imprecise entity name. Privacy choice (never a person) is correct and should stay. |
| D5 | minor | `articleSection`, `keywords`, `mainEntityOfPage` are absent although the data already exists (category name, `meta['tags']`, canonical). `image` is absent and **there is nothing honest to put there yet**: no corpus file contains an image (`grep '!\['` over `custom/db/documentation` returns 0 files) and `og_image_url` is empty unless `OG_IMAGE_CDN_URL` is configured (`portal_helper.rb:3-9`). | | Missed context signal; not an error. |
| D6 | minor | Category pages render a visible breadcrumb (`categories/show.html+documentation.erb:7-8`) but emit no BreadcrumbList; the portal home emits no head content at all (cross-ref 073). | | Crumb 1 and crumb 2 of every article point at pages with no structured data. |
| D7 | minor | Validation is thin and untested at the edges: no helper spec; `seo_spec.rb` has no no-category, no-description, changelog or `</script>` example; the audit spec (`task_documentation_seo_audit_spec.rb`) has no structured-data example. | §2.5 | A regression in the shape would pass the audit. |
| D8 | minor | If `custom_domain`, `HELPCENTER_URL` and `FRONTEND_URL` are all unset, `portal_absolute_url` returns `https://hc/...` (evaluated the expression in isolation: `"https://".chomp('/') + "/hc/…"`). Canonical, `url`, every crumb and the sitemap are then wrong and the audit passes it (`rake:71`). `production.rb:105` already requires `FRONTEND_URL`, so this is a misconfiguration guard, not a live bug. | `documentation_helper.rb:29-33` | Matches the repo rule to fail loudly on a setup bug. |
| D9 | minor | A published article with no category is valid but gets a 2-crumb trail and no "back to category" footer (`show.html+documentation.erb:20-28`), and the audit is silent. | §2.4 | Lost topical context, invisible to the operator. |

**Checked, no defect:** JSON validity and escaping; ISO 8601 format; `position` integers; trail equals visible trail
apart from crumb 1; `headline`/`description` parity with `<title>` and `<meta name=description>`; author privacy;
graceful omission of optional keys; `dateModified` equals the visible "Last updated" for guides
(`_header.html.erb:2,23`); `increment_view_count` and position rebalancing use `update_column` (`article.rb:144-147,181,223`)
so reads and re-ordering do not bump `dateModified`; the seeder writes only when an attribute changed
(`content_seeder.rb:78`).

## 4. What a larger corpus breaks

1. **Dates.** `created_at` of hundreds of articles will cluster on a few seeder runs, and any whole-corpus editorial pass
   (a new front-matter field, a terminology fix) changes `updated_at`, hence `dateModified`, on every page without any
   substantive change. This is exactly the "freshness that isn't true" pattern. Whether dates should be authored is
   charter decision 1 (source of truth), not this report's to settle.
2. **Two breadcrumb builders.** The visible partial and the JSON-LD helper are separate code. Every IA change in Phase 3
   multiplies the chance they disagree (D3 is the first). `Category` already has `parent_category_id`
   (`category.rb` schema) and neither builder nor the seeder (`content_seeder.rb:58-63`) uses it; the charter keeps the 12
   sections flat (§8.5), so this is a latent limit, not a current bug.
3. **One type for every page kind.** `meta_for` (`content_seeder.rb:106-113`) records no page kind. The corpus will contain
   procedures, concept pages, comparison tables, a Meta error catalogue and release notes, all emitted as TechArticle. That
   is acceptable, but it means HowTo or FAQ **cannot be opted into honestly today and cannot be inferred**: step
   sections are headed `## Steps` in 24 of 63 EN files and `## What to do` in 6, and `conversations/labels.md` has a
   `## Steps` heading with no numbered list.
4. **Thin or duplicate pages, not markup, are the risk** for the templated Meta error articles. Identical, valid JSON-LD
   on 200 similar pages is fine; adding per-code types would only dress up near-duplicates (076/098).
5. **Media.** Once images arrive (stream 068), `image` becomes a legitimate property, and must list only images actually
   in the article. `meta['feature_image']` is a stored changelog field (`article_meta_field.rb:13,21,30`) that no template
   renders (grep over `app custom lib`), so there is no visible image to mark up yet.
6. **Size is not a problem.** Two ~0.8 KB blocks per page; the family query is shared with hreflang
   (`documentation_helper.rb:105-110`); the audit loads each portal's articles once (`rake:45`).

## 5. Recommendations

### 5.1 Which additional types the planned corpus justifies

Evidence from the current EN corpus (63 files): `## If it does not work` in 39, `## A worked example` in 38,
`## Steps` in 24, **zero** FAQ headings or "frequently asked" sections (the single `faq` hit is a bot-template name,
`automation/flow-builder.md:77`), four headings ending in `?` (all "A or B?" choices, e.g. `Agent bot or flow?`), zero images.
Steps sections are 4-21% of their page (largest: `getting-started/connect-your-first-channel.md` 21%,
`whatsapp/connect-whatsapp.md` 20%); four files reach 15%.

| Type | Verdict | Why, and the condition that would make it honest |
|---|---|---|
| **TechArticle** | **Keep.** Honest for guides, procedures, troubleshooting, reference and the Meta error explainers. Weakest fit: release notes and hub pages, but not misleading. | The helper's comment that the type "tells a search engine the page explains how to do something" (`documentation_helper.rb:77-79`) is not verifiable and I recall no Google feature keyed to TechArticle; treat it as honest semantics, not a ranking lever. Fix D1 for release notes. |
| **BreadcrumbList** | **Keep and extend to category pages.** Honest because a visible breadcrumb exists on both (`_breadcrumb.html.erb`). | Build the visible trail and the JSON-LD trail from one crumb list so the labels and links cannot diverge (fixes D3). |
| **HowTo** | **Not now.** At most a handful of pages (the four ≥15%) are mainly procedure; on the rest a numbered list sits inside a concept page, and marking up a section of a page as *the* HowTo misdescribes it. Steps here are one-line actions with no images. | Recalled: Google withdrew HowTo rich results in 2023, so there is no search feature to earn. Only as an explicit opt-in (`kind: how-to` in front matter, or a steps component from agent 071) and rendered from the same parsed list that produces the visible steps. Never inferred from the `## Steps` heading. |
| **FAQPage** | **No.** There is no FAQ content. "If it does not work" sections are symptom-then-fix prose, not authored question-and-answer pairs; relabelling them as `Question` entities would be fabricated structure. | Recalled: Google has limited FAQ rich results to a few authority categories since 2023. If a genuine FAQ page is ever written, render the visible Q&A and the JSON-LD from one `faq:` structure, whole-page, and expect no rich result. |
| QAPage | Never. It is for user-submitted answers; there are none. | |
| WebSite / Organization on the portal home | Optional, low value; fix the home page's empty head first (073). | |
| SoftwareApplication, Product, Review, AggregateRating, VideoObject, ImageObject, Course | No. Nothing in the corpus supports them, and ratings or view counts (`articles.views`) must never be exposed as ratings. | |
| WebSite `SearchAction` | No. Recalled: Google retired the sitelinks search box in 2024. | |

### 5.2 Fixes to what is emitted (each extends `DocumentationHelper`; no new system)

1. **Release notes (D1).** In `documentation_article_schema`, when `meta['release_date']` is present use it as
   `datePublished` and emit `version` from `meta['version']` only if present; apply the same rule to
   `article:published_time` (`_meta_head.html.erb:42`). The page already special-cases `release_date`
   (`_header.html.erb:3`). Do not add `version` to the one existing entry, which has none.
2. **Guide dates (D2).** Keep row timestamps until charter decision 1 is made. If repository Markdown becomes canonical,
   carry authored `published`/`updated` dates in front matter via `meta_for` (`content_seeder.rb:106-113`), so a bulk edit
   no longer claims freshness.
3. **One crumb source (D3, D6).** One method returns the crumb list; `_breadcrumb.html.erb` and
   `documentation_breadcrumb_schema` both consume it; add the 2-item BreadcrumbList to `categories/_meta_head.html.erb`.
4. **Entity (D4).** `author`/`publisher` name from the installation brand (`GlobalConfig` `BRAND_NAME`/`INSTALLATION_NAME`,
   already loaded at `base_controller.rb:77-79`), with a `url`; keep it an Organization, never a person.
5. **Free honest properties (D5).** `articleSection` from `article.category.name` (omit when uncategorised), `keywords`
   from `meta['tags']`, `mainEntityOfPage` from the canonical. Add `image` only with a real attached image.
6. **Make the audit prove validity (D7-D9).** Extend `audit_structured_data` (`rake:118-129`) to parse both dates, require an
   `inLanguage`, require crumb `item` URLs with a host, and **warn** on a published article with no category. Make
   `portal_absolute_url` fail when no host source is configured instead of building `https://hc/…` (D8). Add spec examples
   for the no-category, no-description, changelog and `</script>`-in-title cases (a task for a Phase 5 writer, not done here).
7. **Rule for stream 071.** Any structured component that can yield FAQ or HowTo JSON-LD must render the visible content
   and the markup from one data structure; markup with no visible counterpart is the penalty case.
8. **Meta error articles.** Use TechArticle plus honest `keywords`; putting the code itself (e.g. `131049`) in `meta['tags']`
   gives the markup and search a term at no cost (cross-ref 070, 076).

### Not checked and unverified

No page was rendered, so the §2.1 JSON is constructed from source. Not checked: the production portal's `custom_domain`
and `locale_translations` (decide whether the Arabic crumb 1 is English in production); whether `OG_IMAGE_CDN_URL` is set
there; the real `created_at` spread of the 124 production rows; the `lynomia-changelog` portal's live content beyond the
one repository file; and every Google or schema.org statement marked "recalled" or listed in the preamble. Agent 098
should confirm the Google statements against Search Central before they influence a decision.
