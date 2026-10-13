---
agent: 065
scope: Markdown rendering and sanitization for a documentation article, end to end — article.content to bytes in the browser
confidence: high
---

`01-current-system.md` §5 names this "the single most important security question in the program" and ends with
*"`CustomMarkdownRenderer`/`BaseMarkdownRenderer` must be read before any claim is made either way."* They have now
been read, together with the vendored `commonmarker` 0.23.12 Ruby renderer and its C escaping routines. The answer is
definite and it is not the one the §5 wording anticipates: **raw HTML in a documentation article is neither rendered
nor escaped — it is deleted and replaced by the literal comment `<!-- raw HTML omitted -->`.** There is no `sanitize`
call in the path and there does not need to be one for raw HTML, because the renderer never emits author HTML in the
first place.

That is the good news and it is where the good news stops. The same renderer deliberately injects raw HTML of its
own — eleven embed templates, nine of them `<iframe>` and **two of them `<script src>`** — and the portal's
Content-Security-Policy contains exactly two directives, neither of which constrains script or frame loading.

---

## 1. What exists today

### 1.1 The chain, with no gaps

| # | Step | Evidence |
|---|---|---|
| 1 | `article.content` (`text`, no format validation, no sanitization on write) | `app/models/article.rb:6,68` — `validates :content, presence: true, if: :published?` and nothing else |
| 2 | `GET /hc/:slug/articles/:article_slug` → `#show` sets `@parsed_content` | `app/controllers/public/api/v1/portals/articles_controller.rb:24-27` |
| 3 | `render_article_content` → `ChatwootMarkdownRenderer.new(content).render_article` | `articles_controller.rb:109-111` |
| 4 | Parse: `CommonMarker.render_doc(@content, :DEFAULT, [:table])` | `lib/chatwoot_markdown_renderer.rb:15` |
| 5 | Render: `CustomMarkdownRenderer.new` — **no arguments** | `lib/chatwoot_markdown_renderer.rb:14` |
| 6 | `html.html_safe` with `# rubocop:disable Rails/OutputSafety` | `lib/chatwoot_markdown_renderer.rb:27-31` |
| 7 | View variant selection (`:documentation` when `portal.layout == 'documentation'`) | `app/controllers/public/api/v1/portals/base_controller.rb:26-32` |
| 8 | `show.html+documentation.erb` renders the **shared** body partial | `app/views/public/api/v1/portals/articles/show.html+documentation.erb:16-18` |
| 9 | `<%= parsed_content %>` — the html_safe string, straight out | `app/views/public/api/v1/portals/articles/_content.html.erb:18` |
| 10 | Response headers: Rails `load_defaults 7.0` + the CSP initializer | `config/application.rb:39`; `config/initializers/content_security_policy.rb:14-17` |

Step 9 is the same partial for all three layouts (classic, plain, documentation) — the header comment says so
explicitly: *"Same rendering in all 3 layouts"* (`_content.html.erb:2-3`). There is **one** article render path, not
three. `grep` for `sanitize` across `app/views/public/`, `app/controllers/public/`, `portal_helper.rb`,
`documentation_helper.rb` and `custom/app/` returns no HTML sanitizer anywhere in it.

### 1.2 The CommonMarker options actually passed

The brief asks for the options *actually* passed, and the distinction matters because the options reach two different
places and only one of them controls HTML safety.

| Call | Parse options | Parse extensions | Render options | Render extensions |
|---|---|---|---|---|
| `render_article` | `:DEFAULT` | `[:table]` | `:DEFAULT` (the `initialize` default) | `[]` (the `initialize` default) |
| `render_message` | `:DEFAULT` | `[:strikethrough, :autolink]` | `[:HARDBREAKS]` or `:DEFAULT` | `[]` |
| `render_markdown_to_plain_text` | `:DEFAULT` | none | n/a (C `to_plaintext`) | n/a |

`CustomMarkdownRenderer.new` takes the gem's defaults:

```ruby
# vendor/bundle/ruby/3.4.0/gems/commonmarker-0.23.12/lib/commonmarker/renderer.rb:10-18
def initialize(options: :DEFAULT, extensions: [])
  @opts = Config.process_options(options, :render)
  ...
  @tagfilter = extensions.include?(:tagfilter)
end
```

`render` `DEFAULT: 0` and `UNSAFE: (1 << 17)` (`lib/commonmarker/config.rb:19,22`), and
`option_enabled?(opt)` is `(@opts & OPTS.dig(:render, opt)) != 0` (`renderer.rb:131-133`). With `@opts == 0`,
`option_enabled?(:UNSAFE)` is `(0 & 131072) != 0` → **false**. `:UNSAFE` appears nowhere in the repository:
`grep -rn ":UNSAFE" --include=*.rb .` (excluding `vendor/`) returns nothing.

