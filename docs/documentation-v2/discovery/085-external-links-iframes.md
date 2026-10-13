---
agent: 085
scope: External links, iframes and embeds in documentation articles - what the renderer does today, and the policy for a corpus about to link to hundreds of Meta pages
confidence: high
---

# 085 - External links, iframes and embeds

Method: every renderer claim below was read from source (`lib/`, the installed `commonmarker-0.23.12` and
`railties-7.2.3.2` gems, `config/`, the portal views and JS) and cross-checked against the existing specs. Nothing was
executed (contract section 6.1 forbids it), so where a claim is about browser behaviour rather than repository code
it is marked as such. No external site was fetched: this brief did not authorise it.

The direct answers, before the evidence:

| Question in the brief | Answer |
|---|---|
| Does the article renderer add `target`, `rel="noopener noreferrer"` or `nofollow`? | **No, none of the three.** A link renders as `<a href="..." title="...">` and nothing else (`lib/markdown_renderer_url_sanitizer.rb:6-10`). |
| Does anything add them? | Yes, **in the browser, at click time, and only for off-host links**: `target="_blank"` and `rel="noopener noreferrer"`, never `nofollow` (`app/javascript/portal/portalHelpers.js:60-61`). The chat UI's markdown-it path does the opposite: all three, on every link, at render time (`app/javascript/shared/helpers/MessageFormatter.js:57-63`). |
| Does raw HTML survive the renderer? | **No.** Raw HTML becomes `<!-- raw HTML omitted -->` (`html_renderer.rb:110-126`, `UNSAFE` is off). |
| Is an iframe therefore impossible today? | **No - an iframe is already possible, by a different door.** `config/markdown_embeds.yml` turns a bare link to one of 11 provider patterns into raw template HTML: 8 iframes, 1 `<video>`, and 2 templates (Wistia, GitHub Gist) that emit `<script src>` into the page. |
| Does any CSP constrain frame sources? | **No.** The only CSP is `object-src 'none'` and `base-uri 'self'` (`config/initializers/content_security_policy.rb:14-17`). |
| Does the corpus use any of this today? | **No.** 0 external links, 0 images, 0 raw HTML, 0 embeds in 126 articles (measured, section 1). Every finding is prospective except F10. |
| Are embeds needed? | **No.** Recommendation: none allowed in the platform documentation portals (section 5). |

No blocker was found. Two majors are reachable today by an author who adds an embed (F2, F7), one major is a missing
mechanism (F9), and one major is a live link-integrity defect that is not a security issue (F10).

## 1. Attack surface

| # | Surface | Where it is decided | Who can feed it | In the corpus today |
|---|---|---|---|---|
| S1 | Inline link `[text](url)` | `CustomMarkdownRenderer#link` -> `MarkdownRendererUrlSanitizer#link` (`lib/custom_markdown_renderer.rb:54-59`, `lib/markdown_renderer_url_sanitizer.rb:6-10`) | Super Admin authors; seeded Markdown | 494 per locale, all internal bare slugs; 0 absolute |
| S2 | Image `![alt](url)` | `CustomMarkdownRenderer#image` (`lib/custom_markdown_renderer.rb:61-71`) | same | 0 |
| S3 | Embed link (bare link matching a provider regex) | `render_embedded_content` / `find_matching_embed` (`custom_markdown_renderer.rb:164-209`), templates in `config/markdown_embeds.yml` | same | 0 |
| S4 | Raw HTML block / inline HTML | `CommonMarker::HtmlRenderer#html` / `#inline_html` | same | 0 |
| S5 | Outbound links in portal chrome | `documentation_layout/_footer.html.erb:25-26,42-43`, `_topbar.html.erb:25`, `_actions.html.erb:16,25,33` | developers (templates) | static |
| S6 | Click-time handler | `portalHelpers.js:39-67`, wired at `:167`, run on `turbo:load` (`app/javascript/entrypoints/portal.js:9`) | every reader | n/a |
| S7 | Header and CSP layer | `content_security_policy.rb`, Rails default headers, `base_controller.rb:66-68`, `deployment/nginx_chatwoot.conf:62` | operators | n/a |

