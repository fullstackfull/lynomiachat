---
agent: 080
scope: Core Web Vitals and image SEO on the public documentation portal, ahead of the first images in the corpus
confidence: medium
---

Confidence is **high** for what the code and the local build contain, **medium** overall because nothing here was measured in a browser or
against a running server (Phase 1 forbids it): no LCP, CLS or INP number in this report is a field or lab measurement. Where a statement is an
inference from framework behaviour it says so, and section 5.9 lists the commands that would turn each inference into a measurement.
Google's Core Web Vitals "good" thresholds (LCP <= 2.5 s, CLS <= 0.1, INP <= 200 ms at the 75th percentile) are quoted from memory and were
not re-fetched, because this brief did not authorise external research.

## 1. What exists today

### 1.1 A documentation article is server-rendered, then decorated by JavaScript

The HTML is complete on arrival: `ArticlesController#show` renders the Markdown to HTML on the server
(`app/controllers/public/api/v1/portals/articles_controller.rb:24-27,109-111`) and the ERB layout wraps it
(`app/views/layouts/portal.html+documentation.erb:1-27`). There is no client-side rendering of the article body, so a crawler that never runs
JavaScript sees the whole article. Four things are **added after load** by `app/javascript/portal/portalHelpers.js`, which Turbo runs on every
`turbo:load` (`app/javascript/entrypoints/portal.js:6-9`):

| Added by JavaScript | Evidence | Consequence |
|---|---|---|
| Heading `id`s, `#` permalinks and the table of contents | `portalHelpers.js:14-37,100-115` | The server HTML has `<h2>` with no `id` (measured, section 2.1). The TOC `<aside>` is an empty `#cw-hc-toc` div (`articles/show.html+documentation.erb:31-33`). |
| `<html dir>` | `portalHelpers.js:153-162`; layout sets `lang` only (`portal.html+documentation.erb:2`, `portal_helper.rb:40-42`) | Tailwind's `ltr:`/`rtl:` variants compile to `:where([dir=ltr],[dir=ltr] *)` / `:where([dir=rtl],...)` (found in the built CSS), so **no direction-dependent rule applies until JavaScript runs**, in either language. |
| Search box, theme toggle | `portalHelpers.js:80-98,117-128` | Empty mount points (`#search-wrap`, `#sidebar-theme-toggle`) in the topbar until hydrated. |
| External links get `target=_blank` | `portalHelpers.js:39-67` | Not a rendering concern. |

### 1.2 What a public article page loads

Head (`app/views/layouts/_portal_head.html.erb`): `vite_javascript_tag 'portal'` (`:7`), which in `vite_rails` 3.10.0 emits a `type=module` script,
`modulepreload` links for every static import, **and a blocking `<link rel=stylesheet media=screen>`**
(`vendor/bundle/ruby/3.4.0/gems/vite_rails-3.10.0/lib/vite_rails/tag_helpers.rb:38-55`). Also in `<head>`: an inline `<style>` (`:8-14`),
`csrf_meta_tags` (`:15`), optional analytics (`:27`), and two tiny synchronous inline scripts for the theme (`:32,:35-44`). The body ends with a
view-tracking snippet, a second inline `<style>`, `window.portalConfig`, and the web-widget script only if the portal has a widget channel
(`app/views/layouts/_portal_scripts.html.erb:1-102`).

The `portal` entry (`app/javascript/entrypoints/portal.js:1-9`) imports `@rails/ujs`, Turbo, Vue, `vue-dompurify-html`/DOMPurify and the search, TOC
and theme components. Measured from this checkout's build (`public/vite/.vite/manifest.json`, built 2026-10-12 19:04; **not necessarily the
production build**), gzip level 6 computed by me:

| Asset | Raw | Gzip | Notes |
|---|---|---|---|
| `portal-CBxJHZUk.css` (render-blocking) | 1,528,642 B | 144,429 B | 4,557 rule blocks; **2,215 `url(data:` occurrences = 921,966 B** (icon masks) |
| `portal-xOOm_QWC.js` entry | 158,156 B | 46,980 B | |
| `purify.es` | 202,757 B | 75,988 B | modulepreloaded, pulled in by the search/TOC `v-dompurify-html` |
| `vue-dompurify-html` | 108,776 B | 47,357 B | |
| `utils.esm` | 72,544 B | 27,066 B | |
| five small chunks (`module`, `Icon`, `useKeyboardNavigableList`, `colorHelper`, `HTMLSanitizer`) | 24,633 B | 11,200 B | |
| **JS total, 9 modules** | **566,866 B** | **208,591 B** | all 8 imports `modulepreload`ed |
| `InterVariable.woff2` | 345,588 B | (already compressed) | fetched whenever Latin text renders |
| `InterVariable-Italic.woff2` | 380,904 B | | fetched only if italic text renders |
| 9 x `InterDisplay-*.woff2` | 105,568-110,304 B each | | declared in the CSS; the documentation layout uses `font-inter` only (`portal.html+documentation.erb:6`); `font-default`/`InterDisplay` appear only in the classic and plain layouts |

The CSS is the whole product's stylesheet, not the portal's: Tailwind's `content` globs scan the dashboard, widget, v3, super-admin, survey and shared
trees (`tailwind.config.js:24-38`) and `iconsPlugin` generates a data-URI class for every icon any of them names (`tailwind.config.js:311-312`;
`app/javascript/portal/application.scss:2-9`). The built CSS carries 347 `i-ri-*`, 279 `i-lucide-*`, 57 `i-woot-*` and 55 `i-ph-*` classes.

### 1.3 Fonts

Self-hosted woff2, no third-party font request: `app/javascript/shared/assets/fonts/inter.scss:1-16` (variable, `font-display: swap`) and
`.../InterDisplay/inter-display.scss`. No `<link rel=preload as=font>` anywhere in the head, no `unicode-range` subsetting, no fallback
metric-override (`size-adjust`). The stack is `Inter` then the system fonts (`tailwind.config.js:10-19,41-45`). Inter's published coverage is Latin,
Greek and Cyrillic (not re-verified here), so on Arabic pages the 345 KB file serves only the Latin glyphs and the Arabic text falls through to a
system font.