Two things follow that are worth stating now because they are latent traps:

- **`[:table]` is passed to the parser but not to the renderer.** The renderer therefore has `@tagfilter == false`
  (`renderer.rb:17`). `tagfilter` is the GFM defence that neutralises `<script>`, `<iframe>`, `<style>`, `<textarea>`
  and friends *when raw HTML is being emitted* (`renderer.rb:105-121`). It is harmless today only because `:UNSAFE`
  is off. **Anyone who later enables `:UNSAFE` to let authors write HTML will get no tagfilter, because the renderer
  is constructed with no extensions.** That is a one-word change away from a full stored-XSS hole.
- The parse-time `UNSAFE` bit exists too (`config.rb:11`) and is likewise unset.

### 1.3 What the renderer emits

`CustomMarkdownRenderer < CommonMarker::HtmlRenderer` and `include MarkdownRendererUrlSanitizer`
(`lib/custom_markdown_renderer.rb:1-2`). Ruby's ancestor order is `CustomMarkdownRenderer` →
`MarkdownRendererUrlSanitizer` → `CommonMarker::HtmlRenderer`, so the class's own `link` wins and its `super` lands
on the module's `link`, not the gem's. That is load-bearing: it is the reason a non-embed link still gets sanitized.

Overridden: `html`, `table`, `text`, `link`, `image`. **Not** overridden: `inline_html`, `code`, `code_block`,
`header`, `paragraph`, `blockquote`, everything else.

---

## 2. Constraints the existing system imposes

An editor upgrade must not break these, because each one is currently the only thing doing a job:

1. **`:DEFAULT` render options are the entire raw-HTML defence.** There is no sanitizer behind them. Enabling
   `:UNSAFE`, or swapping in a renderer that emits author HTML, removes the only control that exists.
2. **The `html_safe` at `chatwoot_markdown_renderer.rb:29` is unconditional.** Whatever the renderer writes reaches
   the browser as trusted markup. Every new `out(...)` in a renderer subclass is a trust decision.
3. **`config/markdown_embeds.yml` is the only raw-HTML emitter**, and it is source-controlled, not author-controlled.
   That boundary is the whole safety argument for embeds. Moving embed templates into the database, or letting an
   author supply a template, destroys it.
4. **`CustomMarkdownRenderer#html` swallows any HTML block containing `<!--cw-colwidths:...-->`** rather than passing
   it to `super` (`custom_markdown_renderer.rb:22-27`). The colwidths marker is the ProseMirror editor's table
   round-trip channel. An editor that stops emitting it, or emits a second marker kind, changes render output.
5. **Captures interpolated into embed templates are escaped with `CGI.escapeHTML`** (`custom_markdown_renderer.rb:206`)
   and separately with a hand-rolled `escapeHtml` on the client (`node_modules/@chatwoot/prosemirror-schema/src/plugins/embedPreview.js:36-42`).
   Two implementations of the same rule in two languages. Any new template must keep every capture inside a quoted
   attribute, because that is the only context either escaper is written for.
6. **`escape_href` and `escape_html` are C routines with fixed behaviour**, not configurable hooks
   (`ext/commonmarker/houdini_href_e.c:32-44`, `houdini_html_e.c:18-33`). Hand-built tags are safe only because they
   interpolate through these. A new hand-built tag that interpolates anything else is an injection.
7. **The Lynomia documentation author never touches the ProseMirror editor.** Authoring is
   `content: Field::Text.with_options(rows: 28)` (`custom/app/dashboards/article_dashboard.rb:19`) — a textarea. So
   the editor-side sanitization story (markdown-it `html: false`, DOMPurify, the embed preview) is not in this
   author's loop at all today.

---

## 3. Findings

### 3.1 The seven questions, answered

**(1) Is raw HTML in article Markdown rendered or escaped? — Neither. It is omitted.**

```ruby
# vendor/.../lib/commonmarker/renderer/html_renderer.rb:110-126
def html(node)
  block do
    if option_enabled?(:UNSAFE)
      out(tagfilter(node.string_content))
    else
      out("<!-- raw HTML omitted -->")
    end
  end
end

def inline_html(node)
  if option_enabled?(:UNSAFE)
    out(tagfilter(node.string_content))
  else
    out("<!-- raw HTML omitted -->")
  end
end
```