The article HTML is emitted unsanitised into the page: `render_as_html_safe` (`lib/chatwoot_markdown_renderer.rb:27-31`)
-> `@parsed_content` (`articles_controller.rb:26`) -> `<%= parsed_content %>` inside `#cw-article-content`
(`app/views/public/api/v1/portals/articles/_content.html.erb:6,18`). There is no second sanitiser pass, so whatever
the renderer emits, including a `<script>` from an embed template, is live in the page. That is why section 2.5
matters more than the link attributes do.

Corpus measurement (126 `.md` under `custom/db/documentation`, plus 2 under `custom/db/changelog`):

| Probe | Result |
|---|---|
| `https?://` occurrences | 12, **all inside backtick code spans** (`commerce-store-address-refused.md:24,33`, `connect-shopify.md:81`, and the AR twins) |
| `](` links | 494 EN + 494 AR; 57 distinct targets each; **0 absolute, 0 `mailto:`, 0 `//`, 0 fragment-only, 0 containing `/`** |
| `![` images | 0 |
| Raw HTML tags (`iframe script img a div span video embed object style details table`) | 0 |
| `javascript:` / `vbscript:` / `data:` | 0 |
| Meta host mentions | exactly one, and it is not a link: `en/whatsapp-errors/whatsapp-error-131042.md:27` says "Open **business.facebook.com**" |

So the corpus does not yet point readers at Meta at all, even where it tells them to go there.

## 2. What the existing defence actually does

### 2.1 Server-side link rendering

`CustomMarkdownRenderer` includes `MarkdownRendererUrlSanitizer` (`custom_markdown_renderer.rb:2`). Its own `link`
(`:54-59`) only checks for an embed and otherwise calls `super`, which resolves to the module's `link`:

```ruby
# lib/markdown_renderer_url_sanitizer.rb:6-10
def link(node)
  out('<a href="', sanitized_href(node.url), '"')
  out(' title="', escape_html(node.title), '"') if node.title.present?
  out('>', :children, '</a>')
end
```

That is the decisive fact: **href and title, nothing else.** The specs pin it as the exact output
(`spec/lib/custom_markdown_renderer_spec.rb:131-138` expects `<a href="https://example.com">`). The module is shared
with `BaseMarkdownRenderer` (`lib/base_markdown_renderer.rb:2`), which renders chat messages and email bodies
(`app/helpers/message_format_helper.rb:13`, `app/helpers/email_helper.rb:10`), so adding attributes in the module would
change those surfaces too.

### 2.2 The client-side handler, and why it is a weaker control than it looks

`openExternalLinksInNewTab` (`portalHelpers.js:39-67`) registers a `document` click listener:

```js
// portalHelpers.js:59-62
if (!isInternalLink) {
  link.target = '_blank';
  link.rel = 'noopener noreferrer'; // Security and performance benefits
```

"Internal" means same **hostname** as the current location, `customDomain` or `hostURL`
(`:54-57`, `isSameHost` compares `hostname` only - `node_modules/@chatwoot/utils/dist/utils.esm.js:1306-1311`).
Properties that matter at scale:

| Property | Consequence |
|---|---|
| Runs on `click`, after the reader acts | The first click is correct, because the anchor's default action reads `target`/`rel` after the listeners run (browser behaviour, standard, not tested here). Nothing exists in the served HTML. |
| Needs the portal bundle to have loaded | No-JS readers, reader modes, print/PDF, crawlers, and `GET /hc/<slug>/articles/<slug>.md` (`routes.rb:517`, served raw by `show_markdown`, `articles_controller.rb:29-33`) see links with no attributes. |
| Assigns `link.rel` wholesale (`:61`) | Any `rel` token a future server-side change adds (for example `nofollow`) is **overwritten** on click. The two layers must be designed together. |
| Registered once per Turbo visit | `portal.js:9` calls `onLoad` on every `turbo:load`; `onLoad` -> `initialize` -> `openExternalLinksInNewTab()` (`:167`) adds another `document` listener each time and never removes one. Idempotent, so harmless; wasteful. (F12) |
| `isOnArticlePage` is captured at registration (`:41-42`) | Correct per visit; stale listeners from earlier visits stay live. |

Middle-click, Ctrl/Cmd-click and "Open in new tab" never need the handler: a browser-initiated new tab carries no
`window.opener`. (Browser behaviour, standard, not tested here.)

### 2.3 The contrast: the JS markdown-it path