### 1.4 Caching and delivery

| Response | Header the app sets | Evidence |
|---|---|---|
| Portal HTML (`/hc/...`) | none explicit. Rails' default for a dynamic response, `Cache-Control: max-age=0, private, must-revalidate`, plus a weak ETag from the default Rack stack (no `Rack::ETag` removal found) | No `expires_in`, `fresh_when`, `stale?` in any portals controller or `PublicController` (`grep` over `app/controllers/public*`, `custom/`, `lib/`); `articles_controller.rb:43` is the only `expires_in`, on the tracking pixel |
| `/vite/assets/*` (hashed) | `public, max-age=31536000` | `config/environments/production.rb:23-26` (`RAILS_SERVE_STATIC_FILES` defaults to true, so Puma serves it) |
| Tracking pixel | `private, max-age=86400` | `articles_controller.rb:43` |
| `/rails/active_storage/{blobs,representations}/redirect/...` | `max-age=300, private`, then a 302 | `activestorage-7.2.3.2/app/controllers/active_storage/blobs/redirect_controller.rb:13`, `.../representations/redirect_controller.rb:11` |
| `/rails/active_storage/{blobs,representations}/proxy/...` | `max-age=3155695200, public` (100 years), answers conditional requests with 304, no session cookie | `.../proxy_controller.rb:18` and `.../representations/proxy_controller.rb:14` (`http_cache_forever public: true`; `ActionController::ConditionalGet#http_cache_forever`) |
| `/rails/active_storage/disk/...` (the final hop for the Disk service) | none from the app; headers come from `Rack::Files` | `.../concerns/active_storage/file_server.rb:7-18` |

`deployment/nginx_chatwoot.conf:23-63` is a bare `proxy_pass` with `http2`, HSTS and TLS settings; it has **no `gzip`/`brotli`, no `proxy_cache`, no
`location` for `/vite/` or `/rails/active_storage/`**. `config/` has no `Rack::Deflater` and no `.gz`/`.br` siblings exist in this checkout's
`public/vite/assets`. Whether production compresses CSS/JS is therefore decided by an nginx `http {}` block that is not in the repository: unverified.
`ASSET_CDN_HOST` is honoured for Rails assets (`production.rb:36-37`) but does not apply to Active Storage routes. `x_sendfile_header` is commented out
(`production.rb:39-40`), so every file byte, including Disk-service images, streams through Puma, which defaults to 5 threads and `WEB_CONCURRENCY=0`
(`config/puma.rb:7-9,28`). `config/environments/production.rb:56` leaves `cache_store` unset.

### 1.5 The Markdown renderer's image path (the "server-side `setImageSizing`")

`setImageSizing` lives in `app/javascript/shared/helpers/MessageFormatter.js:5-24` and serves chat messages. Its server-side counterparts are:

- `BaseMarkdownRenderer#image` (`lib/base_markdown_renderer.rb:4-9,23-32`) for **messages**, which reads `cw_image_width`/`cw_image_height` from the URL.
- **`CustomMarkdownRenderer#image` (`lib/custom_markdown_renderer.rb:61-71`) for articles**, the only one that matters here. It reads `cw_image_width` only
  (`:130-146`, `\A\d+px\z`, 1..2000) and writes an inline `style`. It is reached from exactly one call site,
  `ChatwootMarkdownRenderer#render_article` (`lib/chatwoot_markdown_renderer.rb:13-19`), called only by `ArticlesController#show`. That site serves every Help Center
  portal, not only the platform documentation one, so a change to `image` reaches tenant portals too.

Raw HTML is **not** a way around it: the renderer is built with default options, `:UNSAFE` is never set, and CommonMarker 0.23.12's
`html`/`inline_html` emit `<!-- raw HTML omitted -->`
(`vendor/bundle/ruby/3.4.0/gems/commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb`, `#html`, `#inline_html`). Agent 065 and the updated
`01-current-system.md` reached the same conclusion independently. So `<figure>`, `<picture>`, `srcset` and `width`/`height` **cannot be authored in
Markdown**; they can only come from the renderer.

### 1.6 Active Storage and libvips

- Variant processor is `:vips`: `config.load_defaults 7.0` (`config/application.rb:39`) sets it
  (`railties-7.2.3.2/lib/rails/application/configuration.rb:254`). `image_processing` is in the Gemfile (`Gemfile:59`), `ruby-vips` is 2.3.0 (`Gemfile.lock:843`).
- Rails 7.2.3.2's Active Storage **refuses to load** unless libvips >= 8.13 and ruby-vips >= 2.2.1, and then calls `Vips.block_untrusted(true)`
  (`activestorage-7.2.3.2/lib/active_storage/vips.rb:33-41`). `deployment/deploy.sh:247-263` (stage 4b) checks exactly that: it prints
  `Vips.version(0..2)` and `Vips::VERSION` and fails the deploy before any migration. It does **not** check that the host can *encode* any format.
- The Docker image installs `vips` and `imagemagick` in the final stage and sets `VIPS_BLOCK_UNTRUSTED=1` (`docker/Dockerfile:123-134`).
- Existing variant users are three call sites that all ask for `resize_to_fill: [250, nil]` with default output: `app/models/concerns/avatarable.rb:16`,
  `app/models/attachment.rb:71`, `app/controllers/slack_uploads_controller.rb:22`. So the libvips *transform* path runs in production, but **never with
  `format: :webp`, never with `saver:`, never via a proxy route.**
- Defaults that matter for public images: `resolve_model_to_route` is `:rails_storage_redirect` (`activestorage-7.2.3.2/lib/active_storage/engine.rb:99`);
  `image/webp` and `image/avif` are allowed inline (`:67-78`); `image/svg+xml` is on the serve-as-binary list (`:56-65`); a representation is generated
  **inline in the request that first asks for it** (`.../representations/base_controller.rb:13-15`, `.processed`); `variation.key` is a signed, deterministic
  string (`.../models/active_storage/variation.rb:41-43,75-77`), so variant URLs cannot be forged to request arbitrary sizes.