`CustomMarkdownRenderer#html` delegates to this for everything that is not the colwidths marker
(`custom_markdown_renderer.rb:22-27`: `return super unless match`), and `inline_html` is not overridden at all, so
both block-level and inline raw HTML are omitted. The repo asserts it:

```ruby
# spec/lib/custom_markdown_renderer_spec.rb:31-37
describe '#html' do
  it 'omits raw HTML' do
    rendered = render_markdown('<script>alert("xss")</script>')
    expect(rendered).to include('<!-- raw HTML omitted -->')
    expect(rendered).not_to include('<script>')
  end
end
```

Note the consequence that is *not* a security consequence: because HTML is deleted rather than escaped, an author who
writes `<inbox>` in prose loses it silently. See F4 — this is live in production today.

**(2) Is a `<script>` tag in an article body executable in the published portal? — A typed one, no. A `<script src>`
the renderer itself writes, yes, and two embed types do exactly that.**

`<script>alert(1)</script>` becomes `<!-- raw HTML omitted -->`. But `config/markdown_embeds.yml` turns a plain
Markdown link, alone on its own line, into raw HTML — and two templates are script tags:

```yaml
# config/markdown_embeds.yml:87-92 (wistia)
wistia:
  regex: 'https?://(?:www\.)?[^/]+\.wistia\.com/medias/(?<video_id>[^&/?]+)'
  template: |
    <div style="position: relative; padding-bottom: 56.25%; height: 0;">
      <script src="https://fast.wistia.com/player.js" async></script>
      <script src="https://fast.wistia.com/embed/%{video_id}.js" async type="module"></script>
```

```yaml
# config/markdown_embeds.yml:151-154 (github_gist)
github_gist:
  regex: 'https?://gist\.github\.com/(?<username>[^/]+)/(?<gist_id>[a-f0-9]+)'
  template: |
    <script src="https://gist.github.com/%{username}/%{gist_id}.js"></script>
```

The trigger is `CustomMarkdownRenderer#link` (`custom_markdown_renderer.rb:54-59`) → `render_embedded_content`
(`:164-172`) → `render_embed_from_match` (`:198-209`), which `out`s the template verbatim. The renderer's own spec
asserts the script tag is emitted (`spec/lib/custom_markdown_renderer_spec.rb:215`). So the answer to "can a
`<script>` tag reach the published portal from an article body" is **yes** — via a link, not via raw HTML, and with
the script origin fixed at `fast.wistia.com` or `gist.github.com`.

The capture groups cannot move the origin: `username` and `user` are `[^/]+`, `video_id` is `[^&/?]+`, `library_id`
is `\d+`, and none can contain `/`, so none can terminate the hardcoded authority. `CGI.escapeHTML` additionally
blocks attribute breakout. The origin lock is real; the script inclusion is also real.

**(3) `javascript:` and `data:` URLs in links and images? — `javascript:`, `vbscript:`, `file:` are blanked. `data:`
is blanked *except* `data:image/{png,gif,jpeg,webp}`, which is permitted on images **and on links**.**

```ruby
# lib/markdown_renderer_url_sanitizer.rb:1-20
module MarkdownRendererUrlSanitizer
  DANGEROUS_URL_PATTERN = /\A(?:javascript:|vbscript:|file:|data:)/i
  SAFE_DATA_IMAGE_PATTERN = %r{\Adata:image/(?:png|gif|jpeg|webp)}i

  def link(node)
    out('<a href="', sanitized_href(node.url), '"')
    ...
  end

  private

  def sanitized_href(url)
    url = url.to_s
    return '' if url.match?(DANGEROUS_URL_PATTERN) && !url.match?(SAFE_DATA_IMAGE_PATTERN)

    escape_href(url)
  end
end
```

The `\A` anchor is the obvious place to attack, and it survives — not because of the Ruby, but because cmark
normalises the destination before the Ruby ever sees it:

```c
// ext/commonmarker/inlines.c:869-885
// Clean a URL: remove surrounding whitespace, and remove \ that escape punctuation.
cmark_chunk cmark_clean_url(cmark_mem *mem, cmark_chunk *url) {
  cmark_strbuf buf = CMARK_BUF_INIT(mem);
  cmark_chunk_trim(url);
  ...
  houdini_unescape_html_f(&buf, url->data, url->len);
  cmark_strbuf_unescape(&buf);
  return cmark_chunk_buf_detach(&buf);
}
```

Whitespace is trimmed and **HTML entities are decoded** before `node.url` exists, so leading-space and
entity-encoding bypasses both fail. The repo tests the entity case:

```ruby
# spec/lib/custom_markdown_renderer_spec.rb:140-146
context 'when link uses an unsafe URL' do
  it 'blanks the URL' do
    output = render_markdown_link('jav&#x61;script:alert(1)')
    expect(output).to include('<a href="">link</a>')
    expect(output).not_to include('javascript:')
  end
end
```

Images use the same helper (`custom_markdown_renderer.rb:62`, `base_markdown_renderer.rb:15`) and are likewise
tested (`custom_markdown_renderer_spec.rb:369-375`, `base_markdown_renderer_spec.rb:13`).

**(4) `onerror` / `onload` attributes? — Not reachable.** Raw HTML is omitted, so an author cannot write an attribute
directly. The renderer hand-builds exactly two tags, and every interpolated value is escaped or bounded:

```ruby
# lib/custom_markdown_renderer.rb:61-71
def image(node)
  src = sanitized_href(node.url)
  width = extract_image_width(src)
  plain do
    out(%(<img src="#{src}"))
    out(' alt="', :children, '"')
    out(%( title="#{escape_html(node.title)}")) if node.title.present?
    out(%( style="width: #{width}; max-width: 100%; height: auto;")) if width
    out(' />')
  end
end
```

- `src` → `escape_href` → `houdini_escape_href`, whose `HREF_SAFE` table marks `"` (34), `<` (60), `>` (62), space
  (32) and all bytes ≥ 128 as unsafe and percent-escapes them; `&` → `&amp;`, `'` → `&#x27;`
  (`houdini_href_e.c:32-44,65-94`). An attribute breakout is impossible.
- `title` → `escape_html` → `houdini_escape_html0(..., secure=1)`, escaping `"` `&` `'` `/` `<` `>`
  (`houdini_html_e.c:18-33,64-66`).
- `width` → `extract_px_param`, `\A(\d+)px\z` plus `px.between?(1, 2000)` (`custom_markdown_renderer.rb:141-146`).
  `BaseMarkdownRenderer` carries the same guard with the reason written down: *"Only allow a bounded `<digits>px`
  value so the decoded query param can't break out of the inline style attribute (HTML attribute injection)"*
  (`base_markdown_renderer.rb:32-39`).

**(5) iframes and embeds? — Yes, by design, for eleven URL patterns, nine of which are `<iframe>`.** Full inventory
from `config/markdown_embeds.yml`:

| Key | Emits | Fixed origin |
|---|---|---|
| youtube | `<iframe>` | `www.youtube-nocookie.com` |
| loom | `<iframe>` | `www.loom.com` |
| vimeo | `<iframe>` | `player.vimeo.com` |
| mp4 | `<video><source>` | any `https?://…mp4` the author names |
| arcade_tab / arcade | `<iframe>` | `app.arcade.software` |
| wistia | **2 × `<script src>`** + `<style>` + `<wistia-player>` | `fast.wistia.com` |
| bunny | `<iframe>` | `player.mediadelivery.net` |
| codepen | `<iframe>` | `codepen.io` |
| guidejar | `<iframe>` | `www.guidejar.com` |
| github_gist | **`<script src>`** + `<noscript>` | `gist.github.com` |

No iframe carries `sandbox` or `referrerpolicy`. YouTube and GuideJar are granted
`allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"`
(`markdown_embeds.yml:21,146`) — `clipboard-write` delegated to a third-party frame on a page the reader trusts.
`object_src :none` in the CSP blocks `<object>`/`<embed>`; it does **not** touch `<iframe>`.

The CSS injection angle on the wistia `<style>` block (`markdown_embeds.yml:93-100`, `%{video_id}` inside a CSS
string and a `url()`) does **not** open: `CGI.escapeHTML` turns `'` and `"` into `&#39;`/`&quot;`, which inside a
raw-text `<style>` element stay literal characters and therefore cannot close the CSS string. The rule breaks; it
does not escape. That is an accident, not a control.

**(6) Is there a Content-Security-Policy on the public portal response, and what does it allow? — Yes, and it allows
everything that matters.**

```ruby
# config/initializers/content_security_policy.rb:14-17
Rails.application.config.content_security_policy do |policy|
  policy.object_src :none
  policy.base_uri :self
end
```

The header is therefore `Content-Security-Policy: object-src 'none'; base-uri 'self'` and nothing else. The
middleware applies it to every non-304 response with no HTML gate
(`vendor/.../actionpack-7.2.3.2/lib/action_dispatch/http/content_security_policy.rb:37-56`), and no controller
overrides it — `grep -rn "content_security_policy" app/controllers/ custom/ config/environments/` finds only
`widgets_controller.rb:84`, a different surface. `deployment/nginx_chatwoot.conf` adds only HSTS (`:62`).