`app/javascript/shared/helpers/MessageFormatter.js:43-64` builds markdown-it with `html: false` (`:45`, the same raw-HTML
stance as the Ruby side) and registers `markdown-it-link-attributes` unconditionally:

```js
// MessageFormatter.js:57-63
.use(mila, { attrs: { class: 'link', rel: 'noreferrer noopener nofollow', target: '_blank' } });
```

| | Chat UI (JS, `MessageFormatter.js`) | Article render (Ruby, `CustomMarkdownRenderer`) | Portal chrome (ERB) |
|---|---|---|---|
| `target="_blank"` | every link, at render time | none; added on click for off-host links | static |
| `rel="noopener noreferrer"` | yes | none; added on click | yes (`_footer.html.erb:26`) |
| `nofollow` | yes | **never** | yes (`_footer.html.erb:26`, `_topbar.html.erb:25`) |
| Works without JS | n/a (it is JS) | no | yes |
| Applies to internal links too | yes (all links) | no (off-host only) | n/a |

Three policies for one product. The portal chrome is the strictest and is hard-coded in templates; the article body,
which will carry the hundreds of Meta links, is the one place with no static guarantee.

### 2.4 URL schemes: a denylist, sound for the shapes I could reason about

```ruby
# lib/markdown_renderer_url_sanitizer.rb:3-4, 14-18
DANGEROUS_URL_PATTERN = /\A(?:javascript:|vbscript:|file:|data:)/i
SAFE_DATA_IMAGE_PATTERN = %r{\Adata:image/(?:png|gif|jpeg|webp)}i
def sanitized_href(url)
  url = url.to_s
  return '' if url.match?(DANGEROUS_URL_PATTERN) && !url.match?(SAFE_DATA_IMAGE_PATTERN)
  escape_href(url)
end
```

`escape_href` is cmark's `houdini_escape_href` (`commonmarker.c:1167-1177`), which percent-encodes anything outside
the href-safe set and entity-encodes `"`, `'` and `&`. Walking the shapes:

| Input (after cmark decodes entities, before the renderer sees it) | Output | Why |
|---|---|---|
| `javascript:alert(1)`, `JaVaScRiPt:...` | `href=""` | pattern, `/i` |
| `jav&#x61;script:...` | `href=""` | cmark decodes first; pinned by `custom_markdown_renderer_spec.rb:140-147` |
| `java&Tab;script:...` (tab in scheme) | `java%09script:` | not matched, but `escape_href` percent-encodes the control character; a percent-encoded scheme is not a scheme (reasoned, not browser-tested) |
| leading space or control char (`[x](< javascript:...>)`) | `%20javascript:` / `%01javascript:` | `\A` misses it, `escape_href` makes it an inert relative path (reasoned) |
| `vbscript:`, `file:`, `data:text/html,...` | `href=""` | pattern; spec `base_markdown_renderer_spec.rb:13` |
| `data:image/png;base64,...` (also `gif`, `jpeg`, `webp`) | kept | `SAFE_DATA_IMAGE_PATTERN`; `data:image/svg+xml` is **not** in the list, so it is blanked |
| `//host/path` | kept verbatim | no rule (F5) |
| `http://...` | kept | no rule; mixed content on an https page (F5) |
| `blob:`, `filesystem:`, `intent:`, `view-source:`, `about:`, any custom scheme | kept verbatim | **denylist**: only four schemes are named (F4) |
| `mention://...` | kept | deliberate, for chat (`:2` comment) - irrelevant to articles |
| `https://developers.facebook.com@evil.example/` | kept | userinfo look-alike; nothing inspects the authority (F13) |

Spec coverage of the scheme matrix is thin: one entity-encoded case for articles
(`custom_markdown_renderer_spec.rb:140-147`) and four bare schemes for messages (`base_markdown_renderer_spec.rb:13`).
No whitespace/control-character, case-mix or protocol-relative case is pinned.

### 2.5 Raw HTML, and the embed door that is already open

**Raw HTML does not survive.** `render_article` constructs `CustomMarkdownRenderer.new`
(`lib/chatwoot_markdown_renderer.rb:14`), whose `options:` default is `:DEFAULT` (`commonmarker/renderer.rb:10`);
`UNSAFE` is a separate bit (`commonmarker/config.rb:22`). In that mode:

```ruby
# commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb:110-126
def html(node)  ... else out("<!-- raw HTML omitted -->") ...
def inline_html(node) ... else out("<!-- raw HTML omitted -->") ...
```

`CustomMarkdownRenderer#html` (`:22-27`) swallows only a `<!--cw-colwidths:N,N-->` comment (digits and commas) and
otherwise `super`s into the above; `inline_html` is not overridden. Pinned by `custom_markdown_renderer_spec.rb:32-37`.
An author who types `<iframe src=...>` gets a comment in the output.

**But an iframe is already possible, plainly.** `link` runs before the sanitiser:

```ruby
# custom_markdown_renderer.rb:54-56
def link(node)
  return if surrounded_by_empty_lines?(node) && render_embedded_content(node)
```

`render_embedded_content` matches `node.url` against `config/markdown_embeds.yml` and, on a hit, writes the
**template HTML verbatim** (`:164-172`, captures `CGI.escapeHTML`ed at `:206`). The 11 entries:

| Key | Emits | Notes (`config/markdown_embeds.yml`) |
|---|---|---|
| `youtube` (`:13-23`) | iframe, `youtube-nocookie.com` | no `title`, no `sandbox` |
| `loom` (`:25-33`), `vimeo` (`:35-45`, `dnt=true`), `arcade_tab` (`:57-70`), `arcade` (`:72-85`), `guidejar` (`:139-149`) | iframe | no `title` on any of them |
| `bunny` (`:108-120`), `codepen` (`:122-137`) | iframe | the only two with a `title` and `loading="lazy"` |
| `mp4` (`:47-55`) | `<video preload="metadata"><source src=...>` | regex `https?://(?:www\.)?.+\.mp4` has **no host restriction** |
| `wistia` (`:87-106`) | two `<script src="https://fast.wistia.com/...">`, a `<style>`, `<wistia-player>` | third-party JS on the page origin |
| `github_gist` (`:151-161`) | `<script src="https://gist.github.com/.../....js">` | third-party JS on the page origin |

Totals: 8 iframes, 1 video, 2 script-bearing templates. None sets `sandbox` or `referrerpolicy`.

What triggers it: the link must have no non-blank **text** sibling (`node_empty?`, `:160-162`, treats every non-text
node as empty). It need not stand alone on a line: `**Watch:** [clip](https://youtu.be/x)` embeds, `Watch: [clip](...)`
does not (spec `custom_markdown_renderer_spec.rb:160-168` pins the text rule). Matching is **unanchored** (`:189`
`link_url.match(regex)`), so any URL that merely *contains* `youtu.be/ID` or ends a path in `.mp4` is converted.

What I tried to break and could not (by reading): attribute breakout in the captured `video_id` - the captures are
`CGI.escapeHTML`ed and the existing spec asserts it (`custom_markdown_renderer_spec.rb:285-301`); `</style>` breakout
in the Wistia `<style>` block - `<` is escaped and the captures exclude `/`, so the closing tag cannot be formed, and
`'` becomes the literal text `&#39;` inside the CSS string (raw-text element, not decoded). The hosts are fixed in the
templates, so a capture can only change the path. The risk of the layer is therefore **trust in the provider**, not
injection by the author.

### 2.6 Referrer behaviour (article URL leaking to a third party)

Nothing in the repository sets a referrer policy: no `Referrer-Policy` in `app/`, `config/` or `deployment/`
(`deployment/nginx_chatwoot.conf:62` adds only HSTS), no `<meta name="referrer">` in `layouts/_portal_head.html.erb`.
What applies is the framework default: `config.load_defaults 7.0` (`config/application.rb:39`) selects the `"7.0"`
block of `railties-7.2.3.2/.../configuration.rb:218`, which sets
`"Referrer-Policy" => "strict-origin-when-cross-origin"` (`:228`).

| Outbound path | What the third party receives (browser behaviour, default policy) |
|---|---|
| Click on an external article link (after JS handler) | nothing - `noreferrer` |
| Click without the handler (no JS, middle-click) | origin only, `https://<portal host>/`; never the article path or query |
| `<img>`, `<video>`, `<iframe>` load | origin only |
| "Open in ChatGPT" / "Open in Claude" (`_actions.html.erb:3-6,25,33`) | by design the article's `.md` URL travels in the destination's `?q=`; `show_markdown` refuses unpublished articles (`articles_controller.rb:30`) |
| GA4/GTM/Hotjar/Plausible, if the portal row has an ID (`layouts/_portal_analytics.html.erb`) | the full URL, by design; whether the platform portals have IDs set is data - not checked |

