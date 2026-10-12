# Documentation SEO

Product Refinement, workstream C. Branch `claude/product-refinement`.

The public documentation is the product's public face: it is what a prospect finds before they find the
product. This completes it as an indexable, multilingual site rather than a set of pages that happen to be
reachable.

## 1. What was already right

Worth stating, because it is what the rest builds on:

- **One stable address per article.** `/docs/:article_slug` and the Help Center's
  `/hc/:slug/articles/:article_slug` carry no database id and no locale segment, so a link survives a reseed
  and a portal slug change.
- **A canonical tag**, built from the portal's own custom domain or the installation's help-centre root — the
  same way the sitemap built its entries, which is why the two agreed.
- **A sitemap** of published articles with `lastmod`.
- **`og:title`, `og:description`, `twitter:card` and `og:image`** on articles.
- **Locale is modelled in the data**, not guessed: an article's locale follows its category's
  (`Article#ensure_locale_in_article`), and translations hang off the default-locale article through
  `associated_article_id`, which the content seeder writes.

## 2. What was missing or wrong

| gap | consequence |
|---|---|
| no `hreflang`, no `x-default` | the English and Arabic versions of a page competed with each other instead of being understood as one page in two languages |
| `<meta name="og:image">` emitted **alongside** `<meta property="og:image">` | the `name` form is read by nothing. A tag that does nothing sitting next to the one that works |
| no `twitter:title`, no `twitter:description` | a crawler reading `twitter:*` does not fall back to `og:*` for every field, so the card had an image and no text |
| no `og:type`, `og:url`, `og:site_name` | a share had no stated page type and no canonical URL of its own |
| no structured data at all | a search result showed a bare URL rather than a breadcrumb trail, and nothing said these pages are technical documentation |
| category pages had **no canonical**, and no `og:title` despite having `name="title"` | a list page with a query string was a separate URL as far as a crawler was concerned |
| sitemap had no locale alternates | same problem as the missing `hreflang`, in the other place a crawler looks |
| `robots.txt` was `Disallow: /widget` and nothing else | no sitemap hint, and the dashboard, Super Admin and API were all crawlable (a crawler indexing a sign-in page) |

## 3. What was built

### 3.1 Every address from one place

`DocumentationHelper` builds them all the same way — the portal's own custom domain if it has one, else the
installation's help-centre root. The canonical, the locale alternates, the Open Graph URL, the structured data
and the sitemap entries all come from it, so **they cannot disagree with each other.** That is the whole reason
they are in one helper rather than one expression per view.

### 3.2 hreflang, from the data rather than from a convention

`portal_locale_alternates` reads the translation family through `associated_article_id` — the association the
Help Center already uses and the content seeder already writes. **Nothing guesses a sibling slug from a naming
convention**: a guessed `hreflang` that 404s is worse than none, because a crawler treats it as a soft-404
rather than ignoring it.

Three rules:

1. **Published siblings only.** Announcing a draft translation earns a soft-404.
2. **The set includes the article itself**, which is what the specification requires and what makes the set
   reciprocal by construction rather than by two pages agreeing.
3. **`x-default` names the portal's default locale**, and is emitted only when there is more than one language
   — with one language there is nothing to default to, and an `hreflang` set of one is noise.

The same set goes into the sitemap as `xhtml:link` alternates, from the same helper.

### 3.3 Structured data

Two blocks per article, both from records the page is already rendering, so neither costs a query:

- **BreadcrumbList** — portal → category → article, so a search result reads
  "Documentation › Commerce › Connect WooCommerce" instead of a bare URL.
- **TechArticle** — not `Article`. The more specific type is what tells a search engine the page explains how
  to do something rather than reporting news.

`author` and `publisher` are the **portal**, never the agent who wrote the article. A documentation page is
published by Lynomia, and putting a staff member's name into public structured data would publish an employee's
identity to the whole internet for no reader's benefit. A spec asserts that.