The initializer's own comment is honest about the state: *"No default-src, script-src or style-src yet,
deliberately… Stage two adds those, report-only first"* (`content_security_policy.rb:10-13`). What that leaves:

| Directive | Effective value | Consequence for an article |
|---|---|---|
| `script-src` | **absent, no `default-src`** | inline and external script both allowed — the gist/wistia tags run, and anything a future editor lets through runs |
| `frame-src` / `child-src` | absent | any iframe to any origin allowed |
| `style-src` | absent | inline style allowed (the templates need it) |
| `img-src` | absent | `data:` images allowed |
| `frame-ancestors` | absent | no framing control (see F3) |
| `object-src` | `'none'` | `<object>`/`<embed>` blocked |
| `base-uri` | `'self'` | `<base>` hijack blocked |

Rails' `load_defaults 7.0` does supply `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`,
`X-Permitted-Cross-Domain-Policies: none`, `X-XSS-Protection: 0`
(`vendor/.../actionpack-7.2.3.2/lib/action_dispatch/railtie.rb:34-38`). `nosniff` is what keeps `show_markdown`'s
`text/markdown` body (`articles_controller.rb:29-33`) from being sniffed into HTML.

**(7) How does the Vue/dashboard-side markdown path differ? — Different engine, different raw-HTML outcome, an extra
sanitizer the server does not have, and an embed set that does not match what the server publishes.**

| | Server (documentation article) | Client (dashboard) |
|---|---|---|
| Engine | `commonmarker` 0.23.12 / cmark-gfm C | `markdown-it` ^14.3.2 (`package.json:88`) |
| Raw HTML | **omitted** → `<!-- raw HTML omitted -->` | **escaped** → `html: false` (`app/javascript/shared/helpers/MessageFormatter.js:45`), so `<script>` shows as visible text |
| Second layer | none | DOMPurify via `v-dompurify-html` (`package.json:77,105`; e.g. `CannedResponse.vue:131`) |
| URL policy | deny-list (`markdown_renderer_url_sanitizer.rb:3`) | DOMPurify allowlist + `tool://` (`shared/helpers/HTMLSanitizer.js:17-23`) |
| Link attrs | none added | `rel="noreferrer noopener nofollow" target="_blank"` (`MessageFormatter.js:58-62`) |
| Embeds | all 11 from `config/markdown_embeds.yml` | the same YAML, **minus `github_gist`** |
| Capture escaping | `CGI.escapeHTML` (`custom_markdown_renderer.rb:206`) | hand-rolled `escapeHtml` (`embedPreview.js:36-42`) |
| Colwidths marker | consumed by `#html` (`custom_markdown_renderer.rb:22-27`) | stripped by regex (`MessageFormatter.js:74-76`) |

The embed divergence is explicit and is a correctness problem for the editor programme:

```js
// app/javascript/dashboard/helper/markdownEmbeds.js:1-12
import config from '../../../../config/markdown_embeds.yml';

// Gists rely on document.write() and can't render inline in the editor.
const NON_PREVIEWABLE_EMBEDS = new Set(['github_gist']);
```

Sharing the YAML is the right instinct, but **the editor cannot preview the one embed that injects a third-party
script tag.** An author sees nothing and publishes a `<script>`. And none of the client-side protection is in the
Lynomia documentation author's loop regardless, because that author types into a Super Admin textarea
(`custom/app/dashboards/article_dashboard.rb:19`).

### 3.2 Concrete payloads, reasoned against the code

Nothing below was executed. Each row is traced through the files cited above.

