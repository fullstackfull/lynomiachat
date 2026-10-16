# 07 — Technical SEO

**Status:** implemented and tested. W5.
**Verified on the rendered HTML**, not on the presence of helper methods — every claim below has an example in
`spec/requests/marketing/seo_spec.rb` or was measured by the browser crawl recorded in `09-test-results.md`.

---

## 1. What the previous site had

Two `<meta>` and three `<link>` elements in total. No description, no canonical, no hreflang, no Open Graph, no
Twitter card, no structured data, no sitemap, and `lang`/`dir` set by a click handler that fired on every load
— so an Arabic visitor was flipped to English before they read a word
(`01-current-state-audit.md` sections 3.3 and 5).

Everything in this document is new.

---

## 2. One host-resolution point

`MarketingHelper#marketing_host` is the only place a marketing URL's host is decided, and every absolute URL
goes through `marketing_absolute_url`. The canonical, both hreflang alternates, `og:url` and every `<loc>` in
the sitemap are therefore built from the same string and cannot disagree.

It reads `FRONTEND_URL` first and `HELPCENTER_URL` second. That order is a correction made during this work:
the first version read the help-centre variable first, which in Chatwoot names a *separate* host for the Help
Center — so on any installation that sets it, every marketing canonical, hreflang, `og:url` and sitemap entry
pointed at the documentation host instead of the website's own.

With no host configured, URLs come out root-relative rather than with a fabricated host. That is deliberate:
interpolating a blank host is exactly how `https://hc/hc/...` reached production canonicals on the
documentation side.

---

## 3. Per-page metadata

Built once per request from the `Marketing::Page` the controller resolved, in
`custom/app/views/marketing/shared/_head.html.erb`:

| Tag | Source | Operator override |
|---|---|---|
| `<title>` | the page's title + the site name | the title field |
| `<meta name="description">` | the page's description | the description field |
| `<link rel="canonical">` | this page's own address | `meta.canonical_url`, validated |
| `<link rel="alternate" hreflang="ar\|en">` | the published sibling, by `[kind, key]` | — |
| `<link rel="alternate" hreflang="x-default">` | the Arabic page, when published | — |
| `<meta name="robots" content="noindex, nofollow">` | emitted only for an unpublished or `noindex` page | the SEO switch |
| `og:type`, `og:site_name`, `og:locale`, `og:url` | the page and its locale | — |
| `og:title`, `og:description` | the title and description | `meta.og_title`, `meta.og_description` |
| `og:image` | the first `image` section | `meta.og_image_id` |
| `twitter:card` | `summary_large_image` **when there is an image**, else `summary` | — |

Two of those are corrections rather than features:

* **hreflang points only at published siblings.** It used to emit both locales unconditionally from a
  hardcoded list, which was harmless while every page was a template and wrong once a page became a row: an
  alternate pointing at a draft tells a crawler to index a 404. The set is suppressed entirely below two
  locales, which is the rule the documentation side already applies.
* **The Twitter card type follows the image.** `summary_large_image` with no `og:image` is a card that
  promises a picture and shows a blank — the same defect the documentation head records having fixed.

Measured across all 96 URLs at two viewports: 192/192 page loads carry a title, a description, a canonical and
the full `ar` + `en` + `x-default` set; `lang`/`dir` is `ar`/`rtl` on 96 and `en`/`ltr` on 96; exactly one
`<h1>` per page.

---

## 4. `/sitemap.xml`

Genuinely unrouted before this work. Now `Marketing::SitemapController`, at the one address crawlers look for
and `robots.txt` advertises.

* **One sitemap for both locales.** The Arabic and English versions of a page are separate `<url>` entries
  carrying `xhtml:link` alternates to each other plus an Arabic `x-default` — the arrangement the protocol
  asks for and the one the documentation portal already uses. A `/en/sitemap.xml` would be a second, partial
  answer to the same question.
* **Published and indexable only.** `SitePage.live` minus anything marked `noindex`. A draft answers 404, so
  announcing it earns a soft-404; a page asking not to be indexed must not be advertised, or the site
  contradicts itself in two files.
* **`lastmod` is `updated_at`**, the only modification date a page actually records. `published_at` is when it
  first went live — a different fact, and wrong here: a page edited this morning and first published last year
  must report this morning.
* **Not served on a tenant custom domain.** The controller inherits the marketing base controller for one
  filter, so a tenant's Help Center domain cannot serve Lynomia's sitemap.

---

## 5. `robots.txt`

Extended, not replaced. `RobotsController` is the one robots implementation in this application; the marketing
site adds two lines to it.

* `Sitemap: https://<host>/sitemap.xml`, first, because it is the sitemap for the site this host primarily
  serves. It is **omitted entirely when no host is configured** — a `Sitemap:` line must be absolute, and a
  crawler reports a wrong one as an error and stops asking, so a wrong line is worse than none.
  It sits in `#body` rather than inside `sitemap_lines`, which reads the Portal table and is wrapped in a
  rescue so a cold boot with no database still answers robots.txt. This line needs no database at all, so
  putting it there would make it disappear in exactly the situation it still works in.