- Analysis (which is what records `width`/`height`) is triggered only by an **attachment** being created
  (`.../models/active_storage/attachment.rb:36,126-127`). Agent 068 reports that the editor's upload endpoint creates an ownerless blob
  (`ActiveStorage::Blob.create_and_upload!` with no `attach`, `upload_controller.rb:39-45` per `068-media-authoring-ux.md` section 1.3). An ownerless blob is
  never analysed, so `blob.metadata['width']` is empty unless something calls `blob.analyze` explicitly.
- `Article` declares no attachment at all (`grep has_one_attached|has_many_attached app/models/article.rb` is empty); only `Portal` does, for its logo (`app/models/portal.rb:50`). There is no owner an article image
  could be attached to today.
- `saver` is **not** in `ActiveStorage.supported_image_processing_methods` (`activestorage-7.2.3.2/lib/active_storage.rb:66-` list contains `format`,
  `convert`, `resize_to_limit`, `strip`, `thumbnail` but no `saver` or `loader`; the repo never extends it, `grep` over `config app lib custom`), so
  `variant(saver: { Q: 85 })` raises `UnsupportedImageProcessingMethod` until `config/initializers/active_storage.rb` adds it.
- `robots.txt` does not disallow `/rails/` (`app/controllers/robots_controller.rb:17,27-28`), so Active Storage image URLs are crawlable.

### 1.7 Existing images on the portal, and image-related SEO surface

Three `<img>` tags exist in the documentation layout: the topbar logo, which has **no `alt` at all** (`documentation_layout/_topbar.html.erb:12`, sized by
`w-8 h-8` so it does not shift); the author avatar (`_user_avatar.html.erb:15`, `alt` = name, sized by classes); the footer brand mark
(`_footer.html.erb:31`, alt = brand). The corpus has **zero** images (`grep -rn '!\[' custom/db/documentation custom/db/changelog` is empty; also the
`068` introduction). `og:image` exists only if `OG_IMAGE_CDN_URL` is configured (`app/helpers/portal_helper.rb:3-18`;
`documentation_layout/articles/_meta_head.html.erb:49-61`), and the production value is unverified (075 flagged the same). The `TechArticle` JSON-LD has no
`image` (`custom/app/helpers/documentation_helper.rb:83-97`). The sitemap has no image entries (`sitemap.xml.erb:13-26`).

### 1.8 Layout geometry (needed for `sizes`)

Container `max-w-screen-2xl` = 1536 px (`portal.html+documentation.erb:13`; `tailwind.config.js` screens). Sidebar in flow from `md`: `md:w-64` (256 px),
`lg:w-72` (288 px) (`_sidebar.html.erb:15`). Article wrapper `px-6 md:px-10`, `flex gap-10`, TOC `w-56` (224 px) from `lg`
(`articles/show.html+documentation.erb:8-9,31`). The prose container is `max-w-none` (`articles/_content.html.erb:6-7`). So the image column is
`100vw - 48 px` below 768 px; `100vw - 336 px` at 768-1023; `100vw - 632 px` at 1024-1535; and a fixed **904 px** from 1536 px up.

## 2. Measured behaviour

### 2.1 What `CustomMarkdownRenderer` emits today

Run: the repository's own `lib/markdown_renderer_url_sanitizer.rb` and `lib/custom_markdown_renderer.rb` against the vendored CommonMarker 0.23.12, via a
standalone script in the scratchpad (no Rails boot, no database; Ruby 3.4.4), with `CommonMarker.render_doc(md, :DEFAULT, [:table])` exactly as
`chatwoot_markdown_renderer.rb:13-19` does.

| Markdown | Output (exact) |
|---|---|
| `![Inbox settings screen](https://example.com/a.png)` | `<p><img src="https://example.com/a.png" alt="Inbox settings screen" /></p>` |
| same, with title `"Settings"` | `<p><img src="..." alt="Inbox settings screen" title="Settings" /></p>` (the title becomes a tooltip, not a caption) |
| `![x](...?cw_image_width=400px)` | `<p><img src="...?cw_image_width=400px" alt="x" style="width: 400px; max-width: 100%; height: auto;" /></p>` |
| `![](https://example.com/a.png)` | `<p><img src="..." alt="" /></p>` (empty alt accepted silently) |
| `![x^2^ chart](...)` | `<p><img src="..." alt="x<sup>2</sup> chart" /></p>` (markup inside the attribute; same as 065 F9) |
| `![**bold** alt](...)` | `alt="bold alt"` |
| `[![Alt](a.png)](big.png)` | `<p><a href="big.png"><img src="a.png" alt="Alt" /></a></p>` |
| `<figure><img src=... width=800 height=450 loading=lazy><figcaption>Cap</figcaption></figure>` | `<!-- raw HTML omitted -->` |
| `<picture><source srcset=...><img src=...></picture>` | `<p>` containing four `<!-- raw HTML omitted -->` |
| `Text <img src="a.png" width="10"> more` | `<p>Text <!-- raw HTML omitted --> more</p>` |
| `## Connect your number` | `<h2>Connect your number</h2>` (no `id`) |

So today an image has **no** `loading`, `decoding`, `width`, `height`, `srcset`, `sizes`, `fetchpriority`; it is wrapped in `<p>` (the `plain do` block in
`image` governs how the *alt children* are rendered, not the wrapper); the one sizing mechanism, `style="width: Npx; height: auto"`, **does not reserve
space**, because the browser has no intrinsic ratio until the file arrives. Every image would therefore shift the layout when it loads.

### 2.2 What the built CSS already supplies for figures

The compiled portal CSS contains the Typography plugin's `.prose :where(figure)` (2em vertical margin), `.prose :where(figure>*)` (0 margin),
`.prose :where(figcaption)` (0.875em, `--tw-prose-captions`, 0.857em top margin) and `.prose :where(picture)`, and Tailwind preflight's
`img,video{max-width:100%;height:auto}` plus `img{display:block}`. `dark:prose-invert` is already on the container
(`articles/_content.html.erb:7`). So `width`/`height` attributes will map to an aspect ratio with no extra CSS, and `<figure>`/`<figcaption>` need no new
CSS. **Trap:** Tailwind's `content` globs include `./app/views/**/*.erb` but not `lib/**` or `custom/**` (`tailwind.config.js:24-38`), so a utility class
emitted from the Ruby renderer would not be generated. The renderer must emit bare elements; styling lives in `_content.html.erb` using `prose-img:*` and
`[&_figure]:*` variants, which is also what CLAUDE.md requires (Tailwind only).