| Payload in `article.content` | Output | Executes? |
|---|---|---|
| `<script>alert(1)</script>` | `<!-- raw HTML omitted -->` | no |
| `<img src=x onerror=alert(1)>` | `<!-- raw HTML omitted -->` (inline_html) | no |
| `<iframe src=//evil.test></iframe>` | `<!-- raw HTML omitted -->` | no |
| `<svg onload=alert(1)>` | `<!-- raw HTML omitted -->` | no |
| `<!--cw-colwidths:1,2--><script>alert(1)</script>` | **nothing at all** — one HTML block, matches `COLWIDTHS_COMMENT`, so `#html` sets `@pending_colwidths` and returns without `super` | no |
| `[x](javascript:alert(1))` | `<a href="">x</a>` | no |
| `[x](jav&#x61;script:alert(1))` | `<a href="">x</a>` — `houdini_unescape_html_f` decodes before the check | no |
| `[x](<  javascript:alert(1)>)` | blanked — `cmark_chunk_trim` strips leading whitespace first | no |
| `[x](java&NewLine;script:alert(1))` | `href="java%0Ascript:alert(1)"` — `\n` is not `HREF_SAFE`, so it is percent-escaped, not a literal control char the URL parser would strip | no (reasoned; see §3.4) |
| `[x](\javascript:alert(1))` | `href="%5Cjavascript:..."` — `cmark_strbuf_unescape` only drops `\` before punctuation, and `j` is not punctuation | no |
| `![a](x.png" onerror="alert(1))` | `"` → `%22` via `escape_href` | no |
| `![a](data:image/png,<svg onload=alert(1)>)` | **permitted** by `SAFE_DATA_IMAGE_PATTERN` → `<img src="data:image/png,%3Csvg…">` | no — declared type is `image/png`; browsers use the declared MIME for `data:` and do not sniff (reasoned) |
| `[x](data:image/png;base64,…)` as a **link** | **permitted** → `<a href="data:image/png;base64,…">` | no — top-level `data:` navigation is blocked in current browsers (reasoned) |
| blank line, `https://gist.github.com/<attacker>/deadbeef`, blank line | `<script src="https://gist.github.com/<attacker>/deadbeef.js"></script>` | **yes — third-party script in the portal origin** |
| blank line, `https://x.wistia.com/medias/ID`, blank line | 2 × `<script src="https://fast.wistia.com/…">` | **yes** |
| `*"Not supported on <inbox>"*` | `<inbox>` is a spec-valid open tag → inline_html → `<!-- raw HTML omitted -->`; the reader sees `"Not supported on "` | n/a — **live content loss** |
| `![a^b^c](x.png)` | `alt="a<sup>b</sup>c"` — `#text` runs inside the `plain` alt capture | no (cosmetic) |

### 3.3 Findings table

| ID | Claim | Evidence | Impact | Severity | Reachable today? |
|---|---|---|---|---|---|
| F1 | Any author can publish a third-party `<script src>` by writing a Gist or Wistia link on its own line | `config/markdown_embeds.yml:87-92,151-154`; `custom_markdown_renderer.rb:54-59,164-172,198-209`; `spec/lib/custom_markdown_renderer_spec.rb:215` | Script executes in the portal origin. Gist content is attacker-authored; GitHub's `.js` endpoint uses `document.write`. An author needs no HTML and no exploit — one Markdown link | **major** | yes |
| F2 | The portal's CSP contains no `script-src`, `default-src`, `frame-src` or `frame-ancestors` | `config/initializers/content_security_policy.rb:14-17`; middleware at `actionpack-7.2.3.2/.../content_security_policy.rb:37-56` | Zero containment. F1 is unmitigated, and any future renderer or editor mistake is unmitigated | **major** | yes |
| F3 | `?show_plain_layout=true` deletes `X-Frame-Options` and no `frame-ancestors` replaces it | `app/controllers/public/api/v1/portals/base_controller.rb:4,14-16,66-68` | Any origin can frame any article at a guessable URL. This is also the Super Admin preview URL (`01-current-system.md` §6) | major | yes |
| F4 | Raw HTML is deleted, not escaped, so prose containing a tag-shaped token is silently lost | `html_renderer.rb:110-126`; live at `custom/db/documentation/en/automation/flow-builder.md:31` — `*"Not supported on <inbox>"*`, in emphasis, not a code span | The published EN article reads *"Not supported on "*. Arabic has no such token, so EN/AR also diverge | minor (security) / **major** (content) | **yes, in production** |
| F5 | `SAFE_DATA_IMAGE_PATTERN` is a prefix match and is applied to `<a href>` as well as `<img src>` | `markdown_renderer_url_sanitizer.rb:4,16` | `data:` links survive the deny-list. Not exploitable in current browsers; it is an unnecessary exception on the wrong element | minor | yes |
| F6 | Scheme policy is a deny-list of four, not an allowlist | `markdown_renderer_url_sanitizer.rb:3` | Every other scheme passes (`blob:`, `filesystem:`, `view-source:`, custom handlers). Intentional, for `mention://` — but the comment claims parity with "CommonMarker's native safe renderer", which uses an allowlist | minor | yes |
| F7 | Enabling `:UNSAFE` would not enable `tagfilter`, because the renderer is built with `extensions: []` | `chatwoot_markdown_renderer.rb:14`; `renderer.rb:10,17,105-121` | A future "let authors write HTML" change that looks like a one-flag change is actually a full XSS hole | minor now, **blocker if taken** | no |
| F8 | No iframe carries `sandbox` or `referrerpolicy`; `clipboard-write` is delegated to YouTube and GuideJar frames | `markdown_embeds.yml:17-22,143-148` | Broader third-party frame capability than the content needs | minor | yes |
| F9 | `#text`'s `^…^` handling emits literal `<sup>` into `alt=""` | `custom_markdown_renderer.rb:43-52,65`, `:211-219`; `renderer.rb:40-41,88-93` | Alt text reads `a<sup>b</sup>c`. No breakout — `escape_html` kills the quote. Hurts accessibility once alt text is mandatory | minor | yes (no images in the corpus yet) |
| F10 | The editor preview and the publish renderer are different code with different embed sets | `markdownEmbeds.js:1-12` vs `custom_markdown_renderer.rb:187-209`; `embedPreview.js:36-42` vs `CGI.escapeHTML` | WYSIWYG is false precisely for the dangerous case | major (for the editor programme) | yes |