So the article path is not leaked to Meta or to an embed provider today. The protection is real but **implicit**: it is
the framework default, not a stated decision, and no test pins it (F6).

### 2.7 CSP and framing

`config/initializers/content_security_policy.rb:14-17` is the whole policy:

```ruby
policy.object_src :none
policy.base_uri :self
```

Its own comment (`:10-13`) says `default-src`, `script-src` and `style-src` are deferred to a "stage two" and that
`frame-ancestors` is deliberately absent. `rg content_security_policy` over `app custom lib config` finds no other
source, and nginx adds none. Consequently **no directive restricts `frame-src`, `child-src`, `script-src`, `img-src`
or `media-src`**: every embed above loads, every third-party script runs, and every external image fetches.

Framing the other way (who may frame *us*): Rails' default `X-Frame-Options: SAMEORIGIN` is deleted for any portal
request carrying `?show_plain_layout=true` (`base_controller.rb:15,66-68`), so any site can frame any published article
by appending that parameter. Public content, so minor; recorded because a stage-two `frame-ancestors` must account
for it.

Stage-two dependency worth surfacing now: the article path emits inline `style=` at five sites
(`custom_markdown_renderer.rb:68,88,96,126,184`) plus every embed template and Wistia's `<style>`, and the portal head
carries inline `<script>` (`_portal_head.html.erb:32-43`, `_portal_scripts.html.erb`). A `style-src` or `script-src`
without `'unsafe-inline'` or nonces will break table and image sizing as well as embeds.

### 2.8 Images

```ruby
# custom_markdown_renderer.rb:61-71 (abridged)
src = sanitized_href(node.url)
out(%(<img src="#{src}")) ... out(' alt="', :children, '"') ... title ... style (bounded px) ... out(' />')
```

Any `https:`, `http:` or protocol-relative host is accepted. The tag carries no `loading`, `referrerpolicy`,
`crossorigin` or intrinsic `width`/`height`. **Yes: an external image URL in Markdown makes the reader's browser call
the third party from a page on the product's own domain**, on page load and without a click, handing over IP,
User-Agent, `Accept-Language`, any cookies that origin holds for the reader, and `Referer: https://<portal host>/`. The
`mp4` embed does the same with `preload="metadata"`. Nothing blocks it (no `img-src`/`media-src`).

### 2.9 Link-health tooling

None. `rg -i 'link.?check|html-proofer|lychee|linkinator|broken.?link|dead.?link'` over the repository (excluding
`node_modules`, `vendor`, the lockfile and `docs/`) matches two comments that use the words in other senses
(`Sidebar.vue:56`, `operations/probes.rb:85`). `.github/workflows/` has 16 files and none touches documentation.
`lib/tasks/documentation_seo_audit.rake` audits canonical, hreflang, title and description and never reads an article
body's links. There is no outbound-click telemetry. A dead link would be discovered by a reader who clicked it and
wrote to support.

## 3. Findings

Severity: `blocker | major | minor`. "Reachable" is today vs only after the editor upgrade.