### 2.3 Image encoding on real screenshots

The repository holds 814 product screenshots under `docs/**/screenshots/` (engineering evidence, not yet corpus images; the best available proxy for what
authors will upload), 498 of them at least 1200 px wide. I re-encoded in memory with libvips 8.15.1 / ruby-vips 2.3.0 (nothing written to the repo; the sandbox is
Ubuntu 24.04, **not** production). Main sample: 24 desktop-width PNGs spread evenly through the sorted list (8 at 1440 px, 16 at 1280 px, heights 900-1500),
each resized with `thumbnail_image` to the recommended ladder and saved as WebP `Q: 85, smart_subsample: true, effort: 4`.

| Variant | Median | Mean | p90 | Max |
|---|---|---|---|---|
| Source PNG | 94.7 KB | 125.0 KB | 278.7 KB | 349.4 KB |
| WebP 800 px | 14.9 KB | 16.9 KB | 33.3 KB | 36.7 KB |
| **WebP 1200 px** | **30.1 KB** | **32.0 KB** | **64.3 KB** | **77.2 KB** |
| WebP 1800 px (sources are <= 1440 px, so this is the unscaled size, not an upscale) | 32.8 KB | 39.7 KB | 84.4 KB | 106.2 KB |

Per file the 1200 px WebP is about 2-17x smaller than its source PNG (median about 2.6x), part of which is the downscale from 1280-1440 px. A true 1800 px variant of a
2x retina capture will be heavier than the last row; I had no such source in the sample. An earlier 16-file sample, 11 of whose files were 390 px phone captures and
which therefore understates desktop sizes, gave a Q85 1280 px median of 19.4 KB (max 58.2 KB) and showed that **lossless WebP after a resize was larger than the source PNG
on 2 of 16 files** (388.6 KB against 151.0 KB at worst).

Format comparison at 1280 px on three desktop files (source PNG / WebP Q85 / WebP Q85 with `smart_subsample` / WebP Q90 + `smart_subsample` / near-lossless Q60 / JPEG Q85):
278.7 / 33.4 / 35.1 / 42.3 / 179.8 / 71.5 KB; 350.7 / 56.9 / 61.8 / 73.9 / 244.9 / 96.9 KB; 151.0 / 47.0 / 49.9 / 65.2 / 266.8 / 99.3 KB. Lossy WebP is about half the size of
JPEG, `smart_subsample` costs 5-9%, and **lossless and near-lossless WebP are the wrong default for resized screenshots**. I compared one crop of
`flow-06-test-handoff.png` (resized original against Q85 + `smart_subsample`) by eye: UI text and the pink-on-dark "Settings" label were indistinguishable at 1x. That is one
crop on one image; a human check of five representative screenshots (including an Arabic RTL one and a dense table) is needed before the quality setting is frozen.
Processing cost in the sandbox was 79-1,227 ms per source image for decode plus four encodes at `effort: 2`: not a production number, but enough to show it must not run on a
visitor's request.

### 2.4 What this libvips build can and cannot encode

`vips_probe.rb` in the scratchpad against the sandbox's system libvips: `webpsave`, `webpsave_buffer`, `heifsave`, `heifsave_buffer`, `jxlsave_buffer`,
`jpegsave_buffer`, `pngsave_buffer` all exist (`Vips.type_find` non-zero). A WebP encode succeeded (276 B for a 64x64 image). **An AVIF encode failed
with `heifsave: Unsupported compression`**, although `heifsave` is present, because the installed libheif ships only the decoder plugin
(`libheif-plugin-aomdec`, libheif 1.17.6; no AV1 encoder plugin is installed). This is the sandbox, not the production host, but it demonstrates the trap: an
operation-exists check passes while the encode fails. Stage 4b in `deploy.sh` would pass this host as well.

### 2.5 What I could not measure

LCP, CLS and INP on any page; whether production compresses and with what; whether the CSS/JS in production matches this checkout's build; the actual
response headers (see 5.9); the production `ACTIVE_STORAGE_SERVICE` (default `local` per `production.rb:43`); whether a CDN or nginx cache fronts
`/rails/active_storage/`; the codecs on the production libvips; whether `OG_IMAGE_CDN_URL` is set; Arabic pre-hydration layout shift.

## 3. Defects

Severity is what it costs a reader or crawler once images exist, not what it costs today.

