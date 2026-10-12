# Security and performance: the four subsystems nobody had looked at

Every other document here describes something this project changed. This one describes four subsystems it
did **not** change, examined because no reader had examined them and three of them sit on the public internet.

The point of the exercise was to find out which of the four were actually at risk, and the answer is: one was
untested, one has a measured cost nobody had measured, and two were sound. Reporting all four as "hardened"
would have been the easier write-up and a false one.

| subsystem | verdict | evidence |
|---|---|---|
| Public documentation search | **was untested** → 9 examples added | the examples fail when the protections are inverted |
| HTTP caching of the docs host | **measured, not changed** | 18 queries fresh, 13 on a 304 |
| Markdown rendering on the public surface | **sound** | 9 injection attempts, all neutralised |
| `CustomFilter` saved filters | **sound** | isolation covered; the ceiling applies on use |

---

## 1. Public documentation search — no spec existed

`spec/requests/documentation/` held `entry_points_spec.rb`, `global_ownership_spec.rb` and `seo_spec.rb`.
Nothing exercised `Public::Api::V1::Portals::SearchController`, which is a public, unauthenticated endpoint
that queries the article table.

Reading it, the protection is real but **accidental in shape**:

```ruby
@articles = @portal.articles.published.includes(:category).where(locale: params[:locale])
search_articles   # @articles.search(search_params), and search_params permits :status
```

`search_params` permits `:status` and `Article.search` passes it to `search_by_status`, which ANDs
`where(status: …)` onto a relation that is already `.published`. So `?status=draft` produces
`status = 1 AND status = 0` — empty, not the drafts. The protection is the **ordering**: `.published` is
applied before the search. Move it after, and the endpoint serves unpublished articles to anyone.

Two things were checked rather than assumed:

* `Article.where(status: 'bogus')` does **not** raise on this Rails version — it compiles to
  `status IS NULL`. So a crafted value is an empty result, not a 500 on a public endpoint.
* A blank query returns `.none`, not `.all`. Without that, an empty search box would page through the whole
  corpus.

`spec/requests/documentation/search_spec.rb` now holds nine examples: a published article is found; a draft,
an archived article, another locale's article and another portal's article are not; a crafted `status=draft`
returns nothing; a `status` that is not a status answers 200 with no results; a blank query returns nothing;
and a body-only term matches without the body's raw markup reaching the page.

**They were verified to have teeth.** Dropping `.published` and changing `.none` to `.all` in the controller
fails four of the nine. An example that cannot fail is not a test.

One trap worth recording for whoever writes the next one: the documentation layout's sidebar lists the
portal's published articles, so a title appears on the page whether or not it **matched**. Asserting
`body).to include(title)` passes with zero results. Zero results is asserted on the empty state the template
renders for `@articles.empty?`, which cannot coexist with a result — and the comparison has to be
HTML-escaped, because the string carries apostrophes and the template emits `&#39;`.

## 2. HTTP caching of the docs host — measured, deliberately not changed

The only `expires_in` anywhere in the public portal controllers is on the tracking pixel
(`articles_controller.rb:43`, `24.hours, public: false`). The article, category, portal-home and search pages
set no cache headers at all.

Measured on an article page with eleven published siblings in its category:

| | status | queries | bytes |
|---|---|---|---|
| fresh request | 200 | **18** | 23,631 |
| revalidated (`If-None-Match`) | 304 | **13** | 0 |

`Cache-Control: max-age=0, private, must-revalidate`.

Rails does emit a weak ETag, so a repeat visitor gets a 304 — but the digest is computed from the rendered
body, so **the 304 still pays 13 queries and a full Markdown render**. The saving is bandwidth only. And
`private` means no CDN or shared cache can hold the page, so every visitor and every crawler re-renders it.

### Why this is recorded rather than fixed

The fix is `fresh_when` with a composed validator, and composing it wrongly is worse than not having it. The
rendered page depends on **four** things, not one:

* the article (`content`, `title`, `meta`)
* the portal (`name`, `config`, `custom_domain`, colour scheme)
* the category's sibling article list, for the sidebar
* `GlobalConfig.get('LOGO_THUMBNAIL', 'BRAND_NAME', 'BRAND_URL', 'INSTALLATION_NAME')`