| ID | Claim | Evidence | Impact | Sev. | Reachable |
|---|---|---|---|---|---|
| F1 | Server-rendered external links carry no `target`/`rel`; the guarantee is a click-time DOM mutation | `markdown_renderer_url_sanitizer.rb:6-10`; `portalHelpers.js:59-62` | No tabnabbing vector exists today (no `target` emitted). But the safe attributes exist only after JS and a click; crawlers, no-JS, print and `.md` consumers get a bare link, and the handler overwrites `rel` | minor | today (design, not exploit) |
| F2 | An embed layer already emits iframes, `<video>` and third-party `<script>` into article HTML, bypassing both the URL sanitiser and the raw-HTML omission | `custom_markdown_renderer.rb:54-56,164-209`; `markdown_embeds.yml:13-161`; no `sanitize` in the path (`chatwoot_markdown_renderer.rb:27-31`) | Wistia and Gist templates run provider JS in the page. The docs portal is served from the app host (`/docs` redirects to the relative `/hc/<slug>`, `documentation_controller.rb:33`) where the JS-set, therefore non-HttpOnly, session cookie `cw_d_session_info` carries the auth headers (`app/javascript/dashboard/store/utils/api.js:33`). A compromised or changed provider script would read it. Whether production uses a separate `DOCUMENTATION_URL` host: not checked | major | today, by any author. Also by any account administrator authoring a portal article (`article_policy.rb:18-20`) |
| F3 | Embed matching is unanchored and `mp4` has no host restriction | `custom_markdown_renderer.rb:189`; `markdown_embeds.yml:48` | A Meta URL whose query/fragment contains `.mp4` or `youtu.be/ID` silently renders as a video or iframe instead of a link; any `.mp4` host is loaded on page view | minor | after links to Meta are added |
| F4 | Scheme handling is a four-item denylist | `markdown_renderer_url_sanitizer.rb:3` | Sound for `javascript:`, `vbscript:`, `file:`, `data:` incl. entity, case and whitespace variants (reasoned); any other scheme passes (`blob:`, `intent:`, custom). Not exploitable by a trusted author; wrong default for a corpus that should only ever need `https:` | minor | today |
| F5 | Protocol-relative and `http://` URLs pass untouched in `href` and `img src` | `markdown_renderer_url_sanitizer.rb:14-18` | `//host` is invisible to any server-side "is it absolute?" test unless that test handles it; `http://` is mixed content on an https page | minor | today |
| F6 | The referrer protection is the unstated framework default | `config/application.rb:39`; `railties configuration.rb:228`; no override anywhere | Safe today; a fronting proxy, a `load_defaults` change or a future header edit would change what hundreds of outbound links disclose with no test failing | minor | today |
| F7 | No CSP constrains frames, scripts, images or media | `content_security_policy.rb:14-17` | F2 has no safety net; there is nothing to make an unexpected embed host fail loudly | major (compounds F2) | today |
| F8 | External images are fetched from the reader's browser on a first-party page | `custom_markdown_renderer.rb:61-71` | Reader IP/UA to a third party, hotlink rot, layout shift (no intrinsic size), and for Meta hotlinks a copy of Meta's material the charter says to paraphrase and link instead | minor (0 images today) | after the editor adds media |
| F9 | Nothing detects a dead or drifted link | section 2.9 | The program will add hundreds of Meta links; Meta restructures documentation and version-pins URLs; a dead one is found by a reader | major | today (absence) |
| F10 | **Every Arabic internal link opens the English article.** 494 AR links are bare keys (0 end in `-ar`); AR slugs are `<key>-ar`; lookup is exact-slug with no locale redirect; the show route has no locale segment | `content_seeder.rb:85-87`; `articles_controller.rb:80-83`; `routes.rb:519`; no link rewriting in `content_seeder.rb` or the model; measured on the corpus | A link-integrity defect no checker would flag, because every target exists. By code reading; not executed | major | today. Owners: 076, 094 |
| F11 | Embed markup defects | `markdown_embeds.yml`: 6 of 8 iframes lack `title`; deprecated `frameborder`/`allowtransparency`; embed `<div>` is written inside the paragraph's `<p>` (`html_renderer.rb:17-30`) | Accessibility (iframe name), invalid nesting | minor | after an embed is used |
| F12 | Click listener registered once per Turbo visit and never removed | `portal.js:9`; `portalHelpers.js:167` | Accumulating idempotent listeners | minor | today |
| F13 | Authority look-alikes (`https://developers.facebook.com@evil.example`, homographs) are not inspected | `sanitized_href` | Text-vs-destination mismatch; author-trust only, but trivially lintable | minor | after links added |

Findings that did **not** hold: attribute breakout through embed captures (escaped, spec-pinned);
`javascript:` via whitespace/control-character/entity forms (blanked or percent-encoded); raw `<iframe>`/`<script>`
typed by an author (omitted); SVG data URIs (not on the safe-image list); reverse tabnabbing (no `target` is emitted,
and the handler sets `noopener noreferrer` together with it).

### Not checked

- Anything requiring execution: the renderer was read, not run. Behaviours I reasoned (whitespace-scheme forms,
  `%09` neutralisation, the `<p><div>` nesting) are worth one spec each, which is not mine to write in Phase 1.
- Browser semantics (implicit `noopener`, origin-only `Referer`, top-navigation from unsandboxed frames) are standard
  but were not tested in a browser.