| # | Sev | Defect | Evidence | Impact |
|---|---|---|---|---|
| D1 | blocker | The article image renderer emits no `width`/`height`, no `loading`, no `decoding`, no `srcset`, no figure, and wraps images in `<p>`; its only sizing path does not reserve space | `lib/custom_markdown_renderer.rb:61-71`; measured 2.1 | Every image causes layout shift on load, with no lazy loading and a full-size download on every viewport. This is the CWV cost of shipping the program's first image. |
| D2 | blocker | Public images served through Active Storage's default routes are neither cacheable nor stable: redirect routes are `private, max-age=300`; the Disk final URL carries an expiring signature that changes on every redirect (and an S3 presigned URL behaves the same way, from general knowledge: the S3 service code was not read here), so the browser's cache entry is never reused; the Disk response has no `Cache-Control` | `redirect_controller.rb:13`; `disk_service.rb:164-175`; `file_server.rb:7-18`; `engine.rb:99` | Each page view after five minutes re-downloads every image, doubles the request count (302 then bytes), and gives Google Images an unstable final URL. |
| D3 | blocker | Variants are generated inline on first request, by whichever visitor or crawler arrives first; an ownerless blob (the editor's current upload shape) is never analysed, so no width/height exists; and `saver` is not on the allowlist | `representations/base_controller.rb:13-15`; `attachment.rb:36,126-127`; `068` section 1.3; `active_storage.rb:66-` | Each of N x 3 first requests runs libvips inside a Puma request thread (5 by default), and concurrent first requests for the same variant each process it. The renderer also has no dimensions to emit. |
| D4 | major | Alt text is not enforced anywhere: `![](x)` renders `alt=""`; `^` in alt injects `<sup>`; the title is a tooltip rather than a caption; the existing topbar logo has no `alt` | `custom_markdown_renderer.rb:43-52,61-71`; `_topbar.html.erb:12`; measured 2.1; `065` F9 | Screenshots are the content of a how-to page. Without alt they are invisible to screen readers, to Google Images, and to the "Open in Claude/ChatGPT" actions, which hand a model the raw Markdown (`documentation_layout/articles/_actions.html.erb:3-6`, `articles_controller.rb:29-33`). |
| D5 | major | The portal stylesheet is the entire product's CSS (1.53 MB raw, 144 KB gzip, 922 KB of it data-URI icons) and is render-blocking on every page | `_portal_head.html.erb:7`; `tag_helpers.rb:52`; `tailwind.config.js:24-38,311-312`; section 1.2 | Paid on every first view, before any text paints. Unmeasured, but a 1.5 MB stylesheet is the dominant fixed cost of this page and images are added on top of it. |
| D6 | major | Direction is applied only by JavaScript; the server sends `<html lang>` with no `dir`, and `ltr:`/`rtl:` rules require `[dir]` | `portalHelpers.js:153-162`; `portal.html+documentation.erb:2`; built CSS | About half the corpus is Arabic (63 EN + 63 AR). The first paint is unstyled for direction and the layout, including figure alignment and the caption's side, changes once the module runs. Layout shift on the Arabic locale is likely; **unmeasured**. Overlaps agent 072. |
| D7 | major | Portal HTML cannot be conditionally cached or shared-cached: `csrf_meta_tags` puts a per-request masked token in every page and starts a session; no `expires_in`/`fresh_when` anywhere | `_portal_head.html.erb:15`; `public_controller.rb:3-5` (forgery protection is skipped, but the meta tag is rendered whenever protection is enabled by `load_defaults`, `config/application.rb:39`); section 1.4 | **Inference from framework behaviour, not observed**: the ETag changes on every response so a 304 never happens, and any CDN honouring `Set-Cookie` will not cache the page. Every crawl is a full render. |
| D8 | major | `show` re-renders Markdown on every request with no fragment cache, and the sidebar loads every published article of the portal **with its `content` column** on every page | `articles_controller.rb:26`; `documentation_layout/_sidebar.html.erb:8-11` (`portal.articles.published.where(category_id: ...)`, no `select`) | The English corpus is 346,513 B of Markdown across 63 files (`wc -c custom/db/documentation/en/*/*.md`), so roughly 346 KB is read from Postgres and discarded per page view today. Longer, image-bearing articles raise it. |
| D9 | major | Fonts: a 345 KB un-subset variable font, `swap`, no preload, no metric-matched fallback; Arabic text never uses it | `inter.scss:1-16`; `_portal_head.html.erb` (no preload); section 1.3 | Late text re-flow on every first view and a 345 KB download that on Arabic pages renders a handful of Latin glyphs. |
| D10 | major | The libvips precondition checks the version, not encode capability, and the repo's variant code has never produced WebP | `deploy.sh:260-263`; section 1.6; measured 2.4 | A host can pass stage 4b and then 500 on every image URL after restart. AVIF in particular fails on a stock Ubuntu libvips. |
| D11 | minor | `turbo:load` re-runs `initialize`, which adds a new `document` click listener each navigation (external-link handler, details click-away) and a `change` listener (locale switcher); none is removed | `portal.js:9`; `portalHelpers.js:44,71,131,166-179` | Listeners accumulate across Turbo navigations in one session; small per-click cost that grows with reading depth. INP not measured. |
| D12 | minor | Amplitude loads as a synchronous `<script src>` in `<head>`; every other analytics tag is async/defer. Only if a portal configures it | `_portal_analytics.html.erb:44-48` | Render-blocking third party on that portal. |
| D13 | minor | Heading `id`s are JS-only and repeated headings get the same id: the library's default export (plain `slugify`) is imported under the name `slugifyWithCounter` and called per heading, so there is no counter | `portalHelpers.js:7,14-37`; `node_modules/@sindresorhus/slugify/index.js:42,100` | No server-side fragment anchors for crawlers; duplicate ids on pages with repeated headings; Arabic slugs unverified. Overlaps 073/076. |
| D14 | minor | Two nested `<main>` landmarks; two viewport meta tags (the first lacks `width=device-width`) | `portal.html+documentation.erb:9,16`; `_portal_head.html.erb:2,4` | Landmark and validity noise for assistive tech. |
| D15 | minor | `show_markdown` returns raw `@article.content`; images will be relative or absolute-redirect URLs the consumer cannot always resolve | `articles_controller.rb:29-33` | The AI-assistant actions will see `![alt](/rails/...)` with an unresolvable relative path. Alt text is all they get. |
| D16 | minor | SVG cannot be an `<img>` through Active Storage: it is served as binary, and libvips runs with untrusted loaders blocked | `engine.rb:56-65`; `vips.rb:41`; `Dockerfile:134` | Diagrams must be raster for now. Agent 084 owns the policy. |
| D17 | minor | No OG image unless an external CDN is configured; `TechArticle` has no `image`; no image sitemap | `portal_helper.rb:3-18`; `documentation_helper.rb:83-97`; `sitemap.xml.erb:13-26` | Link previews and rich results will not use the new screenshots by themselves. |

## 4. What a larger corpus breaks

Assume 5x the corpus (about 315 EN articles per locale) with a mean of three images each.

- **Sidebar HTML and DOM.** Every page lists every article of its locale (`_sidebar.html.erb:30-70`); each link is roughly 0.45 KB of markup because of the repeated
  class strings (estimated from the template text, not measured). That is about 28 KB per page now and about 140 KB per page at 5x, plus roughly 900 more DOM
  nodes, on a page whose gzip budget is otherwise dominated by 350 KB of CSS and JS.
- **Database and Ruby memory.** D8 scales linearly: about 1.7 MB of Markdown loaded per page view at 5x, to render 315 link titles.
- **Variant volume.** 315 articles x 3 images x 2 locales x 3 widths = about 5,700 variants (Arabic screenshots are separate files in the repository's
  own screenshot set, `ar-*.png`). At the sandbox's 0.1-0.3 s per encode that is on the order of 10-30 CPU-minutes in total, which is trivial in a
  background job and an outage if it happens on request threads or in the deploy path.
- **Crawl.** A new article published with N unprocessed variants gets its first Googlebot visit on the slowest possible path (D3). With the default redirect
  routes (D2) the same crawler follows N 302s to expiring URLs on every revisit.
- **Image bytes.** At the measured 1200 px Q85 median of 30 KB and roughly 12 images in a long procedure, an article's images are about 360 KB; if every image were as heavy as the
  heaviest sample (77 KB) about 925 KB. Without width/height/lazy loading all of it competes with the 1.5 MB stylesheet and 345 KB font for the same connection.
- **Search page and categories** list articles with no images, so they are unaffected unless an excerpt starts to render Markdown.

## 5. Recommendations

Everything below extends something that already exists (renderer, Active Storage, `seo_audit`, `_content.html.erb`); none adds a media system.

### 5.1 The markup the renderer must emit

For a paragraph whose only child is an image, replace `<p><img></p>` with:

```html
<figure>
  <img src="/rails/active_storage/representations/proxy/<signed_id>/<key-1200>/<name>.webp"
       srcset="/rails/.../<key-800>/<name>.webp 800w, /rails/.../<key-1200>/<name>.webp 1200w, /rails/.../<key-1800>/<name>.webp 1800w"
       sizes="(min-width: 1536px) 904px, (min-width: 1024px) calc(100vw - 632px), (min-width: 768px) calc(100vw - 336px), calc(100vw - 48px)"
       width="1200" height="750" alt="Inbox settings with the WhatsApp channel selected" loading="lazy" decoding="async">
  <figcaption>The WhatsApp channel tile in Settings, Inboxes.</figcaption>
</figure>
```

| Attribute | Rule | Why |
|---|---|---|
| `alt` | Always present, plain text, built from the image node's text children (so `^` is not turned into `<sup>`), never empty | SEO and accessibility; fixes D4 |
| `width`, `height` | Pixel size of the `src` variant (`W' = min(W0, 1200)`, `H' = round(H0 * W' / W0)`) | The browser derives the aspect ratio before the file arrives: zero shift. Preflight's `height:auto` keeps it responsive. |
| `loading` | `lazy` on every image except the first in the article | Standard deferral for below-the-fold content |
| first image | `loading` omitted (eager) and `fetchpriority="high"` | It is the likeliest LCP element on a phone, because the header above it is short. Drop `fetchpriority` if field data later shows the h1 is the LCP. **Unverified**: no LCP data exists. |
| `decoding` | `async` on all | Keeps decode off the main thread |
| `srcset`/`sizes` | Only for Active Storage blobs; list only widths `<=` the source width; if the source is narrower than 800 px, emit `src` alone | No upscaling; `sizes` is derived from the layout in 1.8. Keep the numbers in one constant with a comment pointing at the three template lines they depend on. |
| `<figcaption>` | From the CommonMark image title; then **omit `title=`** from the `<img>` | The title is already a free, locale-specific caption slot; emitting both makes screen readers announce it twice. |
| `cw_image_width=Npx` | Keep (editor drag-resize). Emit `width`/`height` from the intrinsic size and keep `style="width:Npx;max-width:100%;height:auto"`; `sizes="min(Npx, calc(100vw - 48px))"` | The ratio still comes from the attributes, so the resize no longer causes shift. |

Implementation sketch, `lib/custom_markdown_renderer.rb` (roughly 35 lines including the `paragraph` override): a `paragraph(node)` override that detects
a sole-image paragraph and calls a figure path (otherwise `super`); `image(node)` builds attributes from the Active Storage descriptor when the URL matches
`/rails/active_storage/blobs/(redirect|proxy)/<signed_id>/<filename>`, and falls back to a plain `<img>` with `loading`, `decoding` and `alt` for any other URL.
Track `@image_index` on the renderer instance (one instance per render, `chatwoot_markdown_renderer.rb:14`) for the first-image rule. Tight list items get
no `<p>` from CommonMarker (`html_renderer.rb`, `#paragraph`), so the override must not rely on a `<p>` existing: a screenshot under a numbered step is the
common case.

Where width/height come from. Two options, with a recommendation:

| Option | How | Trade-off |
|---|---|---|
| **A. Server lookup (recommended)** | The renderer parses `signed_id` out of the URL, collects all of an article's ids, does one `ActiveStorage::Blob` query, and reads `metadata['width'|'height']` | Markdown stays plain `![alt](url "caption")`, stays portable (raw `.md`, the editor's existing `file_url`), no editor change, no stale values (a blob is immutable). Needs the blob to be analysed (5.2) and the output cached (5.6). |
| B. Dimensions in the URL | The editor writes `?cw_w=..&cw_h=..` beside `cw_image_width` | No query at render time, but needs a change to the pinned `@chatwoot/prosemirror-schema` package and every seeded `.md` file to carry hand-written numbers. |

