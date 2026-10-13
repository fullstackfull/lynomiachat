---
agent: 074
scope: Sitemap and robots.txt for the public documentation (docs + changelog portals): what exists, what is missing, minimum correct implementation
confidence: high
---

# 074 - Sitemap and robots for the public documentation

**Short answer.** Both exist and both are mostly correct. There is no sitemap gem and no static file: the sitemap is
the Help Center's own per-portal `portals#sitemap` action, rewritten by commit `a6dc20d9` (2026-10-12, ancestor of
`HEAD`) to carry canonical `<loc>`, `lastmod` and hreflang alternates; `robots.txt` is a dynamic controller that
replaced upstream's static file. Drafts and archived articles are excluded, the `/docs/:slug` redirect is excluded by
construction, and the changelog has its own sitemap and its own `Sitemap:` line. What is missing is not a feature but
five correctness gaps: retirement (the sitemap is only as true as the seeder), `noindex` for non-canonical variants,
the sitemap's query cost, a stale spec that contradicts the live robots body, and an unscoped `Sitemap:` list.

Nothing was run (charter 6.1: no rails/rspec). "Measured" below means read from the template, helper and controller.
Protocol limits quoted from sitemaps.org and Google are recalled, not fetched (the brief did not authorise network
reads) and are marked as such.

## 1. What exists today