- Production topology: whether the docs portal is on the app host or a separate `DOCUMENTATION_URL`; whether a CDN or
  proxy rewrites headers; whether the platform portals have analytics IDs set.
- Meta's URL behaviour (redirects, bot blocking, soft-404s, how often paths move) and embed providers' referrer
  requirements: no external fetch was authorised.
- Whether the Help Center feature is enabled for tenants in production (affects the reach of F2 beyond Super Admin).

## 4. What the editor upgrade would newly expose

| Upgrade capability | Newly exposed | Control that already exists | Gap |
|---|---|---|---|
| Rich-text editor that serialises to Markdown | The author sees a link dialog with free-form URLs | Renderer denylist (F4) | Client validation is a convenience only; the renderer must be the enforcement |
| Paste from a web page | Pasted `<iframe>`, `<a target=_blank>`, `<img src=https://scontent...>` | Raw HTML omitted at render | The editor preview may show it while the portal drops it: **works in preview, vanishes on publish**. Preview must go through the real renderer; the existing `preview` action does (it redirects to the portal) |
| Upstream editor embed UX | `config/markdown_embeds.yml:49-50` (`hide_source`, "Editor-only") and `custom_markdown_renderer.rb:17-27,174-185` (`cw-colwidths`, `cw_video_width`) are the renderer half of upstream's editor; `package.json:41` pins `@chatwoot/prosemirror-schema` | none | Adopting that editor brings an embed insertion UI that targets the F2 layer |
| Image upload | ActiveStorage images (agents 066-068) | own-origin URLs | An "insert image by URL" field would reintroduce F8 |
| Drag-resize | `cw_image_width` / `cw_video_width` query params on URLs | bounded `digits px` parse (`custom_markdown_renderer.rb:141-146`) | none; noted so a lint does not flag the params as tracking |
| Large corpus of Meta links | F9 and F3 become probable, not theoretical | none | needs the controls below |

## 5. Required controls

Minimum set, each mapped to an existing mechanism (charter section 2: extend, do not duplicate).

| # | Control | Mechanism to extend | Closes |
|---|---|---|---|
| C1 | Scheme **allowlist** for article rendering: `https:`, relative, fragment, and `mailto:` only if a support address is needed. Keep `mention://` out of the article path | `MarkdownRendererUrlSanitizer` (`:3,14-18`) - the article renderer gets the allowlist, `BaseMarkdownRenderer` keeps its chat behaviour | F4, F5 |
| C2 | Server-side attributes on every external article link: `target="_blank" rel="noopener noreferrer"`. Treat any `http(s)://` or `//` URL as external, which is safe because the corpus convention is relative internal links | `CustomMarkdownRenderer#link` (`:54-59`), **not** the shared module (it also renders chat and email). Keep the JS handler; align its `rel` with C2 | F1 |
| C3 | State the referrer policy instead of inheriting it: `strict-origin-when-cross-origin` set explicitly for portal responses. Do **not** use `no-referrer` globally until each embed provider's requirement is checked | `Public::Api::V1::Portals::BaseController` beside `allow_iframe_requests` (`:66-68`) | F6 |
| C4 | **No embeds in the platform documentation portals.** Enforce in the corpus, not by removing the feature, because tenant portals legitimately use it | The link audit (C6) rejects any link whose URL matches `CustomMarkdownRenderer.embed_regexes` | F2, F3, F11 |
| C5 | No third-party images, Meta's included. Images come from ActiveStorage or are relative | C6 lint; editor upload only (no insert-by-URL) | F8 |
| C6 | A **link audit** modelled on `lynomia:docs:seo_audit` (`documentation_seo_audit.rake`): reads the same Markdown, parses with the same CommonMarker, exits 1 on error | New task beside the existing one; same `error`/`warn` shape | F3, F9, F10, F13 |
| C7 | Stage-two CSP, report-only first as the file already plans (`content_security_policy.rb:13`): `frame-src` generated from the iframe hosts in `markdown_embeds.yml`, `img-src` own origin plus ActiveStorage host, and a decision on inline `style`/`script` (section 2.7). It must be per portal kind, because tenant portals use embeds | `config/initializers/content_security_policy.rb`; owner 098 with Agent 000 | F7 |
| C8 | The editor serialises Markdown only, previews through the real renderer, and validates the link scheme client-side with the same allowlist | `SuperAdmin::ArticlesController#preview`; editor decision (agents 063-072) | section 4 |