Blast radius: the renderer serves tenant Help Center portals as well. `loading`, `decoding`, `alt`, `width`/`height` and the figure are safe everywhere. Gate the
proxy-URL `srcset` on the documentation layout (`@portal_layout == 'documentation'` is already known in the controller, `base_controller.rb:22-24`), by passing an option
from `render_article_content`, so tenant portals keep their current serving path.

### 5.2 Variants, format and the libvips constraint

| Decision | Recommendation | Evidence |
|---|---|---|
| Output format | **WebP only**, lossy, `Q: 85`, `smart_subsample: true`. No AVIF, no JPEG/PNG fallback `<picture>`. | Measured 2.3: about 2-17x smaller than the source PNG at 1200 px (median 2.6x), about half of JPEG Q85, text legible in the one crop I checked; AVIF encode is absent on a stock Ubuntu libvips (2.4) and the gain on flat UI screenshots is not worth a codec-availability dependency. Lossless/near-lossless is larger than the PNG on some inputs. WebP browser coverage is from memory, not re-checked. |
| Width ladder | 800, 1200, 1800; `src` = 1200 | Column widths 327-904 CSS px (1.8) at DPR 1-3 need roughly 650-1,800 px; the ladder serves a phone at DPR 2 from 800, a laptop from 800-1800, and a 1536+ desktop at DPR 2 from 1800. The 1800 size was measured only on sources <= 1440 px wide (2.3). |
| How | `blob.variant(resize_to_limit: [w, nil], format: :webp, saver: { Q: 85, smart_subsample: true })`, i.e. `resize_to_limit` never upscales | `variation.rb`; `image_processing` forwards `saver` options to the libvips saver (option names to be confirmed in a spec when implemented) |
| Allowlist | Add `saver` to `config.active_storage.supported_image_processing_methods` in `config/initializers/active_storage.rb` | D3: absent from `active_storage.rb:66-` |
| When | **Never on a visitor's request.** Declare the widths as named variants with `preprocessed: true` on whichever attachment owns the image (fires `transform_variants_later`, `attachment.rb:36`), or enqueue `ActiveStorage::TransformJob` per width at upload | D3. This depends on program decision 3 (below). |
| Dimensions | The upload path must produce `width`/`height`: attaching the blob to an owner triggers `analyze_later` (`attachment.rb:126-127`); an ownerless blob needs an explicit `blob.analyze` | An ownerless blob has no dimensions (1.6) |
| URL form | Variants through the **proxy** route, `rails_blob_representation_proxy` (`activestorage-7.2.3.2/config/routes.rb:10`), not the redirect route; do **not** flip `resolve_model_to_route` globally | Stable URL, `public, max-age` of 100 years, no session cookie, one request instead of two, crawlable. Flipping the global route would change avatars, logos and chat attachments. |
| Input policy | Accept PNG, JPEG, WebP (GIF discouraged: animated GIFs are not variant-friendly); no SVG | D16. Which other loaders `block_untrusted` refuses is **not checked here**; test PNG, JPEG, WebP and a TIFF/HEIC upload on the real host. |
| Filenames | Slugify to a descriptive, locale-appropriate name at upload (`connect-whatsapp-embedded-signup-en`), not `Screenshot 2026-10-12 at 11.04.png`; the variant filename segment must end `.webp` | The last URL segment is the filename Google sees |