| Question | Answer | Evidence |
|---|---|---|
| Is there a sitemap at all? | Yes, one dynamic XML sitemap **per portal**. No sitemap gem, no `public/sitemap*`, no root `/sitemap.xml` route, no sitemap index. | `grep -i sitemap Gemfile Gemfile.lock` returns nothing; `ls public/` has no sitemap or robots file; route `config/routes.rb:509` -> `app/controllers/public/api/v1/portals_controller.rb:17-21` -> `app/views/public/api/v1/portals/sitemap.xml.erb`; spec asserts `urlset`, never `sitemapindex` (`spec/controllers/public/api/v1/portals_controller_spec.rb:207-208`) |
| What does `robots.txt` serve? | A dynamic body from `RobotsController#show`; no static file. | route `config/routes.rb:40`; `app/controllers/robots_controller.rb:19-31`; `public/robots.txt` does not exist (removed by upstream #15873, `docs/chatwoot-upgrade/03-conflict-resolution.md:55`); no web-server config mentions robots (`grep` over `deployment docker clevercloud Procfile* app.json` empty) |
| Are documentation articles in the sitemap? | Yes: every article of the portal with `status = published`, one `<url>` per locale-article. | `sitemap.xml.erb:14` `@portal.articles.where(status: :published).includes(:root_article)` |
| `<loc>` | The article's canonical, the same helper the page's `<link rel="canonical">` uses. | `sitemap.xml.erb:16`; `custom/app/helpers/documentation_helper.rb:15-17`; `documentation_layout/articles/_meta_head.html.erb:7,11` |
| `lastmod` | `article.updated_at.to_date.iso8601`, date only. | `sitemap.xml.erb:17`. Not bumped by view counts (`article.rb:144-146` uses `update_column`) or by draft autosave; bumped by any real save, including a reorder (see D8). |
| Locale alternates | `xhtml:link rel="alternate"` for every **published** sibling including the article itself, plus `x-default` (the portal's default-locale sibling). Emitted only when the family has 2+ members. Reciprocal because both directions come from the same family method. | `sitemap.xml.erb:18-23`; `documentation_helper.rb:44-60,106-109`; spec `spec/requests/documentation/seo_spec.rb:98-130,157-165` |
| Is the changelog portal included? | Yes, but as a **separate** sitemap: `/hc/lynomia-changelog/sitemap.xml`, same route and template. It is named in `robots.txt` because the `Sitemap:` list covers every non-archived portal. There is no combined sitemap. No spec exercises the changelog portal's sitemap. | `config/routes.rb:509`; `robots_controller.rb:36`; slugs `custom/app/services/documentation/library.rb:8-10`; changelog corpus is 1 note x 2 locales (`custom/db/changelog/{en,ar}/releases/first-release-note.md`) |
| Are draft articles excluded? | Yes, three ways: the sitemap filters `published` (`sitemap.xml.erb:14`); hreflang siblings are filtered `published` (`documentation_helper.rb:108`); and the page itself 404s a draft for anyone but a signed-in super admin (`articles_controller.rb:80-83`). Archived is excluded by the same filter. Spec: `seo_spec.rb:146-148,167-169`. | as cited |
| Is the `/docs/:slug` redirect excluded? | Yes, by construction: the sitemap only ever emits `portal_canonical_url`, which is `/hc/<portal>/articles/<slug>`. `/docs`, `/docs/:slug`, `/changelog` appear nowhere in the sitemap. | `sitemap.xml.erb:16`; routes `config/routes/documentation.rb:22,25-27`; `documentation_controller.rb:9,13,25` |
| What does robots allow/disallow? | `User-agent: *` only. Disallow: `/widget`, `/app/`, `/super_admin/`, `/api/`, `/installation/`, `/hc/*?theme=`. No `Allow` lines, no per-bot rules. Everything else, including all of `/hc/`, `/docs`, `/changelog`, is allowed by default. One `Sitemap:` line per non-archived portal. | `robots_controller.rb:17,26-30,36-39` |
| `noindex` in the documentation layout? | **None.** No `noindex` in any `portal.*` layout, in `_portal_head.html.erb`, in any `public/api/v1/portals/**` view, and no `X-Robots-Tag` anywhere in `app/`, `custom/`, `lib/`, `config/`. `noindex` exists only on the dashboard (`layouts/vueapp.html.erb:6-8`, non-cloud only), Super Admin (`layouts/super_admin/application.html.erb:19`, `super_admin/devise/sessions/new.html.erb:4`), onboarding (`installation/onboarding/index.html.erb:4`) and the widget (`widgets/show.html.erb:7`). | `grep -rniE 'noindex\|X-Robots' app config lib custom` |

## 2. Measured behaviour

**`GET /robots.txt`** (read from `robots_controller.rb:25-31`; `<host>` is `portal.custom_domain` or
`HELPCENTER_URL`/`FRONTEND_URL`, `lib/chatwoot_app.rb:35-37`, whose production values are not checked):

```
User-agent: *
Disallow: /widget
Disallow: /app/
Disallow: /super_admin/
Disallow: /api/
Disallow: /installation/
Disallow: /hc/*?theme=
Sitemap: https://<host>/hc/lynomia-docs/sitemap.xml
Sitemap: https://<host>/hc/lynomia-changelog/sitemap.xml
Sitemap: ... one line for every other non-archived portal of every account ...
```

The portal list is `Portal.where(archived: false)` with no `order` (`robots_controller.rb:36`), so line order is
unspecified. Any exception while reading it returns the rules with no `Sitemap:` lines (`robots_controller.rb:41-44`,
deliberate, documented at `docs/product-refinement/03-documentation-seo.md:105-106`). `RobotsController` inherits
`ActionController::Base`, so it answers on every host, custom domains included.

**`GET /hc/lynomia-docs/sitemap.xml`** emits, per published article:

```
<url>
  <loc>https://<host>/hc/lynomia-docs/articles/<slug></loc>
  <lastmod>YYYY-MM-DD</lastmod>
  <xhtml:link rel="alternate" hreflang="en" href=".../articles/<slug>"/>
  <xhtml:link rel="alternate" hreflang="ar" href=".../articles/<slug>-ar"/>
  <xhtml:link rel="alternate" hreflang="x-default" href=".../articles/<slug>"/>
</url>
```

Corpus size at this commit: 63 EN + 63 AR documentation files plus 1 EN + 1 AR changelog files (`find custom/db/...`),
so at most 128 `<url>` entries across the two sitemaps; ~0.6 KB per entry by my estimate, ~75 KB total.

Behaviours worth stating because nothing asserts them: the sitemap action has no `ensure_custom_domain_request`
(`portals_controller.rb:4` restricts it to `:show`), so it answers on any host (already recorded in
`docs/product-enablement/08-documentation-existing-system-study.md:252`); no spec asserts the response
`Content-Type`; the route carries a literal `.xml` and no `:format`, so format negotiation falls to the `Accept`
header (unverified for a client that sends only `Accept: text/html`).

## 3. Defects

| # | Severity | Defect | Evidence | Impact |
|---|---|---|---|---|
| D1 | major | **The sitemap is only as true as the seeder, and the seeder cannot retire.** It upserts by slug and never deletes or archives; a renamed, split or merged file leaves the old article published, so the old URL stays in the sitemap with its own (different) canonical beside the new one. It also forces `status` on every run, so an article an operator unpublished returns to the sitemap at the next sync. | `custom/app/services/documentation/content_seeder.rb:73` (`find_or_initialize_by(slug:)`), `:101` (`status: published` every run), no `destroy`/`archive` in the file; audit only catches *identical* canonicals (`lib/tasks/documentation_seo_audit.rake:50-60`) | Phase 4's SPLIT/MERGE/RETIRE/RELOCATE verdicts will publish duplicate content into the sitemap that no check flags. Whether production already holds orphans: **not checked** (no production access). |
| D2 | major | **A spec asserts a robots.txt that no longer exists.** `search_indexing_spec.rb:104-111` expects the body to equal `"User-agent: *\nDisallow: /widget\n"`; the controller now emits six Disallows plus `Sitemap:` lines. By reading, the example fails. Last touched by upstream #15873, not by `a6dc20d9`. | `spec/requests/search_indexing_spec.rb:110` vs `robots_controller.rb:26-30`; correct assertions are `seo_spec.rb:176-197` | A red example in the suite, or pressure to revert the controller. Not run (charter 6.1). |
| D3 | minor now, major at 5-10x | **Sitemap request cost.** Unbatched `.each` over full rows (`content`, `draft_content` included) and, because `includes(:root_article)` preloads only the root, one `associated_articles` query per article family (an EN article and each AR article's root each trigger one): about N+2 queries and the corpus read about twice per request. No `expires_in`, no `fresh_when`, no cache. Reasoned from code, not measured. | `sitemap.xml.erb:14`; `documentation_helper.rb:106-109` (called twice per article, `sitemap.xml.erb:18,21`); no caching in `app/controllers/public/` apart from the tracking pixel (`articles_controller.rb:43`); only throttle is the global 3000/min/IP (`config/initializers/rack_attack.rb:71`) | Public, unauthenticated, every crawler and monitor pays it. Already recorded as "known cliff" in `docs/global-documentation/11-search-and-locales.md:146`. |
| D4 | minor (decision) | **`Sitemap:` lines cover every non-archived portal of every tenant**, via `Portal.where(archived: false)`, bypassing `Documentation::Library.portals` (the "single door", `library.rb:37-39`). The SEO audit does the same (`documentation_seo_audit.rake:34`). Deliberate per `03-documentation-seo.md:103-105`, but unordered, a DB hit per request, and unbounded in tenants. | `robots_controller.rb:36` | `robots.txt` becomes a directory of tenant help centers; at thousands of portals it outgrows crawler size limits (Google documents a 500 KiB cap, recalled not fetched). For the owner to arbitrate: should Lynomia's robots file advertise tenant portals at all? |
| D5 | minor | **No `noindex` and no canonical on the non-canonical variants.** Search results (`search/index.html+documentation.erb:1-3` sets a `<title>` only), the plain-layout variant (`?show_plain_layout=true`; classic head has no canonical, `articles/_meta_head.html.erb:1-21`), and the HTML `articles#index` listing are indexable. Reach is limited: the docs search is a JS widget (`documentation_layout/_hero.html.erb:14-15`) and results are only linked from result pages or external URLs. `Disallow: /hc/*?theme=` matches only when `theme` is the *first* query parameter, and by blocking the fetch it stops the crawler reading the canonical on those URLs. | `portal.html+documentation.erb` / `_portal_head.html.erb:16-20` (no robots meta); routes `config/routes.rb:511-512` | Thin duplicate / query-string URLs can enter the index if linked externally. |
| D6 | minor | **The `.md` endpoint is an indexable duplicate of every article.** It is linked from every article page (`documentation_layout/articles/_actions.html.erb:3,16`, rendered from `_header.html.erb:10`), served as `text/markdown` with no `X-Robots-Tag` and no canonical header, and is not in robots. It must stay fetchable: the same menu builds "Open in ChatGPT / Claude" prompts that hand those tools this URL (`_actions.html.erb:4-6`). Whether such fetchers honour robots.txt is **not verified**; whether a given engine indexes `text/markdown` is **not verified**. | route `config/routes.rb:517-518`; `articles_controller.rb:29-33` | Duplicate text competing with the HTML page. A robots `Disallow` could break the AI-prompt feature; a header does not. |
| D7 | minor | **Hub pages are not in the sitemap and the home has no head.** Category pages carry a canonical (`documentation_layout/categories/_meta_head.html.erb:8-11`) but are not listed; the locale home (`/hc/<slug>/en`, `/ar`) has neither canonical nor description (`show.html+documentation.erb` sets no `content_for :head`, so `_portal_head.html.erb:19` emits a bare `<title>`). `/hc/<slug>` is a 302 to the default locale (`portals_controller.rb:30-35`). | as cited | Discovery of hubs relies on internal links only. Canonical for the home is agent 073's. |
| D8 | minor | **`lastmod` is `updated_at`, so reordering lies.** `Article.update_positions` uses `update!(position:)` (`article.rb:157`) and a front-matter `position` change in the seeder is an attribute diff (`content_seeder.rb:76-78`), both of which bump `updated_at` without any content change. `release_date` (changelog) is a release date, not a modification date, and should not replace it. | as cited | Inflated `lastmod` on a mass edit; Google may stop trusting `lastmod` site-wide (recalled guidance, not fetched). |
| D9 | minor | **Draft locales are not honoured.** `Portal#draft_locale?`/`public_locale_codes` feed only the language switcher (`documentation_layout/_topbar.html.erb:44,55`, `_header.html.erb:89`); the sitemap and the hreflang family ignore them (`sitemap.xml.erb:14`, `documentation_helper.rb:108`). Not reachable for the two platform portals (the portal seeder drafts nothing, `portal_seeder.rb:62-66`); reachable for tenant portals. | as cited | A locale marked draft is still announced to crawlers. |
| D10 | minor | **Dead code in the sitemap action.** `@help_center_url` is computed and never read by the view; if a portal has no custom domain and neither `HELPCENTER_URL` nor `FRONTEND_URL` is set, `nil.include?` raises. | `portals_controller.rb:18-20` vs `sitemap.xml.erb` (no reference) | Noise now; a 500 in a misconfigured install (which per repo policy should fail loudly, so removing the dead line is the whole fix). |

Redirect status of `/docs`, `/docs/:slug`, `/changelog` is `302` (default `redirect_to`, `documentation_controller.rb:9,13,25,33`), and `/docs` chains through a second `302` at `/hc/lynomia-docs`. That is retirement/redirect territory (agent 079), noted here only because it is why those addresses are not, and should not be, in the sitemap.

## 4. What a larger corpus breaks

- **Request cost grows linearly with a large constant** (D3). At 128 articles roughly 130 queries and ~1 MB of text twice; at 10x, about 1,300 queries and ~10 MB per fetch of an uncached public URL.
- **Protocol limits are not the threat for the docs portals.** The sitemaps.org per-file cap (50,000 URLs / 50 MB uncompressed, recalled not fetched) is about 390x today's count. It matters only if tenant portals ever share a file, which they do not (one file per portal).
- **Churn makes D1 worse.** Phase 4 grows the corpus several times *and* renames, splits and merges; each rename adds a live, sitemap-listed duplicate. The audit's duplicate check compares canonical strings, so two slugs for one topic pass.
- **`lastmod` degrades under mass edits** (D8): a front-matter change touching all 126 files stamps one date on every URL.
- **`robots.txt` grows with tenants, not with the corpus** (D4); the corpus has no effect on it.
- **hreflang cost is quadratic in locales.** Each URL lists the whole family (`documentation_helper.rb:44-49`), computed twice per article; harmless at 2 locales, noticeable at 6+ and compounding D3.
- **Hub pages gain value.** With hundreds of articles, category and home pages are the discovery path and are the pages not in the sitemap (D7).
- **Verification does not scale with it.** The only sitemap assertions are two articles in the docs portal (`seo_spec.rb:145-174`) and a 3-article count (`portals_controller_spec.rb:185-210`); `lynomia:docs:seo_audit` never fetches the sitemap or robots (`documentation_seo_audit.rake:34-75`).

## 5. Recommendations

The minimum correct implementation is **not** a new sitemap or robots feature. It is this, in priority order, each on an
existing system.

1. **Make retirement real, so the sitemap stays true (D1).** In `Documentation::ContentSeeder`, archive (`status: :archived`) any platform article whose slug is no longer produced by the manifest, and decide the rule for an operator-unpublished article (stop forcing `status` on update, or accept re-publish). No sitemap change is needed: `sitemap.xml.erb:14` and `articles_controller.rb:80-83` already drop archived articles. Design belongs to 079; the sitemap is its test oracle.
2. **Fix the stale spec (D2).** Rewrite `spec/requests/search_indexing_spec.rb:104-111` to assert the Disallow set and drop the exact-body equality, or delete it in favour of `seo_spec.rb:176-197`. Needed before anyone trusts a green run.
3. **Cap the sitemap's cost (D3, D10).** In `PortalsController#sitemap`: preload `includes(:associated_articles, root_article: :associated_articles)` so the family needs no per-article query (confirm with a query-count expectation in `seo_spec.rb:145`), select only the columns the view and helper read, and add `fresh_when(etag: [published.maximum(:updated_at), published.count])` so conditional crawlers get a 304. Delete the dead `@help_center_url` lines.
4. **Control the index with `noindex`, not `Disallow` (D5, D6).** One `<meta name="robots" content="noindex,follow">` under `@is_plain_layout_enabled` in `layouts/_portal_head.html.erb` (the earliest shared point; covers every plain-layout page, also for tenants); the same meta in the `content_for :head` of the search results views; `response.set_header('X-Robots-Tag', 'noindex')` in `show_markdown`. Do not also `Disallow` those paths: a disallowed URL's `noindex` is never read, and a `Disallow` on `.md` risks the AI-prompt links. Keep robots for what has side effects or no value (`/widget` creates contacts, per `robots_controller.rb:7`).
5. **Scope and order the `Sitemap:` list (D4).** `Documentation::Library.portals.order(:slug)` unless the owner decides tenant portals should be advertised from the installation's robots file. This is a product decision, not a defect to fix silently.
6. **Optional, after 073 gives the home a canonical (D7).** Add `portal_home_url` for each `portal.public_locale_codes` and `portal_category_canonical_url` for categories with a published article to `sitemap.xml.erb`; both helpers already exist (`documentation_helper.rb:19-26`). Never add `/docs`, `/docs/:slug` or `/changelog`.
7. **Cover what is unasserted.** Add to `seo_spec.rb`: the changelog portal's sitemap lists its release and alternates; the sitemap `Content-Type` is XML; the retired/archived article is absent; the `noindex` surfaces from item 4. No change to `lynomia:docs:seo_audit` is required.
8. **Leave `lastmod` on `updated_at` (D8).** Do not substitute `release_date`. Revisit only if the seeder gains a content hash.

## 6. Not checked / unverified

- Production values of `HELPCENTER_URL` / `FRONTEND_URL` (they decide the host in every `<loc>`), whether any portal has a `custom_domain`, how many tenant portals exist, and the live `robots.txt`/`sitemap.xml` output: no production access (charter 3, 6.5).
- Whether production holds orphaned or operator-unpublished articles (D1).
- rspec was not run; D2 is a reading of the spec against the controller.
- sitemaps.org limits and Google's robots.txt size and `lastmod` guidance are recalled, not fetched.
- Whether ChatGPT/Claude link-fetchers honour robots.txt, and whether any engine indexes `text/markdown`.
- Response `Content-Type` of the sitemap and behaviour under a strict `Accept: text/html` client.

## 7. Stale prior records (do not rely on them)

`docs/global-documentation/FINAL-CHECKPOINT.md:26` and `docs/global-documentation/16-regression-results.md:206` say robots disallows only `/widget`; `docs/product-enablement/08-documentation-existing-system-study.md:396` says no canonical/hreflang and a sitemap without alternates; `docs/global-documentation/11-search-and-locales.md:120-122` says hreflang is not built. All pre-date `a6dc20d9` and are superseded by `docs/product-refinement/03-documentation-seo.md` and the code cited above.