### Recommended policy

**Which external content is allowed**

| Content | Policy |
|---|---|
| Links | `https:` only. Host must be on an allowlist in the repository. Initial allowlist: the hosts the charter names as normative for Meta (section 6.2: `developers.facebook.com`, `business.facebook.com`, `www.facebook.com` under `/business/help`) plus Meta's own status/changelog hosts, to be named by agents 003 and 028. Any other host needs a reviewer's explicit addition. No userinfo, no tracking parameters, no shortened URLs |
| Link text | Names the destination page, matching its title in the source register; never "click here". An Arabic article linking to an English-only Meta page says so in the link text |
| Meta material | Paraphrase and link (charter). No hotlinked or copied Meta screenshots. Version-pinned Meta URLs are recorded with their API version in the register, because they age on Meta's deprecation schedule |
| Images | Own origin only (ActiveStorage or relative) |
| Iframes, video, script embeds | **None.** The documentation explains errors and flows; screenshots and text do that better, survive link rot, translate to Arabic, and cost no page weight or privacy. If a walkthrough is ever approved: YouTube via the existing `youtube-nocookie` template only, with a `title`, lazy loading and a text transcript in both locales; never Wistia, Gist or `mp4` |
| Raw HTML | None (the renderer already drops it; the lint reports it so the author knows) |

**What every external link must carry**

| Attribute | External (absolute) link | Internal link |
|---|---|---|
| `href` | `https://`, canonical path, no tracking parameters | relative slug, per the locale rule (F10) |
| `target="_blank"` | yes | no |
| `rel` | `noopener noreferrer` (`noreferrer` implies `noopener`; both kept for old WebViews) | none |
| `nofollow` | no - editorial citations of an authoritative source; it has no security function. Final call belongs to 073-080 | no |
| `title` | no | no |
| Visible and assistive cue that it opens a new tab | yes (WCAG technique G201). Mechanism for 099; a Tailwind variant on `#cw-article-content` (`_content.html.erb:6-17`) avoids per-link markup | no |

**How link health is checked** - two passes with different failure semantics.

1. **Static audit** (offline, deterministic, safe to gate a PR or release because it reads only files):
   parse every article in both locales; classify each link; fail on a disallowed scheme or host, `http://`, `//`,
   userinfo, tracking parameters, an image or raw HTML that is not allowed, any embed-pattern match, an internal
   target that does not resolve **in the same locale** (the `-ar` rule, F10), and an external URL absent from the
   Meta source register (`03-meta-source-register.md`, which already records URL, title and date checked, and
   should be machine-readable). The inverse check - a register URL no article cites - is a warning.
2. **Liveness audit** (network, scheduled, **never a deploy gate** - a Meta outage or a bot block is not a Lynomia
   defect). Each distinct URL once, not once per article, rate-limited per host, through `SafeFetch`
   (`lib/safe_fetch.rb:26-34`: SSRF filter, 2 s open / 20 s read timeouts, `method:` and `validate_content_type:`
   options in `request_options.rb:2-15`, `HEAD` available via `SsrfFilter::VERB_MAP`, redirects capped at
   `DEFAULT_MAX_REDIRECTS = 10`). Classification: `ok`; `redirected` (record the final URL; flag when the final path
   differs materially or lands on a generic landing page); `dead` (404/410); `inconclusive` (401/403/429/5xx/timeout,
   retried before alarming); `drifted` (200, but `<title>` no longer matches the register). The thresholds for
   "consecutive failures before alarm" and "re-verify every N months" are owner decisions, not Meta facts, and are
   deliberately not invented here.

Where results live: **not** in `Article.meta`. The content seeder rebuilds `meta` from the file on every run
(`content_seeder.rb:94-104`, `meta_for` at `:106-113`), so any health data stored there is wiped by the next sync.
Use a scheduled-job artifact (a workflow in `.github/workflows/`, which has none for docs today) or the operations
probes (`custom/app/services/operations/probes.rb`); the choice is for Agent 000 with 097, since it interacts with the
content-sync design.

Both passes report to a human with a named fix owner per article. A tool that opens an alert nobody owns repeats the
current situation with extra steps.