The proxy route streams through Puma (no `x_sendfile`, 5 threads by default, 1.4). That is no worse than the redirect route on the default `local`
Disk service, where the final hop is also served by Puma, but it **is** worse on S3 or GCS, where redirect hands the bytes to the bucket. Because the response
carries `public, max-age=3155695200` and no cookie, the fix for both is an `nginx` `proxy_cache` for `/rails/active_storage/representations/proxy/` (or any CDN in front),
which is a deployment-stream change. Which storage service production uses and whether a cache sits in front are unverified, and decide whether proxy is
acceptable (agents 066/083).

**libvips and the deploy.** Stage 4b stays as it is (it is a hard boot precondition, `deploy.sh:247-263`) and gains one assertion that the host can *encode*
the format the portal depends on: a 1x1 in-memory `webpsave_buffer`, not `Vips.type_find`, because the AVIF case in 2.4 shows that an operation can exist and
still fail. Failing stage 4b costs one unused backup; failing at the first image costs a published portal with broken images. Also record, for the deployment
agents (097): `deployment/setup_20.04.sh:231,889` installs libvips through `apt`, and the packaged version on that Ubuntu release is older than 8.13 (from memory,
unverified), so a host built from that script cannot satisfy 4b without a newer libvips.

### 5.3 Budgets

Budgets are my recommendations, derived from the measurements in 2.3 and the layout in 1.8; the CWV thresholds are Google's published ones (from memory).