Both are injected through `json_escape`, so a `</script>` inside a title cannot break out of the block.

### 3.4 Category pages are lists, and say so

`og:type: website`, a canonical of their own, their own `og:title`, and **no** `article:published_time` — a
list has no publication date of its own, and deriving one from the newest article in it would be a number
nobody stated.

### 3.5 Deliberately not emitted: `og:locale`

Open Graph's `og:locale` wants `language_TERRITORY`. Lynomia's portal locales are language-only (`en`, `ar`),
and turning `en` into `en_US` would be asserting that an installation serving English serves *American*
English, which it never said. `hreflang` accepts language-only and is the mechanism that actually governs
multilingual search, so that is where the language is stated. Recorded as a decision rather than left as an
oversight.

### 3.6 robots.txt

Only the public documentation is worth crawling. Everything else either creates data when it loads, needs a
session, or duplicates a page already listed:

| rule | reason |
|---|---|
| `Disallow: /widget` | a widget load **creates a contact** before it renders. Crawling it manufactures contacts |
| `Disallow: /app/`, `/super_admin/`, `/installation/` | behind a session; a crawler gets a sign-in page and indexes that |
| `Disallow: /api/` | JSON, not a page |
| `Disallow: /hc/*?theme=` | the same article again with a query string; the page's canonical already points at the clean address |
| `Sitemap:` per portal | at the portal's **own** host, because a portal with a custom domain serves its sitemap there |

The sitemap lines are read from the portals that exist, and a database that is missing or migrating yields the
rules without the hint rather than a 500 — `robots.txt` is served before anything else on a cold boot.

## 4. The validator

`bundle exec rake lynomia:docs:seo_audit` (optionally `PORTAL_SLUG=…`). Read-only; exits **1** on an error so
it can gate a deploy, while warnings do not fail it.

A template spec asserts the page emits a canonical tag. This asserts that **this installation's content**, as
seeded and edited, produces addresses a crawler can use:

| check | level |
|---|---|
| two articles claiming one canonical | error |
| canonical with no host | error |
| no title | error |
| no meta description **and** no description | error |
| `hreflang` set that does not include the article itself | error |
| `hreflang` set with no `x-default` | error |
| duplicate `hreflang` locales | error |
| structured data that does not serialize, or a breadcrumb crumb with no name or URL | error |
| title over 60 characters | warning |
| description outside 50–160 characters | warning |

## 5. Verification

- `spec/requests/documentation/seo_spec.rb` — **18 examples** against the head a crawler actually receives:
  canonical; `property` for Open Graph and `name` for Twitter with `name="og:image"` asserted **absent**;
  Twitter title and description; published and modified times; both JSON-LD blocks parsed and their breadcrumb
  positions checked; organisation attribution rather than the author; no `hreflang` for a single-language
  article; both directions of a translation pair plus `x-default`; a draft translation not announced; a
  category page as `website` with no article time; the sitemap's count, alternates, `lastmod` and draft
  exclusion; and every `robots.txt` rule.
- `spec/lib/tasks/rake/task_documentation_seo_audit_spec.rb` — 6 examples: a clean article passes; a missing
  description fails with a non-zero exit; a short description warns without failing; a duplicate canonical
  fails; a reciprocal translation pair passes; an empty installation says so rather than claiming success.
- Regression: `spec/requests/documentation`, `spec/controllers/public/api/v1/portals`,
  `spec/custom/services/documentation` — **383 examples, 0 failures**.

## 6. One finding about the test data, kept here because it is a product fact

An article's locale is **not** independently settable: `Article#ensure_locale_in_article` overwrites it with
the category's locale whenever the article has a category. So a translation must live in that language's
category — which is exactly what the content seeder does, and what the hreflang work therefore relies on.
Worth recording, because a spec that creates an "Arabic" article in an English category gets an English
article and a silently empty `hreflang` set.