**Checked and safe, recorded so nobody re-checks it:**

- The second `html_safe` on the article page is correctly escaped:
  `tag.script(json_escape(payload.to_json).html_safe, type: 'application/ld+json')`
  (`custom/app/helpers/documentation_helper.rb:99-101`). `json_escape` converts `<`, `>`, `&` to `<`-style
  escapes, so an article title cannot close the `<script>`.
- `set_og_image_url` builds its URL with `URI.encode_www_form` (`app/helpers/portal_helper.rb:11-15`), so the
  `.html_safe` on `<meta content="<%= og_image_url.html_safe %>">`
  (`documentation_layout/articles/_meta_head.html.erb:59-60`) cannot be broken out of.
- Search snippets call `render_markdown_to_plain_text` (`portal_helper.rb:96-98`), which returns a plain String; ERB
  escapes it at `search/_results.html.erb:27`.
- `draft_content` never reaches the public portal — it exists only on the account-scoped API
  (`app/controllers/api/v1/accounts/articles_controller.rb:100,111`). `#show` renders `@article.content`.
- `custom/db/documentation/en/integrations/webhooks.md:80` (fenced block) and `:135` (code span) are safe:
  `code_block` and `code` both route through `escape_html` (`html_renderer.rb:105,159-163`).
- The corpus today contains **zero images and zero embed links** —
  `grep -rn "!\[" custom/db/documentation/` and a grep for all eleven embed hosts across
  `custom/db/documentation/` and `custom/db/changelog/` both return nothing. F1 and F9 are latent in the corpus but
  live in the code, and the editor programme is specifically about adding media.
- The `platform_support` module's claim that *"both renderers escape by default, so there is nothing to sanitize"*
  (`custom/app/models/platform_support/message.rb:43-44`) is right about the outcome and wrong about the mechanism on
  the server side: the server omits, it does not escape. Worth correcting so nobody reasons from "escapes" to
  "escaping is the control".

### 3.4 Unverified

Four claims rest on browser behaviour, not on this repository, and I did not run anything:

1. `href="java%0Ascript:alert(1)"` is inert because the URL parser strips literal tab/LF/CR but not their
   percent-encoded forms.
2. `<img src="data:image/png,<svg …>">` does not execute because `data:` URLs are typed by their declared MIME and
   are not content-sniffed.
3. `<a href="data:image/png;base64,…">` does not execute because top-level `data:` navigation is blocked.
4. `<inbox>` is parsed as inline HTML. I verified cmark routes `<` through `handle_pointy_brace` →
   `scan_html_tag` (`ext/commonmarker/inlines.c:913-940`, `scanners.h:16,42`), which is the generic CommonMark open-tag
   production with no tag-name allowlist — but the scanner itself is re2c-generated and I read its contract, not its
   state machine.

**The experiment that settles all four, without a server:** one RSpec file that renders each payload through
`ChatwootMarkdownRenderer.new(payload).render_article` and asserts the exact output string — that settles (4)
outright and pins the exact markup for (1)–(3). For (1)–(3) themselves, load that recorded markup as a static HTML
file in current Chrome, Firefox and Safari with a `window.alert` spy. Neither needs this application running, a
database, or a deploy.

---

## 4. Options

**Decision A — what to do about F1 (the script-emitting embeds).** This is the one the orchestrator must arbitrate,
because it is a product decision dressed as a security one.

