---
agent: 076
scope: Internal linking and related articles — the actual link graph of the corpus, and what the portal layout offers for navigation
confidence: high
---

Every number below is measured from `custom/db/documentation/{en,ar}/**/*.md` at `claude/documentation-v2`, by
parsing every Markdown link in all 126 files and resolving each target against the set of article keys. The
layout claims are read from the `+documentation` view variant that the documentation portal actually renders.

The headline is not what a discovery report usually finds. The corpus's link graph is **clean**: 988 links, zero
broken, zero external, perfect EN/AR parity. It is clean because a spec enforces it. What is broken is one layer
down — **the rendered href of every one of the 494 Arabic links points at the English article** — and what is
absent is any *derived* navigation: there is no related-articles surface, no previous/next, and the only
graph-level invariants anyone checks are the two that one spec file happens to cover.

---

## 1. What exists today

### 1.1 The link convention

Every internal cross-reference in the corpus is a **bare relative key**: `[quality rating and messaging
limits](whatsapp-quality-and-limits)`
(`custom/db/documentation/en/whatsapp-errors/whatsapp-error-131049.md:25`). The target is the Markdown file's own
basename, which `Documentation::ContentSeeder` treats as the article's stable key
(`custom/app/services/documentation/content_seeder.rb:70-73`, and the comment at `:66-69` states the intent: *"The
file name is the article's stable KEY -- what a product link in the dashboard points at"*).

There is no second convention. Measured across all 126 files:

| Link class | Count |
|---|---|
| Relative bare key | **988** |
| Absolute URL (`https://…`) | **0** |
| Root-relative path (`/…`) | **0** |
| Fragment / anchor (`#…`) | **0** |
| `mailto:` | **0** |
| Reference-style definitions (`[x]: y`) | **0** |
| Images (`![…](…)`) | **0** |
| Links in YAML front matter | **0** |

The 14 occurrences of the string `http` in the corpus are all inside code spans or prose about store addresses
(for example `en/troubleshooting/commerce-store-address-refused.md:24`), not links. **The corpus contains no
external links of any kind.** That is a notable fact for agent 085 (external links, iframes, embeds): the attack
surface in the corpus today is empty, and it will not stay empty.

### 1.2 Link validation already exists

`spec/custom/services/documentation/content_seeder_corpus_spec.rb:29-39` generates one example per file per locale
and asserts that every bare-key link resolves to a file in the same locale directory:

```ruby
targets = File.read(path).scan(%r{\]\((?!https?:|#|/)([^)\s]+)\)}).flatten.uniq
expect(targets - keys_by_locale[locale]).to be_empty
```

The header explains why it exists (`:3-7`): *"these are the invariants the seeder cannot check for itself, because
it reads one file at a time and never follows a link -- and both have been broken in practice."* The same file
also validates EN/AR key parity (`:25-27`), same-section/same-position placement (`:52-63`), and that every
`DOC_ARTICLES` slug names a real corpus file (`:77-79`).

**This spec is why the broken-link count is zero.** It is the single most valuable thing in this report's scope
and it must be extended rather than replaced.

### 1.3 What the portal layout offers

The documentation portal renders through the `+documentation` view variant
(`app/controllers/public/api/v1/portals/base_controller.rb:26-32`), laid out by
`app/views/layouts/portal.html+documentation.erb`.

| Navigation affordance | Exists? | Evidence |
|---|---|---|
| **Breadcrumbs** | **yes** | `app/views/public/api/v1/portals/documentation_layout/_breadcrumb.html.erb:1-31`; rendered on the article page at `app/views/public/api/v1/portals/articles/show.html+documentation.erb:11-12` and the category page at `categories/show.html+documentation.erb:7-8`. Trail is Home → Category → Article title (the article itself is plain text, correctly not a link, `_breadcrumb.html.erb:27-30`). |
| **Breadcrumb structured data** | **yes** | `documentation_breadcrumb_schema` emits a `BreadcrumbList` (`custom/app/helpers/documentation_helper.rb:64-75`), injected at `documentation_layout/articles/_meta_head.html.erb:64`. |
| **Category navigation (sidebar)** | **yes** | `documentation_layout/_sidebar.html.erb:1-90`, rendered on *every* documentation page from `app/views/layouts/portal.html+documentation.erb:14-15`. Collapsible `<details>` per category (`:31-61`), with every published article of the locale listed inside it (`:51-59`), the current article and category marked active (`:34,:52`). |
| **Category landing pages** | **yes** | `categories/show.html+documentation.erb:16-23` lists every article in the category as a card. Unpaginated (`app/controllers/public/api/v1/portals/categories_controller.rb:31-35`). |
| **Home → category grid** | **yes** | `show.html+documentation.erb:11-18`, plus an admin-curated "recommended" or view-count "popular" block at `:22-35` (`app/controllers/concerns/portal_home_data.rb:12-20,33-43`). |
| **Back to category** | **yes** | Article footer, `articles/show.html+documentation.erb:20-28`. |
| **On-page table of contents** | **yes** | Client-side, built from `h1/h2/h3` by `app/javascript/portal/portalHelpers.js:14-36`, mounted into `#cw-hc-toc` (`:101-113`, container at `articles/show.html+documentation.erb:31-33`). |
| **Search** | **yes** | Topbar mount point `#search-wrap` (`documentation_layout/_topbar.html.erb:33-35`). |
| **Language switcher** | **yes, but** | `_topbar.html.erb:44-69` — see Defect 2. |
| **Related articles** | **NO** | `grep -rni "related" app/views/public/api/v1/portals/ app/controllers/public/ app/helpers/portal_helper.rb custom/app/helpers/documentation_helper.rb` returns **nothing**. `ArticlesController#show` sets only `@og_image_url` and `@parsed_content` (`app/controllers/public/api/v1/portals/articles_controller.rb:24-27`). |
| **Previous / next article** | **NO** | The only `prev_page`/`next_page` in the portal views is search-result pagination (`search/index.html+documentation.erb:50-56`, `search/_results.html.erb:50-56`). Nothing sequences articles, despite `position` being a first-class seeded field (`content_seeder.rb:100`) and the sidebar already ordering by it (`_sidebar.html.erb:7`). |
| **Tag browsing / tag index** | **NO** | Tags are stored at `content_seeder.rb:110`, emitted as a `<meta name="tags">` (`documentation_layout/articles/_meta_head.html.erb:30-32`) that no crawler reads, and rendered as **non-clickable `<span>` chips** (`documentation_layout/articles/_release_meta.html.erb:22-26`). There is no route, no index and no query by tag anywhere. |
| **All-articles index page** | **NO (HTML)** | `/hc/:slug/:locale/articles` exists (`config/routes.rb:512`) but `ArticlesController#index` has no `+documentation` variant — only `articles/index.html.erb`, the classic layout. |

So the portal gives a reader **three** ways to move: the sidebar tree, the breadcrumb, and search. Every
*topical* adjacency a reader might want — "what else is about the 24-hour window" — exists only as prose the
author typed.

### 1.4 The authored "Related" convention

The corpus compensates with a hand-written convention. **57 of 63 EN articles end with a `## Related` heading**
(the heading string is exactly `## Related` 57 times; the next most common headings are `## Limits` 52,
`## Who can do this` 45, `## If it does not work` 39). The Arabic corpus mirrors it with
`## مواضيع ذات صلة` 56 times plus one variant, `## ذات صلة`, at
`custom/db/documentation/ar/workspace/your-own-help-centre.md:51`.

Of the 494 EN links, **255 sit inside a `## Related` list and 239 sit in the body.** This is a deliberate,
consistent authoring pattern — and it is invisible to the application. The seeder stores it as prose in
`articles.content`, the renderer emits it as a plain `<ul>` of `<a>` elements, and nothing can query it, validate
it, or render it as a UI block distinct from the body.

---

## 2. Measured behaviour — the actual link graph

### 2.1 Totals

| Measure | Value |
|---|---|
| Markdown files parsed | 126 (63 EN + 63 AR) |
| Distinct article keys | 63 |
| **Total internal links** | **988** (494 EN + 494 AR) |
| Distinct `(source, target)` pairs, per locale | 349 |
| Duplicate link instances (same target linked ≥2× in one file) | 145 per locale, **290** in all |
| Broken internal links | **0** |
| Links to an absolute production URL | **0** |
| Self-links | **0** |
| EN/AR outbound multiset mismatches | **0** |
| EN/AR outbound *order* mismatches | **0** |

The EN/AR parity result is worth stating plainly: for all 63 articles, the Arabic file links to the same targets,
the same number of times, **in the same order** as the English file. The Arabic corpus is a true translation at
the link level, not an approximation.

### 2.2 Links per article (outbound, EN; AR is identical)

| Outbound links | Articles |
|---|---|
| 0 | 5 |
| 3 | 5 |
| 4 | 5 |
| 5 | 2 |
| 6 | 6 |
| 7 | 6 |
| 8 | 8 |
| 9 | 6 |
| 10 | 6 |
| 11 | 6 |
| 12 | 4 |
| 13 | 1 |
| 17 | 1 |
| 22 | 1 |
| 27 | 1 |

min 0, max 27, mean 7.8, median 8. The 27 is `whatsapp-errors/whatsapp-nothing-arrives`-class hub prose; the
long tail at 17–27 is three articles that behave as hubs without being labelled as such.

Authored `## Related` list lengths, EN: 3 links ×12 articles, 4 ×18, 5 ×18, 6 ×8, 9 ×1, and 6 articles with no
list. **The convention in practice is 3–6 related links.**

### 2.3 Inbound links (unique linking sources, EN)

| Unique inbound sources | Articles |
|---|---|
| 0 | **6** |
| 1 | 7 |
| 2 | 10 |
| 3 | 6 |
| 4 | 7 |
| 5 | 7 |
| 6 | 1 |
| 7 | 3 |
| 8 | 2 |
| 9 | 3 |
| 10 | 1 |
| 11 | 2 |
| 12 | 1 |
| 13 | 2 |
| 16 | 1 |
| 19 | 1 |
| 21 | 2 |
| 24 | 1 |

min 0, max 24, mean 5.5, median 4.

The most-linked articles are the ones a support corpus would expect, which is a sign the authoring is sound:

| In | Out | Article |
|---|---|---|
| 24 | 4 | `workspace/roles-and-permissions` |
| 21 | 5 | `whatsapp/the-whatsapp-24-hour-window` |
| 21 | 8 | `audiences-and-campaigns/whatsapp-campaigns` |
| 19 | 9 | `automation/automation-rules` |
| 16 | 19 | `whatsapp/whatsapp-troubleshooting` |
| 13 | 9 | `commerce/commerce-overview` |
| 13 | 8 | `audiences-and-campaigns/shared-audiences` |

### 2.4 Articles with zero inbound internal links

**Six, all of them explicable and five of them wrong.**

| Article | Out | Why it matters |
|---|---|---|
| `getting-started/welcome-to-lynomia-chat` | 7 | The corpus root, and the `gettingStarted` registry key (`documentationLinks.js:13`). Zero inbound is defensible for a root — but it is reachable only via the sidebar and the home grid, never from inside an article. |
| `troubleshooting/contact-lynomia-support` | 8 | **Defect.** The escalation page. 8 outbound links, 0 inbound. Nothing anywhere in the corpus tells a reader who has exhausted an article how to reach support, even though the registry carries `contactLynomiaSupport` (`documentationLinks.js:93`). |
| `troubleshooting/commerce-keys-cannot-do-that` | 0 | **Isolated.** |
| `troubleshooting/commerce-order-action-did-not-apply` | 0 | **Isolated.** |
| `troubleshooting/commerce-store-address-refused` | 0 | **Isolated.** |
| `troubleshooting/commerce-store-needs-reconnecting` | 0 | **Isolated.** |

### 2.5 Articles with zero outbound links

**Five** — the four isolated commerce articles above plus `troubleshooting/commerce-store-unreachable` (which has
exactly 1 inbound, from `contact-lynomia-support.md:81,116`).

These five are the only articles in the corpus with no `## Related` heading other than
`welcome-to-lynomia-chat`, and they are the only five that are dead ends.

They are **not** unreachable from the product: all five are `DOC_ARTICLES` entries
(`documentationLinks.js:74-78`) and `commerceErrorArticle()` maps 19 `Commerce::Error` codes onto them
(`documentationLinks.js:108-134`). A user reaches them by clicking an error in the UI. But once there, the
corpus is a cul-de-sac: no related links, no onward path, and no inbound path to find them by browsing.

The sharpest version of this: **`troubleshooting/troubleshooting` — the one article whose job is to be the
troubleshooting index — links to 16 articles and not one of the five commerce troubleshooting articles that sit
in its own section.** Its `## Related` list names `whatsapp-troubleshooting`, `roles-and-permissions`,
`set-up-an-inbox`, `audit-logs`, `webhooks`, `whatsapp-campaigns`, `automation-rules`, `flow-builder` and
`commerce-provider-support`.

### 2.6 Graph shape

- **Weakly connected components: 5.** One component of 59 articles, and four singletons (the four isolated
  commerce articles). `commerce-store-unreachable` joins the main component through its single inbound edge.
- **Reachability from `welcome-to-lynomia-chat` by following links only: 57 of 63.** Depth histogram:
  1 article at depth 0, 7 at 1, 21 at 2, 26 at 3, 2 at 4. **Maximum click depth 4** — good, and it will not
  survive the expansion (§4).
- Unreachable by link-following: the five commerce troubleshooting articles and `contact-lynomia-support`.
- **Intra-section edges 203, cross-section edges 291.** The corpus links across sections more than within them,
  which is the right instinct for a support corpus and the reason the sidebar (which is strictly intra-section)
  cannot substitute for related articles.

Section-to-section edge counts show where the density is: `whatsapp-errors → whatsapp-errors` 44,
`whatsapp-errors → whatsapp` 31, `whatsapp → whatsapp` 31, `commerce → commerce` 33, `conversations →
conversations` 23, `contacts → contacts` 19, `automation → automation` 17. `administration` (1 article) emits 11
edges and receives 4. `integrations` emits 26 and receives 1.

### 2.7 Anchor text

32 of the 57 linked-to articles are reached by **more than one** distinct anchor text. 103 distinct normalized
anchor texts point at 57 targets — mean 1.81 per target. Worst cases:

| Target | Anchor texts used |
|---|---|
| `import-contacts` | "import contacts", "import", "imports", "importing them yourself" |
| `whatsapp-campaigns` | "whatsapp campaigns", "whatsapp campaign", "campaign", "campaigns" |
| `whatsapp-quality-and-limits` | "quality rating and messaging limits", "quality and limits", "quality rating", "messaging limits" |
| `commerce-overview` | "what connecting a store gives you", "commerce", "connect your store" |
| `whatsapp-error-131049` | "error 131049", "131049", "131049 — refused for this one person" |

Varied inline anchor text in prose is *correct* — "a narrower [audience](shared-audiences)" reads better than
the article title. The problem is that the `## Related` lists also vary, and those are the links a crawler and a
reader treat as a navigation label. This is a Phase 5 authoring rule, not a code defect.

### 2.8 Cross-locale link errors

This is the serious finding and it needs the render path spelled out.

The public article URL carries **no locale segment**: `get 'hc/:slug/articles/:article_slug'`
(`config/routes.rb:519`). The seeder gives the Arabic sibling a suffixed slug:

```ruby
def slug_for(key, locale)
  locale == Documentation::Library::DEFAULT_LOCALE ? key : "#{key}-#{locale}"
end
```
(`custom/app/services/documentation/content_seeder.rb:85-87`)

The renderer emits the Markdown href **verbatim**. `MarkdownRendererUrlSanitizer#link` writes
`out('<a href="', sanitized_href(node.url), '"')` (`lib/markdown_renderer_url_sanitizer.rb:6-10`), and
`sanitized_href` only rejects `javascript:`/`vbscript:`/`file:`/`data:` and percent-escapes
(`:14-19`). `CustomMarkdownRenderer#link` falls through to that `super` for any non-embed link
(`lib/custom_markdown_renderer.rb:54-59`). No `<base>` element exists in any portal layout
(`grep -rn "<base" app/views/layouts/ app/views/public/` → nothing), and the portal JavaScript only sets
`target="_blank"` on off-host links — it never rewrites an `href`
(`app/javascript/portal/portalHelpers.js:38-60`).

Therefore, for the Arabic article at `/hc/lynomia-docs/articles/whatsapp-error-131049-ar`, the link at
`ar/whatsapp-errors/whatsapp-error-131049.md:25` is emitted as
`<a href="whatsapp-quality-and-limits">` and the browser resolves it against the directory
`/hc/lynomia-docs/articles/` to:

```
/hc/lynomia-docs/articles/whatsapp-quality-and-limits     ← the ENGLISH article
```

**All 494 Arabic internal links render to the English article.** An Arabic reader who follows any
cross-reference in any article leaves Arabic and cannot get back except through the language switcher, which
goes to the home page (Defect 2). The 494 English links are correct, because for the default locale
`slug == key`.

The corpus spec does not catch this, because it validates keys against the locale's *file* set
(`content_seeder_corpus_spec.rb:36`) — which passes — not rendered hrefs against the locale's *slug* set.

There is a second, related locale failure on the product's own entry point. `/docs/:article_slug` has no locale
in its route (`config/routes/documentation.rb:25-26`), so `DocumentationController#article` calls
`Documentation::Library.article_for(params[:article_slug], locale: params[:locale])` with `params[:locale]` nil
(`custom/app/controllers/documentation_controller.rb:22`), and `article_for` then falls to
`by_key.find_by(locale: DEFAULT_LOCALE)` (`custom/app/services/documentation/library.rb:56`). **Every contextual
help link from the dashboard lands on the English article**, whatever language the agent is working in, unless a
caller appends `?locale=ar` — and `documentationArticleUrl` does not
(`app/javascript/dashboard/helper/documentationLinks.js:102-107`: `return ${base}/${slug}`).

### 2.9 Registry ↔ corpus coverage

Measured from `documentationLinks.js`: **62** `DOC_ARTICLES` entries, 62 distinct slugs, each pointing at a real
corpus key. One corpus key is not in the registry: `workspace/your-own-help-centre`.

Note for the orchestrator: `docs/documentation-v2/01-current-system.md` §7 states *"`DOC_ARTICLES` — 87 keys"*.
The measured count is **62** (plus 19 `COMMERCE_ERROR_ARTICLES` mappings onto 5 of those keys, which is 81
`key: 'value'` lines in the file in total). The 87 figure does not reconcile with the file.

### 2.10 Key / category-slug collisions

Three article keys are also category slugs: `contacts`, `integrations`, `troubleshooting`. All three are link
targets. Nothing breaks today, because the URL namespaces differ (`/articles/:slug` versus
`/:locale/categories/:category_slug`), but any future convention that lets a link point at a category will have
to disambiguate.

### 2.11 Tag vocabulary (the input a "derive related from tags" design would use)

Every EN article has 1–3 tags: 20 articles have 1, 24 have 2, 19 have 3. 32 distinct tags, 125 applications.

| Count | Tag |
|---|---|
| 22 | `whatsapp` |
| 14 | `errors` |
| 12 | `commerce` |
| 10 | `contacts` |
| 8 | `troubleshooting` |
| 7 | `conversations` |
| 6 | `getting-started` |
| 5 | `automation`, `workspace`, `connection` |
| 3 | `audiences`, `inboxes`, `inbox` |
| 2 | `campaigns`, `integrations`, `templates` |
| 1 | `administration`, `audit`, `labels`, `salla`, `shopify`, `woocommerce`, `zid`, `webhooks`, `billing`, `delivery`, `attachments`, `quality`, `roles`, `teams`, `documentation`, `support` |

Three facts decide §5's recommendation:

1. **No controlled vocabulary.** `inbox` (3) and `inboxes` (3) coexist. `audiences` (3) sits beside the article
   key `shared-audiences`. There is no enum, no validation, no list — `content_seeder.rb:110` is
   `Array(front_matter['tags'])` and `custom/app/fields/article_meta_field.rb:43` splits a free-text input on
   commas.
2. **16 of 32 tags are singletons.** A tag used once can never identify a sibling.
3. **The top tag covers 35% of the corpus.** `whatsapp` on 22 of 63 articles cannot pick 5 related articles; it
   picks 21 candidates with no ranking signal.

---

## 3. Defects

### Defect 1 — every Arabic internal link renders to the English article · **blocker**

494 of 988 links. Evidence: `content_seeder.rb:85-87` (slug suffix), `config/routes.rb:519` (no locale segment),
`lib/markdown_renderer_url_sanitizer.rb:6-19` (href emitted verbatim), no `<base>` in any layout, no JS href
rewrite (`portalHelpers.js:38-60`).

Impact: the Arabic corpus is navigationally unusable. A reader is ejected to English on the first
cross-reference. Half the corpus's authoring effort — and the perfect link parity of §2.1 — delivers nothing to
the reader it was written for. For a crawler, every Arabic page links only to English pages, which is a strong
signal that the Arabic pages are thin satellites of the English ones. Agent 073 should be told: this directly
undercuts the hreflang work at `documentation_layout/articles/_meta_head.html.erb:19-24`, which correctly
declares the Arabic article as an alternate while the page body links away from Arabic entirely.

### Defect 2 — the language switcher discards the reader's place · **major**

`documentation_layout/_topbar.html.erb:57` emits `href="/hc/<%= portal.slug %>/<%= code %>/"` for every locale.
From an article it goes to the locale home page, not to the translated article — even though
`article.associated_article_id` is exactly that link (`content_seeder.rb:77,90-92`) and
`portal_locale_alternates` already computes the sibling URLs for the `<head>`
(`documentation_layout/articles/_meta_head.html.erb:19-21`). Combined with Defect 1, there is no path at all from
an Arabic article to another Arabic article.

### Defect 3 — four articles are graph singletons, five are dead ends, and the troubleshooting hub ignores its own section · **major**

`commerce-keys-cannot-do-that`, `commerce-order-action-did-not-apply`, `commerce-store-address-refused`,
`commerce-store-needs-reconnecting` have 0 in and 0 out. `commerce-store-unreachable` has 0 out.
`troubleshooting/troubleshooting`'s `## Related` list names nine articles, none of them these five.

Impact: a user who arrives from a commerce error banner has no onward path, and a user browsing cannot find
these pages at all. These are the articles most likely to be reached by a frustrated user, and they are the
least connected.

### Defect 4 — nothing in the corpus links to support · **major**

`troubleshooting/contact-lynomia-support` has 0 inbound links. 57 articles end in a `## Related` list; none of
them offers "if this did not help, contact support", despite 39 articles carrying an `## If it does not work`
heading. `documentationLinks.js:93` carries the registry key, so the product can link there; the corpus cannot.

### Defect 5 — the authored `## Related` convention is prose, not data · **major**

255 EN links sit under a heading the application cannot see. Consequences, each concrete:

- It cannot be rendered as a UI block. The reader sees a bulleted list indistinguishable from body prose.
- It cannot be validated for reciprocity, length, or locale-correctness.
- It cannot be queried. "Which articles relate to the 24-hour window?" requires grepping Markdown.
- 6 of 63 articles have no list and nothing notices.
- The heading itself has already drifted: `ar/workspace/your-own-help-centre.md:51` says `## ذات صلة` where the
  other 56 Arabic files say `## مواضيع ذات صلة`.
- 124 article-target pairs appear in **both** the body and the `## Related` list of the same article (and 290
  duplicate link instances exist overall). That is fine as prose and wasteful as data.

### Defect 6 — no graph-level invariant is checked anywhere · **major at scale**

`content_seeder_corpus_spec.rb` validates each file in isolation: *"it reads one file at a time and never follows
a link"* is true of the seeder and nearly true of the spec. Nothing checks:

- orphans (zero inbound) — 6 exist,
- dead ends (zero outbound) — 5 exist,
- connectivity — 5 components exist,
- click depth from a root,
- reciprocity of a `## Related` pair,
- `## Related` list presence or length,
- inbound-link concentration.

`rake lynomia:docs:seo_audit` does not look at links either: its checks are canonical collisions, canonical host,
title, description, hreflang reciprocity, hreflang `x-default`, duplicate hreflang locales and structured-data
build (`lib/tasks/documentation_seo_audit.rake`, and the table in `01-current-system.md` §8). Internal linking is
the one SEO axis with no audit.

### Defect 7 — no related articles, no previous/next · **major**

Established in §1.3. Nothing in `ArticlesController#show`
(`app/controllers/public/api/v1/portals/articles_controller.rb:24-27`) or any `+documentation` view loads an
adjacent or similar article. `position` is seeded, ordered by the sidebar, and never used to sequence.

### Defect 8 — the corpus spec's exclusions become blind spots the moment an author uses them · **minor today**

`content_seeder_corpus_spec.rb:34` deliberately skips `https?:`, `#` and `/` targets: *"A URL, an anchor or a
path is somebody else's to validate."* Nobody validates them, and today nobody needs to — there are zero of
each. The first external link, the first `#section` anchor and the first `/docs/...` path all enter unchecked.

### Defect 9 — the sidebar loads the whole corpus, with bodies, on every page · **minor today, blocker at scale**

`documentation_layout/_sidebar.html.erb:8-11`:

```erb
sidebar_articles_by_category = order_articles.call(
  portal.articles.published.where(category_id: sidebar_categories.map(&:id))
).group_by(&:category_id)
```

No `select`, no limit. `articles.content` is a `text` column (`db/schema.rb:209`), so this materialises every
published article of the locale including its full body on every documentation page render. The EN corpus is
346 KB of Markdown across 63 files — roughly 5.5 KB per article. See §4.

### Defect 10 — `<meta name="tags">` is dead weight · **minor**

`documentation_layout/articles/_meta_head.html.erb:30-32` and `articles/_meta_head.html.erb:13-14` emit
`<meta name="tags">`. No search engine consumes it. The tag data is real and useful; this is not the surface
that makes it useful.

---

## 4. What a larger corpus breaks

The corpus is 63 keys. Phase 5 is to take it "substantially broader" (charter §9). Assume 400–700 keys and
the following stop working.

**Click depth collapses into search-only navigation.** Today every article is within 4 clicks of the root and
mean inbound degree is 5.5. Hold the authored convention at 3–6 related links per article and grow the node
count 8×: mean inbound degree stays ~5.5 only if authors distribute links evenly, which they will not — the
current graph already concentrates 24 inbound links on `roles-and-permissions` and gives 0 to six articles. At
600 articles, the orphan *rate* is what matters. At the current rate (6/63 ≈ 9.5%) that is **~57 orphaned
articles**, each invisible to browsing. The authored convention does not scale by itself because an author
writing article 400 cannot know which of the existing 399 should now link *to* it. **Inbound degree is the
metric that breaks, and no current process measures it.**

**The sidebar becomes the page.** At 600 articles per locale, `_sidebar.html.erb:8-11` loads ~600 full article
rows (~3.3 MB of `content`) per request and renders ~600 `<a>` elements plus ~30 category groups into every
page — including the article page, where it is chrome. Every documentation page then carries 600 outbound
internal links, which flattens internal link signal to nothing and is a Core Web Vitals problem for agent 080.
The `<details>` collapse hides it visually; it is still in the DOM and still in the query.

**Unpaginated category pages become unusable.** `categories_controller.rb:31-35` loads and
`categories/show.html+documentation.erb:16-23` renders every article in a category as a card. `whatsapp-errors`
has 14 today. A Meta error taxonomy of the size agents 001–028 are mapping puts dozens to low hundreds into one
category with no paging and no sub-grouping.

**Breadcrumbs stay 3 deep while the taxonomy wants to be 4.** `_breadcrumb.html.erb` and
`documentation_breadcrumb_schema` (`custom/app/helpers/documentation_helper.rb:64-75`) both hard-code
Home → Category → Article. The Help Center model has a `folder_id` column (`db/schema.rb:206`) that nothing
in the documentation path uses. If `whatsapp-errors` needs sub-grouping, there is no crumb for it.

**The per-file corpus spec becomes 1,200+ examples that still miss the graph.** One RSpec example per file per
locale (`content_seeder_corpus_spec.rb:30-38`) is 126 examples now and ~1,400 at 700 keys — and it will still
pass on a corpus with 57 orphans, because orphanhood is not a property of any single file.

**The absolute-URL temptation arrives.** Zero absolute production URLs exist today, and that is the single most
valuable property of this corpus for the expansion. With dozens of writers across ten streams in separate
worktrees, someone will paste `https://docs.lynomia.com/...` from a browser. Nothing currently rejects it: the
corpus spec's regex explicitly excludes `https?:` targets from validation (`:34`).

**Cross-locale breakage multiplies silently.** Defect 1 is 494 links today. At 700 keys it is ~5,500 Arabic links
every one of which lands in English, and the hreflang/sitemap machinery
(`app/views/public/api/v1/portals/sitemap.xml.erb:14-25`) keeps declaring the Arabic pages as first-class
alternates.

---

## 5. Recommendations

Each extends something that exists. None adds a table, an engine, or a second content model.

### R1 — Rewrite internal link targets per locale at seed time. **Blocker; do this first.**

`Documentation::ContentSeeder` already owns the key→slug mapping for every locale, in one method
(`content_seeder.rb:85-87`). Make `attributes_for` pass the body through a rewrite that maps each bare-key link
target through `slug_for(key, locale)` before assigning `content` (`content_seeder.rb:94-104`), and **raise on a
key the corpus does not carry**.

Why here and not elsewhere:
- It is the earliest shared entry point. Every article in every locale passes through `upsert_article`.
- The corpus stays locale-agnostic and keyed. A writer never types `-ar`, never types a portal slug, never
  types a URL. The `DOC_ARTICLES` contract (`01-current-system.md` §10) is untouched.
- Raising makes zero-broken-links an **invariant of the seed**, not a property the corpus spec happens to
  enforce. A renamed or deleted file then fails the sync loudly, which is exactly what the charter asks for
  ("let it fail loudly instead of silently skipping behavior") and exactly the failure mode `01-current-system.md`
  §9.3 flags: the seeder deletes nothing, so a renamed key currently leaves an orphan *and* breaks every link to
  it.
- It does not change the English output at all (`slug_for('x','en') == 'x'`), so the risk is confined to the
  locale that is already broken.

Pair it with R2 so the raise is caught in CI rather than at deploy time.

### R2 — Extend `content_seeder_corpus_spec.rb` from per-file checks to graph checks.

The file already exists, already enumerates the corpus, already enforces the two invariants that matter most,
and already reads `documentationLinks.js` as text. Add, as examples over the whole key set:

| Invariant | Threshold |
|---|---|
| Every key has ≥1 inbound link | hard fail, with a named allowlist for the corpus root |
| Every key has ≥1 outbound link | hard fail |
| The link graph is one weakly connected component | hard fail |
| Every key is reachable from the root within N clicks | start at N=4, raise with evidence |
| Every article has a `## Related` list of 3–6 links | hard fail; the measured convention is already 3–6 |
| No `https?:` target points at this installation's own documentation host | hard fail — this is the absolute-URL gate |
| Anchors (`#…`) resolve to a heading in the target article | hard fail once anchors are used |
| EN and AR outbound link multisets are equal | hard fail; currently passes for all 63 |

The last one is free: it passes today, and it locks in the parity that §2.1 measured.

Put these in the spec, not in `lynomia:docs:seo_audit`. The audit deliberately inspects *data on a server*
(`documentation_seo_audit.rake:1-11`); the link graph is a property of *the files*, checkable in CI before merge,
where a Phase 5 writer gets the failure in their own worktree. This also answers the charter §8.2 question for
this one axis: **internal-link validation is a CI gate, not a deploy gate.**

### R3 — Make `## Related` a structured front-matter field, and render it as a real block.

Add `related: [key, key, …]` to the front matter that `content_seeder.rb:126-131` already parses, store it in
`meta` alongside `tags` (`content_seeder.rb:106-113` — `meta` is `jsonb` and already carries arrays), and render
it from a new `documentation_layout/articles/_related.html.erb` after the body in
`articles/show.html+documentation.erb`, using the existing `documentation_layout/_article_card.html.erb`.

This is the smallest change that fixes Defects 5 and 7 together:
- The `## Related` prose lists are **deleted from the body** and become data. 255 EN + 252 AR links move from
  prose to `meta`, and the 124 body/Related duplicate pairs collapse.
- The rendered links go through a Rails path helper, so **they are locale-correct by construction** — no
  rewrite needed for this half of the graph.
- The block is validatable (R2), queryable, and reciprocity-checkable.
- The in-body inline links stay exactly as they are. They are good writing and R1 fixes their locale.
- The Arabic heading drift (`## ذات صلة`) disappears along with the heading.

### R4 — Answer the actual question: authored, tag-derived, or category-derived?

**Authored, as a validated front-matter field (R3), with a category-derived fallback and a measured
inbound-degree floor. Not tag-derived.**

**Not tag-derived**, on the evidence of §2.11: no controlled vocabulary (`inbox` and `inboxes` both in use), 16
of 32 tags are singletons and can never find a sibling, and the top tag covers 35% of the corpus so it returns
21 undifferentiated candidates. Making tags work for this would require inventing a controlled taxonomy,
retagging 126 files, and building a ranking function — which is the "new engine" the charter forbids, to
reproduce something 57 articles already do better by hand. Tags should be fixed and put to work on **search
facets and synonyms** (agents 077, 078), which is what a 1–3-tag-per-article vocabulary is actually shaped for.

**Not category-derived as the primary**, because the sidebar already *is* category-derived navigation
(`_sidebar.html.erb:31-61`) and it renders on every page. A related block that shows category siblings shows the
reader what is already in their peripheral vision. The measurement that settles it: **cross-section edges (291)
outnumber intra-section edges (203)**. The authored relationships in this corpus are predominantly the ones a
category cannot express — `whatsapp-error-131049` → `shared-audiences` → `whatsapp-campaigns` →
`roles-and-permissions` is a user's journey across four sections, and it is the whole value of the `## Related`
lists.

**Authored, because the evidence says authoring already works here.** 57 of 63 articles carry a 3–6 link list;
EN/AR parity is exact in set *and* order; the top-inbound articles are the genuinely central ones. The corpus
does not have a related-articles quality problem. It has a related-articles *plumbing* problem.

**With a category-derived fallback**, for the one case authoring cannot cover: an article nobody has linked to
yet. Render category siblings ordered by `position` when `meta['related']` is absent, so a new article is never
a dead end on day one. This is also the honest answer to the 400-article scale problem — the fallback is a
floor, not the design.

**And with an inbound-degree floor enforced in CI (R2), because that is the half of the graph an author cannot
see.** A writer controls their outbound links and nothing else. Orphanhood is created by everyone *else's*
omissions. The only durable mechanism at several hundred articles is a check that fails the build when a key has
no inbound edge, which forces the writer who adds article 400 to also add the one inbound link that makes it
findable.

### R5 — Add previous/next from `position`, within the category.

`position` is seeded (`content_seeder.rb:100`), validated for cross-locale consistency
(`content_seeder_corpus_spec.rb:52-63`), and already the sidebar's sort key (`_sidebar.html.erb:7`). Two
sibling lookups in `ArticlesController#show` and a footer partial beside the existing "back to category" link
(`articles/show.html+documentation.erb:20-28`) give every article two guaranteed outbound links and two
guaranteed inbound links. At 600 articles this alone makes a zero-inbound article structurally impossible inside
a category, and it costs one query.

### R6 — Fix the language switcher to carry the reader's place.

`_topbar.html.erb:57` should resolve the sibling for `article`/`category` rather than always linking the locale
home. `portal_locale_alternates(portal, article)` already returns exactly that map and is already called in the
same page's `<head>` (`documentation_layout/articles/_meta_head.html.erb:19-21`). Reuse it; fall back to the
locale home when no published sibling exists. Without this, R1 fixes Arabic→Arabic links but an Arabic reader who
arrives on an English page still cannot cross over.

### R7 — Give the five commerce troubleshooting articles and `contact-lynomia-support` their edges.

Phase 5 content work, not code: add the five to `troubleshooting/troubleshooting`'s related set and to
`commerce/commerce-overview`; give each of the five a related set; and make `contact-lynomia-support` the
standard last entry under the 39 `## If it does not work` headings. R2's orphan and dead-end checks then keep it
that way. Owner: whoever takes `commerce` (agent 056) and `troubleshooting` (agent 060) in Phase 5 — this is a
cross-cutting fix and needs one owner, not two.

### R8 — Bound the sidebar before the corpus grows.

Narrow `_sidebar.html.erb:8-11` to the columns the partial uses (`id, title, slug, category_id, position`) — it
reads `title` and `slug` only — and render only the current category's articles expanded, with other categories
as links to their landing page. This is the difference between a 3 MB query per page view and a 60 KB one at 600
articles, and it keeps per-page outbound internal links in the dozens rather than the hundreds. Agent 080 owns
the CWV consequence; the navigation consequence is that internal link signal survives.

### R9 — Settle the locale on `/docs/:article_slug`.

`DocumentationController#article` reads `params[:locale]` (`custom/app/controllers/documentation_controller.rb:22`)
and the route never supplies one (`config/routes/documentation.rb:25-26`), so every contextual-help click lands
in English. Either `documentationArticleUrl` appends the dashboard's UI locale
(`documentationLinks.js:102-107`) or the controller reads `Accept-Language`. This is agent 073's and 077's
territory as much as mine; flagging it because it is the same class of bug as Defect 1 and the two should be
decided together.

---

## 6. Priority

| # | Recommendation | Severity | Phase |
|---|---|---|---|
| R1 | Locale-rewrite link targets in the seeder, raise on unknown key | blocker | 5, stream owning the seeder |
| R2 | Graph invariants in `content_seeder_corpus_spec.rb` (CI gate) | blocker | 5, early — it gates everything else |
| R3 | `related:` front matter + rendered related block | major | 5 |
| R4 | Authored + category fallback + inbound floor (the decision) | — | **freeze in Phase 4** |
| R6 | Language switcher carries the reader's place | major | 5 |
| R5 | Previous/next from `position` | major | 5 |
| R7 | Connect the 6 orphans / 5 dead ends | major | 5, content |
| R8 | Bound the sidebar query and render | minor now, blocker at scale | 5 |
| R9 | Locale on `/docs/:article_slug` | major | 4 decision, 5 fix |

Not checked: whether a staging render of an Arabic article actually produces the href in §2.8 — the conclusion is
read from the route, the seeder's `slug_for`, the renderer's `link`, the absence of a `<base>` element and the
absence of JS href rewriting, which is every layer in the path, but no page was rendered. A one-line request spec
asserting the emitted `href` on an Arabic article would convert this from "read from four files" to "observed",
and it belongs in R2 anyway.
