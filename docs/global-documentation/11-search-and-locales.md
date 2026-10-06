# 11 — Search, locales and SEO

How a reader finds an article, reads it in their own language, and how a search engine sees it. All three reuse what
the Help Center already has; none of them is a new system.

---

## 1. Search

**Reused as-is: `Article.search` → `pg_search_scope :text_search`.** No new search engine, no new index, no second
implementation.

```ruby
pg_search_scope :text_search,
                against: { title: 'A', description: 'B', content: 'C' },
                using: { tsearch: { prefix: true, normalization: 2 } },
                ranked_by: ':tsearch'
```

Title outranks summary outranks body, and the normalisation divides rank by the log of the document length so a long
article does not win merely by repeating the term.

### Scoping — P4 §12 and §24

The public search controller resolves `@portal.articles.published` for the requested locale. That single expression
gives three properties for free:

| Property | Why it holds |
|---|---|
| Global documentation never returns a tenant's private article | the query is scoped to one portal, and a tenant's articles are in a different one |
| A tenant's help centre never returns a Lynomia documentation article | the same sentence, read the other way |
| The changelog never pollutes a documentation search | the changelog is a **separate portal** (`08-changelog-design.md §4`) |

**Verified in both directions**, not assumed: `spec/requests/documentation/global_ownership_spec.rb` searches a
tenant portal for a documentation article's title and a documentation portal for a tenant article's title, and
asserts neither surfaces the other.

### Arabic search

Postgres `tsearch` with the default dictionary does not stem Arabic, so an Arabic search is effectively a prefix
match on the words as typed. For a documentation set of this size that is sufficient and was **verified against the
running application**: searching the Arabic portal for `الوسوم` returns the Arabic labels article.

What it does not do is match a different inflection of the same root. Making it do so needs an Arabic text-search
configuration in Postgres — a deployment change, recorded here as a limitation rather than guessed at.

### What is deliberately not used

The Enterprise **vector search** (`Article.vector_search` over `article_embeddings`) is gated on
`help_center_embedding_search`, which ships `enabled: false, premium: true`. A platform portal has no account to
enable it on, and `Portal#feature_enabled?` answers `false` for it deliberately
(`01-global-ownership-design.md §5`). Global documentation uses the same pg_search path every portal uses.

## 2. Locales

**Reused as-is: the Help Center's own locale model.** A translation is a separate `Article` row, not a runtime
translation layer.

| | How |
|---|---|
| Which languages a portal publishes | `portals.config['allowed_locales']` — `['en', 'ar']` |
| The default | `config['default_locale']` — `en` |
| An article's language | `articles.locale`, NOT NULL |
| How a translation is linked | `articles.associated_article_id` → the English article |
| How a reader chooses | the locale is a **URL segment**: `/hc/lynomia-docs/ar/...` |
| Right-to-left | the layout's `dir`, driven by `html_lang_attribute`. **Verified:** the Arabic page renders `<html lang="ar">` and the English one `lang="en"` |

### The slug problem, and what it forced

`articles.slug` is **globally unique**. The English and Arabic versions of one article therefore cannot share a slug
— a constraint found by running the seeder, not by reading the schema.

The answer is the one P4 §15.1 explicitly allows: **a key, not a slug.** The content file's name is the article's
stable key; each locale gets a slug derived from it (`labels`, `labels-ar`); the key is stored in `meta['doc_key']`;
and `/docs/<key>` resolves the article in the reader's language:

```ruby
def article_for(key, locale: nil)
  by_key = articles.where("articles.meta->>'doc_key' = ?", key)
  by_key.find_by(locale: locale) || by_key.find_by(locale: DEFAULT_LOCALE) || by_key.first || article(key)
end
```

So a product help link lands in Arabic for an Arabic reader and falls back to English where a translation does not
exist yet — which is better than the original design, where it would always have landed in English.

### Fallback behaviour, stated

| Situation | What happens |
|---|---|
| The reader's locale has the article | they get it |
| The reader's locale does not | they get the English one, rather than a 404 |
| Neither exists | **404** — the link fails safely rather than landing on a page that does not answer the question |
| A locale is in `draft_locales` | the whole language is held back from the public portal |

Nothing is machine-translated at runtime. Arabic is authored (`06-information-architecture.md §6`).

## 3. SEO

**Reused as-is: `_meta_head.html.erb`.** It already emits, per article:

- `<title>` as *"<article> | <portal>"*
- `name` / `og:` / `twitter:` **title** and **description**, each only when the corresponding `meta` key is present
- `name="tags"` as a comma join
- `og:image` / `twitter:image` when an OG image resolves

The content pipeline fills `meta['title']` and `meta['description']` from each article's front matter — its
`seo_title` and `seo_description`, falling back to the article's own title and summary — so every published article
has both without an author having to remember.

| P4 §14 asks for | Where it comes from |
|---|---|
| title | `meta['title']`, or the article title |
| description | `meta['description']`, or the article summary |
| canonical URL | the article's own `/hc/<portal>/articles/<slug>`; `/docs/<key>` redirects to it rather than duplicating it |
| indexability | public portal pages are ordinary HTML served to anyone; drafts return **404** and so cannot be indexed |
| article slug | stable, from the content file name |
| structured hierarchy | portal → category → article, with the sitemap at `/hc/<portal>/sitemap.xml` listing every published article with its `lastmod` |

**Not built:** structured data (JSON-LD), hreflang alternates between the English and Arabic versions, and per-article
canonical overrides. The brief says not to overbuild an SEO platform; hreflang is the one of the three worth adding
later, and it is recorded in `15-content-quality-audit.md` rather than done now.

## 4. Caching and index freshness — P4 §33

There is nothing to invalidate, and that is the honest answer rather than a gap:

- **pg_search reads the table directly.** There is no separate index to rebuild, so publishing an article makes it
  searchable in the same transaction.
- **The public portal is not page-cached** in this application. The tracking pixel sets `expires_in 24.hours,
  public: false`, which is a private browser cache for the pixel only and deliberately bypasses a CDN.
- **The one index that does exist** — EE's `article_embeddings`, refreshed by `Portal::ArticleIndexingJob` — is
  behind the feature flag that a platform portal answers `false` for, so it never runs for documentation.

If a CDN is put in front of the documentation later, that is where invalidation will have to be configured, and the
sitemap's `lastmod` is already correct for it.

## 5. Performance — P4 §32

| Risk | Status |
|---|---|
| Loading every article body to render navigation | the sidebar selects whole rows; at 43 articles this is immaterial, and it is the Help Center's own query |
| N+1 on categories and articles | the category page uses `includes(:author)`; the sidebar groups one query |
| Search across tenant and global content | impossible by construction — the query is portal-scoped |
| Unbounded article payloads | the public article index caps `per_page` at 100, default 25 |
| The sitemap loading every published article | true, and unbatched upstream. At documentation scale it is fine; recorded as a known cliff |