* `Disallow: /*?preview=`. To a signed-in super admin that URL is a draft carrying `noindex`; to an anonymous
  crawler it is the **published** page with a canonical pointing at the clean address — a duplicate with a
  correct canonical, which is crawl budget spent for nothing.

Everything the file disallowed before is unchanged: `/widget` (a widget load creates a contact before it
renders), `/app/`, `/super_admin/`, `/api/`, `/installation/`, `/rails/`, and the four `/hc/*` patterns.

---

## 6. Structured data

Built from the objects the page already rendered, so it cannot describe something the page does not show.

| Node | Where | Built from |
|---|---|---|
| `Organization` | the home page only | the brand name, the company URL, a real logo file |
| `WebSite` | the home page only | the site name, the home address, the current locale |
| `BreadcrumbList` | every detail page | the **same array** the visible trail renders from |
| `FAQPage` | `/faq` | the **same `SiteFaqEntry` rows** the reader sees |

`Organization` and `WebSite` are on the front page and nowhere else: repeating them on all 48 pages per locale
says nothing extra. Nothing at all is emitted for a page that is not indexable.

**No conflict with Documentation V2.** It emits `BreadcrumbList` and `TechArticle` per article and nothing
else — there is no top-level `Organization` or `WebSite` node anywhere else in this application, and the two
URL spaces do not overlap. These are the installation's only such nodes rather than a second opinion.

### What is deliberately absent

Every value is a fact this repository can point at, so:

* no `aggregateRating` or `review` — none exists;
* no `sameAs` social profiles — the site publishes none, and guessing a handle publishes a claim;
* no `foundingDate`, `numberOfEmployees` or `address` — not published anywhere this repository can read;
* no `offers` or `priceRange` — there is no published price (doc 02 §4);
* **no `SearchAction`** on the `WebSite` node — the marketing site has no search, and a `SearchAction` naming
  a URL template that 404s is the kind of structured data that earns a manual action.

### Escaping

`json_escape(payload.to_json)` — `to_json` escapes the content and `json_escape` neutralises `<`, `>` and `&`,
so a `</script>` an operator types into a heading cannot end the block early. Tested with exactly that input:
the page does not contain the breakout, and the parsed node still contains the text.

---

## 7. Breadcrumbs

Visible on every detail page: site home → the index it belongs to → the page itself, the last with
`aria-current="page"` and no `href`. The machine-readable `BreadcrumbList` is built beside it from the same
array.

Standing pages carry no trail. They are one level below the home page, so a two-item breadcrumb would be
chrome rather than navigation.

---

## 8. Redirects

`SiteRedirect`, managed in Super Admin, covering the one URL space the CMS can change: a detail page's slug.

| Property | How |
|---|---|
| correct status codes | `permanent` → 301, otherwise 302 |
| no open redirects | an absolute or protocol-relative `to_path` is refused on save; `raise_on_open_redirects` is on; the controller passes `allow_other_host: false` |
| no loops | the chain is walked from the destination through existing redirects; a save that returns somewhere it has been, or runs past ten hops, is refused with the chain named |
| no shadowing protected routes | structural: a redirect is consulted only from the marketing detail action, so a row naming `/app/login` or `/super_admin` can never be reached. Two examples assert it rather than a validation guarding an unreachable case |
| chains work | each hop is one redirect, which is what the protocol expects — tested three deep |

**The documented limit:** a path that matches no route at all never reaches the lookup, so `SiteRedirect`
cannot rescue an arbitrary retired URL. It covers renamed detail slugs, which is the whole set the CMS can
break.

---

## 9. Indexing summary

| State | In the sitemap | `noindex` | Reachable |
|---|---|---|---|
| published, not flagged | yes | no | yes |
| published, `noindex` ticked | no | yes | yes |
| draft | no | yes (on preview) | 404, or preview for a signed-in super admin |
| archived | no | yes (on preview) | 404 |

---

## 10. What is not done, and why

* **No analytics or tag manager.** Nobody asked for one, and adding a third-party script to a zero-JavaScript
  site is a decision with privacy consequences that belongs to the owner.
* **No `Link: rel="canonical"` header** on any marketing response. Every marketing page is HTML and carries a
  `<link>`; the header matters for non-HTML responses, and the one this site serves — the sitemap — is not a
  duplicate of anything.
* **No image sitemap.** The 96 pages ship with no images at all; the markup would be dead on arrival. The
  entry point if that changes is `custom/app/views/marketing/sitemap/show.xml.erb`.
* **The CSS is 1.46 MB uncompressed**, 138 KB gzipped, because Tailwind's content globs are
  application-wide — so the marketing page downloads every class the dashboard uses. Measured, recorded in
  `09-test-results.md` with the remedy, and not fixed here: a marketing-only Tailwind config is a build-system
  change with its own risk, and gzip (now in the vhost) takes the over-the-wire cost to 138 KB.