An ETag from `@article` alone — the obvious implementation — serves a **stale 304 after a rebrand**: the
installation name changes, every page still validates against the old article timestamp, and nobody sees the
new name until an article is edited. That is a silent wrongness of exactly the kind the rest of this project
has been removing, so it is not something to add in passing.

What would make it safe, for whoever takes it:

1. `fresh_when(etag: [@article, @portal, @global_config, sibling_max_updated_at], public: true)`, and
   `public: true` only once somebody has confirmed no page on this host carries per-visitor content.
2. The view counter is **not** a blocker: views are incremented by the separate tracking-pixel request, not
   by the page render, so a cached page does not lose a count. This is the fact that makes caching possible
   at all, and it is worth stating because it is not obvious.
3. A spec that changes the brand name and asserts the page does **not** 304.

## 3. Markdown rendering on the public surface — sound

`ChatwootMarkdownRenderer#render_article` ends in `.html_safe` with no sanitizer, which is what drew
attention. It is nonetheless safe, and the reason is in the renderer rather than the view.

`CustomMarkdownRenderer` is a `CommonMarker::HtmlRenderer` constructed with no options, so `:UNSAFE` is not
enabled, and the gem's own `html`/`inline_html` emit `<!-- raw HTML omitted -->` rather than the content
(`commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb:110-126` — read, not remembered). Its
`#html` override forwards to `super` for anything that is not the editor's `cw-colwidths` comment, so the
suppression is not bypassed. `MarkdownRendererUrlSanitizer` strips `javascript:`, `vbscript:`, `file:` and
`data:` from link and image URLs, keeping `data:image/{png,gif,jpeg,webp}`. `#text` escapes.

Proved against the real renderer rather than argued:

| input | output |
|---|---|
| `<script>alert(1)</script>` | `<!-- raw HTML omitted -->` |
| `hello <img src=x onerror=alert(1)> there` | `<p>hello <!-- raw HTML omitted --> there</p>` |
| `[click](javascript:alert(1))` | `<a href="">click</a>` |
| `[click](vbscript:alert(1))` | `<a href="">click</a>` |
| `[click](data:text/html;base64,…)` | `<a href="">click</a>` |
| `![x](data:image/png;base64,…)` | `<img src="data:image/png;base64,…">` — allowed, as intended |
| `![x](javascript:alert(1))` | `<img src="">` |
| `<iframe src=//evil></iframe>` | `<!-- raw HTML omitted -->` |

Nine attempts, none surviving.

### What the CSP is actually for here

`config/initializers/content_security_policy.rb` sets `object-src 'none'` and `base-uri 'self'` app-wide and
**deliberately** omits `default-src`/`script-src`/`style-src`, because those have to be enumerated from what
the dashboard, widget, SDK and portal really load and a policy that misses one source breaks a feature in
production.

That is the right posture, and it is worth being precise about why: on this surface the CSP is
defence-in-depth over a renderer that already suppresses the vector, not the thing holding the vector shut.
Articles are authored only by Super Admins, so the injection would have to come from an operator in the
first place. Stage two of the CSP remains worth doing for the dashboard; it is not what stands between a
visitor and an article's markup.

## 4. `CustomFilter` saved filters — sound

Two questions, both closed.

**Can one user read or change another's saved filter?** No.
`Api::V1::Accounts::CustomFiltersController#fetch_custom_filter` reads
`Current.account.custom_filters.where(user: Current.user).find(id)`, so the account and the user are both in
the scope and a miss is a `RecordNotFound` → 404, not a 403 that confirms existence. Already covered:
`spec/controllers/api/v1/accounts/custom_filters_controller_spec.rb` has 23 examples, including "prevents the
update of custom filter of another user/account" asserting 404.

**Can a saved filter reach conversations the user may not see?** No, and the reason is that the saved payload
has no privileged path. `query` is arbitrary JSON, but applying it runs through
`Conversations::FilterService#base_relation`, which hands the relation to
`Conversations::PermissionFilterService` before any filter predicate is applied — the same Inbox/Team ceiling
(`Conversations::AccessCeiling`) every other list path uses. A saved filter therefore grants nothing a user
could not already get by typing the same payload into the same endpoint, and both are bounded by the ceiling.

So the arbitrary-JSON column is not the risk it looks like: it is a convenience over an endpoint that is
itself authorized.