| Budget | Value | Basis |
|---|---|---|
| Layout shift from images | **0**: every `<img>` in rendered article HTML has non-empty `alt`, `width` and `height` | CLS "good" is <= 0.1; images should contribute nothing |
| Delivered image, 1200 px variant (screenshot) | warn above 100 KB | Measured Q85 median 30 KB, p90 64 KB, max 77 KB (n=24 desktop screenshots, 2.3) |
| Delivered image, 1800 px variant | warn above 180 KB | Measured max 106 KB, but only for sources <= 1440 px; a 2x retina source will be heavier. Re-measure on real uploads. |
| First (above-the-fold) image, delivered | <= 100 KB | About 0.5 s on a 1.6 Mbps link (arithmetic from Lighthouse's published slow-4G profile, quoted from memory) |
| Images per article | warn above 12; at most 2 images in the first viewport | About 360 KB at the measured median, about 925 KB if every image is as heavy as the heaviest sample |
| Source upload | keep the editor's existing 4 MB cap (`FullEditor.vue:40` per 068); warn above 1 MB; longest edge <= 4,000 px; PNG/JPEG/WebP | Measured desktop PNG screenshots: median 95 KB, max 349 KB, so 1 MB flags only photographs and mistakes |
| Alt text | required; <= 125 characters (a convention, not a rule); must not begin "image of"/"screenshot of"/"picture of", equal the filename, or repeat the caption | Writing guidance |
| Page, text-only (targets to re-measure, not measured) | CSS <= 60 KB gzip (now 144), JS <= 150 KB gzip (now 209), no font > 150 KB (now 345) | Reachable by 5.6 steps 1-2; unmeasured |

### 5.4 Alt text as an SEO and accessibility requirement

- **Policy: documentation images are never decorative.** A screenshot in a how-to is information; an empty alt is an **audit error** (5.5), which exits 1 and blocks release, not a style
  choice. This avoids inventing a "decorative" marker in CommonMark, which has none.
- Alt describes what the reader needs from the picture in one sentence (UI state and the label to look for); the steps stay in the prose. The
  caption says what the image is a screenshot **of** and may be shorter; they must differ.
- Alt and caption are written **in the article's own language** and are part of the per-locale file. An Arabic article with English alt is a
  parity defect for 094. Machine translation of alt is not parity either.
- Alt is the only description a model sees through the "Open in ChatGPT/Claude" actions (`_actions.html.erb:3-6`) and the raw `.md` endpoint (D15), and the
  main text signal Google Images has for a screenshot.
- Fix `text`'s `^` handling inside alt (D4) in the renderer, and add `alt` to the topbar logo (`_topbar.html.erb:12`).

### 5.5 Extend `lynomia:docs:seo_audit` (no new tool)

`lib/tasks/documentation_seo_audit.rake` already renders through the real helpers and exits 1 on error. Add, over the rendered HTML of every published
article, with the existing ERROR/WARN levels:

| Check | Level |
|---|---|
| `<img>` with empty or missing `alt` | error |
| `<img>` missing `width` or `height` | error |
| Active Storage image with no `srcset` (documentation portal) | error |
| Referenced blob not analysed or not `image/*` | error |
| alt over 125 chars, begins "image of"/"screenshot of", equals the filename, or equals the caption | warn |
| Source blob over 1 MB (warn) or over 4 MB (error); more than 12 images in one article | warn / error |
| EN article image whose AR sibling has no image, or the reverse | warn (feed 094) |

This is also the gate for the seeded corpus: a Markdown file that references an image without alt fails the same check the editor enforces.

### 5.6 Page-level CWV, in order of value

The image work does not fix these; images add to them. Each is independent.

1. **Portal-only Tailwind content (D5).** Give the `portal` entry its own `@config` (Tailwind 3.4 supports it) whose `content` is the public portal views,
   `app/javascript/portal/**`, `app/helpers/**` and `custom/app/helpers/**` (the helpers emit icon classes). Expected: the 922 KB of data-URI icons for
   dashboard-only icons disappears. Unmeasured; run `public/vite` through the same size script afterwards. Risk: a class built from a database value
   (category icons) must be safelisted.
2. **Fonts (D9).** `preload` the one variable woff2 the documentation layout uses with `crossorigin`; subset it (Latin plus the digits and punctuation the
   Arabic pages need); add a `size-adjust` fallback face. Drop the italic and InterDisplay faces from the portal entry.
3. **Server-side `dir` (D6).** Emit `dir="rtl|ltr"` from the locale in `portal.html+documentation.erb:2`, as the portals already know the locale. Overlaps 072.
4. **Cacheable HTML (D7, D8).** Remove `csrf_meta_tags` from `_portal_head.html.erb:15` (the portal has no non-GET form of its own; confirm), add
   `fresh_when`/`expires_in ... stale-while-revalidate` for published documentation articles, and `Rails.cache.fetch` the rendered article keyed on
   `article.cache_key_with_version` plus a renderer version constant. `select` only the columns the sidebar uses (`id`, `title`, `slug`, `category_id`, `position`) on the sidebar query.
5. **Listener leak (D11).** Register the click/change listeners once, not per `turbo:load`.
6. **Analytics (D12).** Add `async` to the Amplitude script.

### 5.7 Head and structured data once images exist

- `og:image`: if `OG_IMAGE_CDN_URL` is blank, fall back to the article's first image. Use a **JPEG** variant of about 1200 x 630 rather than WebP, because WhatsApp
  link previews are central to this product and I could not verify WebP support there (unverified), and add `og:image:width`, `og:image:height`, `og:image:alt`.
- `TechArticle.image` (075 D5): an array of the proxy URLs of the images **actually in the article**, 1200 px variants. Google's Article guidance on
  image size and format is from memory (a minimum pixel area and WebP supported): confirm before relying on it.
- Image sitemap entries (`<image:image><image:loc>`): optional. Images are discoverable from `<img src>`; add them only if Search Console shows images not
  indexed (unverified).
- No new robots rule: `/rails/` is already crawlable.

### 5.8 Ordering

| Gate | Items |
|---|---|
| **Before the first image is published** | 5.1 renderer, 5.2 allowlist, preprocessed variants, dimensions, proxy URL, stage-4b encode assertion, 5.5 audit checks, `alt` on the logo |
| Phase 5, same release if possible | 5.6 items 3 and 4, 5.7 |
| Later, measured first | 5.6 items 1, 2, 5, 6 |

### 5.9 Verification, for Phase 6 and the adversarial agents

None of these was run by this agent. Each is read-only and belongs to Phase 6 or to the owner, on staging or the owner's own hosts.

1. `curl -sI https://<docs-host>/hc/lynomia-docs/articles/<slug>` twice: compare `ETag`, `Cache-Control`, `Set-Cookie` (confirms or refutes D7).
2. `curl -sI -H 'Accept-Encoding: br, gzip' https://<docs-host>/vite/assets/portal-*.css`: `content-encoding` present or not (1.4).
3. `vips -l | grep -E 'webpsave|heifsave'` and a 1x1 `webpsave_buffer` encode on the **production host and in the Docker image** (2.4); `apk info` for the Alpine `vips`
   split packages (my recollection that the HEIF module is a separate package is unverified).
4. Lighthouse (mobile, EN and AR, one image-bearing article) before and after: LCP element, CLS (AR in particular), total CSS/JS bytes. This is the measurement this report
   lacks.
5. Renderer spec table: the 11 inputs in 2.1 with the new expected output, plus a tight-list step with a screenshot, a linked image, an inline icon, a `cw_image_width` image, and an
   image whose alt contains `^`.
6. Fetch one variant URL twice: `Cache-Control` must be `public, max-age=3155695200`, second request `304`, no `Set-Cookie`.

### 5.10 Dependencies on other agents' decisions

- **Program decision 3 (media ownership model).** The owner must be an Active Storage **attachment**, not an ownerless blob, or analysis and `preprocessed` variants never fire
  (1.6). This directly constrains 066/068/083.
- **068's upload response** returns `url_for(blob)`, an absolute redirect URL. The renderer should rewrite a recognised redirect URL to the proxy representation URL at
  render time, so already-authored Markdown needs no migration.
- **072** for the `dir` attribute; **075** for `TechArticle.image`; **084** for the SVG policy; **087** for screenshot redaction before upload, which is
  an authoring-time control the renderer cannot supply.

Scratchpad scripts used (outside the repository, read-only against it): `render_probe.rb`, `vips_probe.rb`, `shots2.rb`, `shots3.rb`, `crop.rb`.