| Option | Trade-off |
|---|---|
| A1. Drop `github_gist` and `wistia` from `config/markdown_embeds.yml` | Smallest change; removes the only author-reachable `<script>` in the portal. Costs two embed types the corpus does not use today. The editor already refuses to preview the gist, which is evidence nobody relies on it |
| A2. Keep them, add a `script-src` allowlist naming `fast.wistia.com` and `gist.github.com` | Keeps the feature, documents the trust, but writes two third-party script origins into the installation's permanent policy — including a host whose content is authored by strangers |
| A3. Per-embed gate (an allowlist of embed keys the documentation portals may use) | Most flexible, most machinery, and a second configuration surface to keep correct |

**Recommendation: A1 now, and treat the embed list as a security-reviewed allowlist from here on.** The corpus uses
no embeds at all, so the cost today is zero and the benefit is removing the only path from "author writes a link" to
"script runs". A2 is the wrong shape for `gist.github.com` specifically: the point of a gist is that anyone can
create one, so allowlisting that origin allowlists an attacker-controlled script host. Note that embed templates are
*the* thing to extend here (program rule §2) — the fix is editing the existing YAML, not building a second embed
system.

**Decision B — what to do about F2 (the CSP).** The initializer already names the plan: *"Stage two adds those,
report-only first"*. The portal is the right place to start, because it is the one surface that renders
third-party-authored content and loads the fewest script sources.

| Option | Trade-off |
|---|---|
| B1. One global stage-two policy for dashboard + widget + SDK + portal | One policy to maintain; must enumerate every source any surface loads, and a miss breaks production. Slowest to land |
| B2. A portal-scoped policy via `content_security_policy` in `Public::Api::V1::Portals::BaseController`, report-only first | Uses the existing Rails per-controller override. Small source set to enumerate (own assets, `ASSET_CDN_HOST`, fonts, whatever embeds survive Decision A). Lands independently of the dashboard |
| B3. Do nothing until the editor ships | Leaves F1 unmitigated and means the editor ships into an environment with no containment — exactly the order §5 of `01-current-system.md` warns about |

**Recommendation: B2, report-only first, with `frame-ancestors` included so it also closes F3.** It extends the
existing initializer's own staged plan rather than replacing it, and it scopes the enumeration problem down to one
controller whose asset list is short and known.

**Decision C — raw HTML in article prose (F4).** Three honest choices: (C1) leave omission and fix the corpus, adding
a CI check that rejects tag-shaped tokens outside code spans; (C2) switch to escaping, which means emitting author
HTML as text and is a renderer change affecting messages and email too; (C3) enable `:UNSAFE` plus a real sanitizer.
**Recommend C1.** It is the smallest change, it keeps the renderer's single safest property intact, and the actual
defect is three characters of corpus. C3 is the option that must not be taken casually — see F7.

---

## 5. Risks

1. **The editor upgrade is being designed against a renderer that deletes HTML.** A WYSIWYG editor that round-trips
   through Markdown is fine. A WYSIWYG editor that stores HTML, or that offers "paste as HTML", or an "embed code"
   field, requires `:UNSAFE` — and F7 says that flag alone silently skips `tagfilter`. Any such proposal is a
   sanitizer decision, not a flag decision, and `00-program.md` §2 forbids a second sanitizer: the control has to be
   added to this path, not beside it.
2. **The embed list is the attack surface that grows.** Every new entry in `config/markdown_embeds.yml` is raw HTML
   with no sanitizer behind it and, today, no CSP in front of it. It needs a named reviewer and a rule — no `<script>`
   templates, every capture inside a quoted attribute, every iframe sandboxed — before the list grows for the
   richer-content work in streams covering components (agent 071) and media (068).
3. **Media authoring will exercise paths nothing has exercised.** The corpus has zero images today, so F9 (`<sup>` in
   `alt`), the `cw_image_width` bounds, and the `data:image/*` exception (F5) are all untested by real content.
   ActiveStorage URLs will also be the first author-supplied `src` values in the corpus (agents 066, 083, 084).
4. **Two renderers will drift.** `config/markdown_embeds.yml` is shared, but the escaping, the engines and the embed
   sets already differ (F10). A richer editor widens that gap, and the gap's failure mode is an author publishing
   something they could not see.
5. **F3 compounds with the Super Admin preview.** The preview URL is `?show_plain_layout=true`
   (`01-current-system.md` §6), which is the exact parameter that deletes `X-Frame-Options`. A framed draft preview
   plus a logged-in super admin is a worse combination than a framed published article.
6. **Nothing in CI asserts the raw-HTML property.** `spec/lib/custom_markdown_renderer_spec.rb:31-37` is the only
   test of it, it tests one payload, and it tests the renderer rather than the published response. A dependency bump
   that changes the gem's default, or a future `options:` argument at
   `chatwoot_markdown_renderer.rb:14`, would not be caught by the article-level specs.
