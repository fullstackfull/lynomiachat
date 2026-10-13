---
agent: 081
scope: XSS in documentation article content, and the sanitizer — if there is one
confidence: high
---

# XSS and the article sanitizer

**There is no sanitizer.** `01-current-system.md` §5 left the question open and flagged it as "the single most
important security question in the program". This report closes it: raw HTML in article Markdown *is* dropped,
but not by a sanitizer — by CommonMarker's default "omit raw HTML" renderer mode. Nothing in the article render
path calls `sanitize`, Loofah, `Rails::HTML`, or any allowlist. The output is `html_safe`'d unconditionally and
printed raw. That distinction matters, because the charter's own extension table (§2) promises to extend
"the existing article render path" rather than add "a second sanitizer" — and the existing article render path
has no sanitizer to extend. Agent 000 must arbitrate that row.

Two further things make the picture worse than "CommonMarker handles it":

1. The **embed system re-introduces** exactly the raw HTML the renderer strips — including two `<script src>`
   templates and nine `<iframe>` templates — triggered by nothing more than a URL on a line by itself.
2. The article page is served from the **same origin** as `/super_admin` and the agent dashboard, and the
   Super Admin preview deliberately renders *unpublished* drafts there. There is no CSP `script-src`.

---

## 1. Attack surface

| # | Surface | `file:line` | Who writes the input |
|---|---|---|---|
| A | `Article#content` (CommonMark) → HTML → printed raw on the public portal | `app/controllers/public/api/v1/portals/articles_controller.rb:26,109-111` → `app/views/public/api/v1/portals/articles/_content.html.erb:18` | Super admin (docs portal); **any account user with HC access** (tenant portals) |
| B | Markdown link URL → embed template → raw `<script>`/`<iframe>` | `lib/custom_markdown_renderer.rb:54-59,164-209` + `config/markdown_embeds.yml` | same as A |
| C | Image / link URL → `src` / `href` attribute | `lib/custom_markdown_renderer.rb:61-71`, `lib/base_markdown_renderer.rb:4-9,48-60`, `lib/markdown_renderer_url_sanitizer.rb:6-19` | same as A |
| D | `Article#title` → `<title>`, `<meta content>`, JSON-LD, OG image URL | `app/views/public/api/v1/portals/articles/_meta_head.html.erb:2,18-20`; `.../documentation_layout/articles/_meta_head.html.erb:10,26,38,50,59-60,64-65`; `custom/app/helpers/documentation_helper.rb:67,86,99-101` | same as A |
| E | `Article#meta` jsonb (`title`, `description`, `tags`, `version`, `release_date`, `feature_image`) | `custom/app/fields/article_meta_field.rb`; `custom/app/views/fields/article_meta_field/_{show,index,form}.html.erb`; `.../documentation_layout/articles/_release_meta.html.erb:5-26`; `_meta_head.html.erb:3-15` | Super admin form (key-allowlisted) + HC API (`articles_controller.rb:111-113`) + Markdown front matter |
| F | Super Admin **preview** — unpublished draft rendered on the main app origin | `custom/app/controllers/super_admin/articles_controller.rb:22-25`; `articles_controller.rb:80-88`; `config/routes.rb:519` | super admin's own browser |
| G | Dashboard HC editor: diff preview `v-html`, ProseMirror embed previews | `app/javascript/dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleDiffPanel.vue:152,165`; `app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue:108` | agent / future doc author |
| H | Markdown files in a pull request → seeded verbatim into `content` | `custom/app/services/documentation/content_seeder.rb:70-104,126-131` | anyone who lands a PR |

Nothing is gated by a Content Security Policy that would matter here: the policy sets only `object-src 'none'`
and `base-uri 'self'`, and the comment says `script-src` is deliberately absent —
`config/initializers/content_security_policy.rb:14-17`.

## 2. What the existing defence actually does

### 2.1 The option set, and whether raw HTML survives

`render_article` constructs the renderer with **no** `options:` argument and parses with `:DEFAULT`:

```ruby
# lib/chatwoot_markdown_renderer.rb:13-19
def render_article
  markdown_renderer = CustomMarkdownRenderer.new
  doc = CommonMarker.render_doc(@content, :DEFAULT, [:table])
  html = markdown_renderer.render(doc)

  render_as_html_safe(html)
end
```

`CustomMarkdownRenderer < CommonMarker::HtmlRenderer < CommonMarker::Renderer`, whose initializer defaults the
render option set and resolves it against the `:render` table:

```ruby
# vendor/bundle/ruby/3.4.0/gems/commonmarker-0.23.12/lib/commonmarker/renderer.rb:10-11
def initialize(options: :DEFAULT, extensions: [])
  @opts = Config.process_options(options, :render)
```

```ruby
# .../lib/commonmarker/config.rb:18-22
render: {
  DEFAULT: 0,
  SOURCEPOS: (1 << 1),
  HARDBREAKS: (1 << 2),
  UNSAFE: (1 << 17),
```

So `@opts == 0` and `UNSAFE` is off. The gem's HTML renderer then discards raw HTML in both block and inline
position:

```ruby
# .../lib/commonmarker/renderer/html_renderer.rb:110-126
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

**Decisive: raw HTML typed or pasted into article Markdown does not survive.** `<script>alert(1)</script>`,
`<img src=x onerror=alert(1)>`, `<svg onload=alert(1)>`, `<iframe>`, `<style>`, `<base>` and `<form>` all
become the literal comment `<!-- raw HTML omitted -->`. Note it is *omission*, not escaping: the content is
not shown as text either.

`CustomMarkdownRenderer` overrides `html` only to harvest the editor's column-width marker:

```ruby
# lib/custom_markdown_renderer.rb:22-27
def html(node)
  match = node.string_content.match(COLWIDTHS_COMMENT)
  return super unless match

  @pending_colwidths = match[1].split(',').map(&:to_i)
end
```

I attacked this override specifically. `COLWIDTHS_COMMENT = /<!--cw-colwidths:([\d,]+)-->/` (`:17`) is
unanchored, so `<!--cw-colwidths:1,1--><script>alert(1)</script>` on one line is a single CommonMark HTML block
(type 2 ends on the line containing `-->`) whose `string_content` matches — and the method then returns the
width array **without calling `out` at all**, so the whole node including the `<script>` is dropped. The
override fails safe. `inline_html` is not overridden, so inline raw HTML still reaches the gem's omission path.
Only digits and commas reach `colgroup_html`/`table_sizing_style` (`:118-128`), and `inject_table_sizing`'s
`html.sub(/<table[^>]*>\n?/, opening)` (`:97`) is given a replacement string containing no backslash, so
`String#sub` back-reference interpretation is not reachable.

### 2.2 The URL check — a four-scheme denylist that happens to hold

```ruby
# lib/markdown_renderer_url_sanitizer.rb:1-19
module MarkdownRendererUrlSanitizer
  # Match CommonMarker's native safe renderer while retaining application protocols such as mention://.
  DANGEROUS_URL_PATTERN = /\A(?:javascript:|vbscript:|file:|data:)/i
  SAFE_DATA_IMAGE_PATTERN = %r{\Adata:image/(?:png|gif|jpeg|webp)}i
  ...
  def sanitized_href(url)
    url = url.to_s
    return '' if url.match?(DANGEROUS_URL_PATTERN) && !url.match?(SAFE_DATA_IMAGE_PATTERN)

    escape_href(url)
  end
end
```

The comment's claim is accurate — this is a faithful port of cmark's own scanner, exemption included:

```c
/* vendor/.../commonmarker-0.23.12/ext/commonmarker/scanners.re:319-330 */
// Returns positive value if a URL begins in a way that is potentially
// dangerous, with javascript:, vbscript:, file:, or data:, otherwise 0.
bufsize_t _scan_dangerous_url(const unsigned char *p)
...
  'data:image/' ('png'|'gif'|'jpeg'|'webp') { return 0; }
  'javascript:' | 'vbscript:' | 'file:' | 'data:' { return (bufsize_t)(p - start); }
```

I tried the classic ways round a prefix-anchored scheme denylist and they all fail, because of the escaper that
runs afterwards. CommonMark decodes entity references inside link destinations, so
`[x](jav&#x09;ascript:alert(1))` yields `node.url == "jav\tascript:alert(1)"`, which does not match
`DANGEROUS_URL_PATTERN` — but `escape_href` is cmark's `houdini_escape_href`, whose safe table marks every
byte 0x00–0x20 and `"` as unsafe and percent-encodes them:

```c
/* ext/commonmarker/houdini_href_e.c:32-44 (first rows) */
static const char HREF_SAFE[] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1,
```

Index 9 (tab) and index 34 (`"`) are `0`, so the rendered attribute is
`href="jav%09ascript:alert(1)"` — `jav%09ascript` is not a valid URL scheme, so the browser treats it as a
relative path. The same table is why no image or link URL can break out of its own `src="…"`/`href="…"`.
Leading whitespace is stripped by CommonMark's destination parser before the regex sees it, and `/i` covers
case games. The `data:image/png` exemption is not a hole either: top-level navigation to `data:` is blocked in
all current browsers, and a `data:image/png` payload containing SVG markup is not parsed as SVG.

Attribute text goes through cmark's HTML escaper, which always escapes `"` (`&quot;`), `&`, `<`, `>` and, in
non-secure mode, leaves `'` and `/` alone — `houdini_html_e.c:18-33`, called with `secure = 0` from
`commonmarker.c:1198-1199`. Every use in this codebase puts it inside a double-quoted attribute
(`lib/custom_markdown_renderer.rb:67`, `lib/base_markdown_renderer.rb:49`) or in element text
(`custom_markdown_renderer.rb:50,214-216`), so no break-out.

### 2.3 Then `html_safe`, with no second line of defence

```ruby
# lib/chatwoot_markdown_renderer.rb:27-31
def render_as_html_safe(html)
  # rubocop:disable Rails/OutputSafety
  html.html_safe
  # rubocop:enable Rails/OutputSafety
end
```

printed as `<%= parsed_content %>` at `app/views/public/api/v1/portals/articles/_content.html.erb:18`, from all
three layouts (`show.html.erb:16` → `_article_body.html.erb:5`; `show.html+plain.erb:12`;
`show.html+documentation.erb:16`). `rails-html-sanitizer 1.7.1` and `loofah 2.25.2` are in `Gemfile.lock:533,728`
as transitive Rails dependencies and are never invoked on this HTML.

## 3. Findings

Severity assumes the origin fact established in F9: the article page and `/super_admin` share an origin, and
there is no `script-src`.

### F1 — `blocker` (design gap, reachable today): no sanitizer exists, so the whole defence is one option bit

**Claim.** The only thing preventing stored XSS in documentation article content is `UNSAFE` being absent from a
default-constructed renderer. There is no allowlist, no post-render sanitization pass, and no test that would
notice if that changed.

**Evidence.** `lib/chatwoot_markdown_renderer.rb:13-19,27-31`; `renderer.rb:10-11`; `config.rb:18-22`;
`html_renderer.rb:110-126`; no `sanitize`/Loofah call in `lib/*markdown*`, `app/views/public/`,
`app/controllers/public/` or `custom/app/`. `spec/lib/chatwoot_markdown_renderer_spec.rb` (132 lines) and
`spec/lib/chatwoot_markdown_renderer_editor_output_spec.rb` (88 lines) contain no `<script>`, `javascript:`,
`onerror` or raw-HTML-omission assertion — the single `script` match is line 89 asserting that a Wistia
`<script>` *is* emitted.

**Impact.** A one-word change (`CustomMarkdownRenderer.new(options: :UNSAFE)`, or adopting an editor that needs
`:UNSAFE` to round-trip its own markup) converts every article into a same-origin script injection, and CI would
stay green. The charter's extension table says sanitization should extend "the existing article render path"
rather than add "a second sanitizer"; there is no first sanitizer, so that row cannot be honoured as written.

**Reachable:** the *gap* is today. Exploitation requires one of F3/F4 or a renderer change.

### F2 — `major` (reachable today): the embed system re-injects the raw HTML the renderer strips, including `<script>`

**Claim.** A bare URL on its own line is enough to emit an unescaped third-party `<script src>` or `<iframe>`
into the article page, bypassing §2.1 entirely.

**Evidence.**

```ruby
# lib/custom_markdown_renderer.rb:54-59
def link(node)
  return if surrounded_by_empty_lines?(node) && render_embedded_content(node)

  # If it's not a supported embed link, render normally
  super
end
```

`render_embedded_content` → `find_matching_embed` → `render_embed_from_match` (`:164-209`) looks the URL up
against `config/markdown_embeds.yml` and `out`s the matching template verbatim. Concrete payloads, both valid
CommonMark that an author can paste or a PR can land:

| Payload (alone on a line, blank line either side) | Emitted | Source |
|---|---|---|
| `https://gist.github.com/anyuser/deadbeef` | `<script src="https://gist.github.com/anyuser/deadbeef.js"></script>` | `config/markdown_embeds.yml:151-154` |
| `https://x.wistia.com/medias/AAAA` | `<script src="https://fast.wistia.com/player.js" async></script>` + `<script src="https://fast.wistia.com/embed/AAAA.js" async type="module"></script>` + a `<style>` block | `config/markdown_embeds.yml:87-106` |
| `https://codepen.io/u/pen/x` | `<iframe src="https://codepen.io/u/embed/x?default-tab=result">` | `config/markdown_embeds.yml:122-137` |
| `https://evil.example/a.mp4` | `<video><source src="https://evil.example/a.mp4"></video>` | `config/markdown_embeds.yml:47-55` (`.+\.mp4`, any host) |

The Wistia behaviour is pinned by `spec/lib/chatwoot_markdown_renderer_spec.rb:89`, so it is intentional, not an
accident.

**Impact.** Whatever `gist.github.com` and `fast.wistia.com` serve runs with the privileges of the article page —
which is the privileges of `/super_admin` and `/app` (F9). The gist template is worse than the rest: the path is
author-controlled (`(?<username>[^/]+)/(?<gist_id>[a-f0-9]+)`) and GitHub Gist content is attacker-publishable
by anyone with a GitHub account, so "a URL pasted into an article" is a fully attacker-controlled script load
with no review step that looks like code. `object-src 'none'` does not cover `<script>` or `<iframe>`, and there
is no `script-src`/`frame-src` (`content_security_policy.rb:14-17`).

What I could *not* break, and tried: the capture groups are escaped — `render_embed_from_match` applies
`CGI.escapeHTML` to every named capture (`custom_markdown_renderer.rb:205-207`), which covers `& " ' < >`, so no
attribute break-out. The Wistia template interpolates `%{video_id}` inside a `<style>` block
(`markdown_embeds.yml:93-100`), where HTML entities are *not* decoded — but that cuts both ways: `&#39;` cannot
terminate the CSS string and `&lt;/style&gt;` cannot close the element, so CSS injection there fails too.
`apply_embed_width` round-trips the template through `Nokogiri::HTML5.fragment` (`:177-185`) and only writes a
`style` built from a bounded `\d+px` (`:141-146`).

**Reachable: today**, on both the documentation portal and every tenant portal.

### F3 — `major` (today in the HC editor; lands on the documentation path with the editor upgrade): the ProseMirror embed preview deliberately re-executes `<script>` in the dashboard

**Claim.** The editor's embed preview assigns template HTML to `innerHTML` and then goes out of its way to make
the `<script>` tags inside it execute, inside the authenticated dashboard origin.

**Evidence.**

```js
// node_modules/@chatwoot/prosemirror-schema/dist/index.es.js:5059-5077
} = {}) => (view, getPos) => {
  const wrapper = document.createElement("div");
  wrapper.className = "cw-embed-preview";
  wrapper.contentEditable = "false";
  wrapper.innerHTML = html;
  const savedWidth = url && embedWidth(url);
  if (savedWidth) wrapper.style.width = `${savedWidth}px`;
  // innerHTML doesn't execute <script> tags — re-create them so they do.
  wrapper.querySelectorAll("script").forEach(stale => {
    const fresh = document.createElement("script");
    Array.from(stale.attributes).forEach(({ name, value }) => fresh.setAttribute(name, value));
    fresh.textContent = stale.textContent;
    stale.replaceWith(fresh);
  });
```

Wired up at `app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue:108`
(`embedPreviewPlugin(markdownEmbeds)`).

**Impact.** Typing or pasting a Wistia link into the HC article editor loads remote JS into the dashboard origin.
Today the gist template — the one with an author-controlled path — is excluded from the editor's embed set:

```js
// app/javascript/dashboard/helper/markdownEmbeds.js:3-7
// Gists rely on document.write() and can't render inline in the editor.
const NON_PREVIEWABLE_EMBEDS = new Set(['github_gist']);
```

That exclusion is for a rendering reason, not a security reason, and it is the only thing keeping an
attacker-controlled script out of this path. The capture escaping is correctly mirrored on the JS side
(`index.es.js:4953-4954`, same five characters as `CGI.escapeHTML`).

**Reachable:** today for tenant Help Center articles. **Not yet** for documentation articles — Super Admin
authors in a plain textarea (`custom/app/dashboards/article_dashboard.rb:19`,
`Field::Text.with_options(rows: 28)`). Adopting `FullEditor` for documentation, which is the obvious move for
agents 063/067, imports this primitive into the super admin's own browser.

### F4 — `major` (reachable today): Super Admin preview executes an *unreviewed* draft same-origin with `/super_admin`

**Claim.** The preview is a pre-review execution surface on the privileged origin, which is exactly threat (d).

**Evidence.**

```ruby
# custom/app/controllers/super_admin/articles_controller.rb:22-25
def preview
  article = requested_resource
  redirect_to "/hc/#{article.portal.slug}/articles/#{article.slug}?show_plain_layout=true"
end
```

That is a *relative* path, served by the main application: `config/routes.rb:519`
(`get 'hc/:slug/articles/:article_slug', to: 'public/api/v1/portals/articles#show'`), and
`app/controllers/public_controller.rb:9-20` accepts the installation's own domain. So the page renders on the
same origin as `/super_admin`, `/app` and the API. And the lookup is widened for exactly this case:

```ruby
# app/controllers/public/api/v1/portals/articles_controller.rb:80-88
def set_article
  scope = previewing_as_super_admin? ? @portal.articles : @portal.articles.published
  @article = scope.find_by!(slug: permitted_params[:article_slug])
end

def previewing_as_super_admin?
  respond_to?(:current_super_admin) && current_super_admin.present?
end
```

**Impact.** Content that has not been published, reviewed or approved by anyone executes in the super admin's
browser with their session, one click from the Administrate show page. The usual mitigation — "a super admin
wrote it, so it is trusted" — is precisely what fails for threats (a) paste-from-untrusted and (b) PR Markdown:
the author is trusted, the *content* is not. Combined with F2 this is live today; combined with F1 it is what
makes an `:UNSAFE` regression a super-admin account takeover rather than a defacement.

I am not arguing the preview should be removed. It should not be same-origin, and it should not be the first
place unvetted bytes get to run.

### F5 — `major` (reachable today, vector (b)): PR Markdown reaches `content` with no validation at all

**Claim.** `Documentation::ContentSeeder` writes the file body straight into `Article#content`.

**Evidence.** `custom/app/services/documentation/content_seeder.rb:71` (`front_matter, body = split(File.read(path))`),
`:98` (`content: body`), `:101` (`status: @publish ? :published : :draft` — default `publish: true`, `:20`), and
`:126-131`, where only the front matter is parsed (`YAML.safe_load`, correctly). `front_matter.fetch('title')`
(`:96`) and `meta_for` (`:106-113`) are likewise taken verbatim. The seeder publishes by default, so a merged
`.md` file becomes a published, publicly-served article the next time `rails documentation:content` runs.

**Impact.** The review gate for article content is code review of a Markdown file — where an embed URL
(F2) looks like a perfectly ordinary documentation link and a reviewer has no reason to read it as a script
load. There is no CI check on corpus content.

### F6 — `minor` (reachable today): JS/Ruby asymmetry on `cw_image_width` lets CSS into the dashboard preview

**Claim.** The Ruby renderers validate the image sizing parameter; the JS formatter does not, so arbitrary CSS
declarations land in a `style` attribute in the authenticated dashboard.

**Evidence.** Ruby validates and bounds it:

```ruby
# lib/base_markdown_renderer.rb:32-39
# Only allow a bounded `<digits>px` value so the decoded query param can't
# break out of the inline style attribute (HTML attribute injection).
def sanitize_pixel_value(raw)
  return unless raw =~ /\A(\d+)px\z/

  px = Regexp.last_match(1).to_i
  "#{px}px" if px.between?(1, 2000)
end
```

(same in `lib/custom_markdown_renderer.rb:141-146`). The JS twin does not:

```js
// app/javascript/shared/helpers/MessageFormatter.js:5-19
const setImageSizing = inlineToken => {
  const imgSrc = inlineToken.attrGet('src');
  if (!imgSrc) return;
  const url = new URL(imgSrc);
  const width = url.searchParams.get('cw_image_width');
  if (width) {
    inlineToken.attrSet('style', `width: ${width}; max-width: 100%; height: auto;`);
```

Payload: `![x](https://h/i.png?cw_image_width=1px;position:fixed;inset:0;width:100vw;height:100vh;z-index:9999;background:url(https://attacker.example/ping))`,
rendered via `v-html` at `ArticleDiffPanel.vue:165`.

**Impact.** No script and no attribute break-out — markdown-it HTML-escapes attribute values and runs with
`html: false` (`MessageFormatter.js:44-46`) — but a full-viewport fixed overlay inside an authenticated page is a
clickjacking primitive, and the `background:url()` leaks a page view to an attacker-chosen host. It is also a
correctness defect: the two renderers disagree about what a valid width is.

**Reachable: today** in the dashboard diff panel; the same formatter backs message rendering.

### F7 — `minor` (latent): `og_image_url.html_safe` puts an author-controlled title one escaping bug from attribute injection

**Claim.** Safe today, unnecessary, and the wrong shape.

**Evidence.** `app/controllers/public/api/v1/portals/articles_controller.rb:25` builds it from the article title,
and both meta-head partials print it with `.html_safe`:
`app/views/public/api/v1/portals/articles/_meta_head.html.erb:18-20` and
`app/views/public/api/v1/portals/documentation_layout/articles/_meta_head.html.erb:59-60`. It holds only because
the builder percent-encodes the whole query string:

```ruby
# app/helpers/portal_helper.rb:11-15
uri.query = URI.encode_www_form(
  clientRef: client_ref,
  title: title,
  portalName: portal_name
)
```

**Impact.** `URI.encode_www_form` encodes `"` as `%22`, so there is no break-out today. But the `.html_safe` buys
nothing — `&amp;` inside an attribute value is correct HTML and browsers decode it — while removing the only
backstop between `Article#title` and `<meta content="…">`. Drop the `.html_safe`.

### F8 — `minor` (adjacent, flagged for 085/086): `@portal.color` is interpolated into a `<style>` block

**Evidence.** `app/views/layouts/_portal_scripts.html.erb:27-41`, e.g.
`--dynamic-portal-color: <%= @portal.color %>;`. ERB escaping does not protect a CSS context — `<style>` content
is RAWTEXT, so entities are never decoded, and a colour value of `red;}html{display:none}` injects rules without
needing a quote. Not XSS (no `expression()` in current browsers) and the input is portal configuration rather
than article content, so it is a trusted-actor defacement/exfiltration path rather than an author one. Related:
`@portal.channel_web_widget.web_widget_script.html_safe` at `:101`. Out of my scope; recording it so it is not
lost.

## 3a. What survived — I tried these and could not break them

These matter as much as the findings, and three of them are things the brief asked me to test specifically.

**JSON-LD injection via a title containing `</script>` — does not work.** This is the hole the brief called
"real and commonly missed", so I read the emitting code rather than reasoning about it:

```ruby
# custom/app/helpers/documentation_helper.rb:97-101
# One <script type="application/ld+json">. `to_json` escapes the content, and the result is injected with
# `json_escape` so a `</script>` inside a title cannot break out of the block.
def documentation_structured_data(payload)
  tag.script(json_escape(payload.to_json).html_safe, type: 'application/ld+json') # rubocop:disable Rails/OutputSafety
end
```

The comment is correct and the implementation matches it. `ERB::Util.json_escape` rewrites `<`, `>`, `&`,
U+2028 and U+2029 to `<`, `>`, `&`, ` `, ` `. Inside a JSON string those decode back to
the right characters for a structured-data consumer, but the HTML tokenizer never sees a `<`, so `</script>`
cannot be formed. A title of `Foo</script><script>alert(1)</script>` emits
`"headline":"Foo</script><script>alert(1)</script>"`. It is belt-and-braces:
`config.load_defaults 7.0` (`config/application.rb:39`) leaves `ActiveSupport.escape_html_entities_in_json`
at its default `true`, so `to_json` has already escaped those characters before `json_escape` runs, and nothing
in `config/` overrides it. The `.html_safe` is load-bearing and correct here — HTML-escaping the payload would
corrupt the JSON, since entities are not decoded inside `<script>`. Both callers are
`documentation_layout/articles/_meta_head.html.erb:64-65`, carrying `article.title` (`documentation_helper.rb:67,86`)
and `article.meta['description']` (`:87`).

**Super Admin Administrate pages never render the body unescaped.** `SHOW_PAGE_ATTRIBUTES` includes `content`
(`custom/app/dashboards/article_dashboard.rb:32-34`) as `Field::Text` (`:19`), and there is no article-specific
view override anywhere under `app/views/super_admin/` or `custom/app/views/super_admin/`. So the generic chain
applies: `app/views/super_admin/application/show.html.erb:60` (`<%= render_field attribute, page: page %>`) →
`vendor/bundle/ruby/3.4.0/gems/administrate-0.20.1/app/views/fields/text/_show.html.erb:18`
(`<div class="preserve-whitespace"><%= field.data %></div>`), ERB-escaped. Index is
`.../fields/text/_index.html.erb:18` (`<%= field.truncate %>`). The only `html_safe` in the Administrate views is
the flash partial (`.../application/_flashes.html.erb:18`, mirrored at
`app/views/super_admin/application/_flashes.html.erb:17`), which carries I18n strings, not article content. **The
Super Admin show and edit pages are clean; the exposure is the preview (F4), which leaves Administrate.**

**`ArticleMetaField`'s views are escaped.** All three are `<%= field.to_s %>`
(`custom/app/views/fields/article_meta_field/_show.html.erb:1`, `_index.html.erb:1`) over a plain String built by
`ArticleMetaField#to_s` (`custom/app/fields/article_meta_field.rb:49-54`) — not `html_safe`, so ERB escapes it.
The form writes `value="<%= field.value_for(key) %>"` (`_form.html.erb:11`) and
`value="<%= field.tags %>"` (`:19`), also escaped. Same for `ArticleAuthorField`
(`custom/app/fields/article_author_field.rb:11-15`). On the public side, `meta` reaches
`<meta name="…" content="<%= … %>">` (escaped: `_meta_head.html.erb:3-15`,
`documentation_layout/articles/_meta_head.html.erb:26-53`), `_release_meta.html.erb:13,19,24` (escaped) and the
JSON-LD above. `meta['feature_image']` is author-supplied with no scheme validation, but its only consumer binds
it to an `<img :src>`, not an `:href` (`app/javascript/dashboard/components-next/changelog-card/StackedChangelogCard.vue:62-69`),
where a `javascript:` URL is inert. A key allowlist keeps the Super Admin form from writing `doc_key` or new
keys: `ArticleMetaField.permitted_attribute` (`article_meta_field.rb:33-35`), matched by the HC API
(`app/controllers/api/v1/accounts/articles_controller.rb:111-113`).

**`@theme_from_params` inside `<script>` is allowlisted.** `_portal_head.html.erb:32`
(`localStorage.theme = '<%= @theme_from_params %>';`) and `_portal_scripts.html.erb:81` look alarming, but the
value can only ever be two literals: `@theme_from_params = params[:theme] if %w[dark light].include?(params[:theme])`
(`app/controllers/public/api/v1/portals/base_controller.rb:19`).

**`renderInlineDiff` is safe in its current use.** `app/javascript/dashboard/helper/articleDiffHelper.js:22-23`
escapes only `&`, `<`, `>` — not `"` or `'` — but the result is wrapped in element content
(`:76-77`, `<ins class="…">${text}</ins>`) and consumed by `v-html` at `ArticleDiffPanel.vue:152`, never as an
attribute value. Safe today; a trap the moment the helper is reused in an attribute.

**Search snippets and cards are plain text.** `render_category_content` is
`ChatwootMarkdownRenderer#render_markdown_to_plain_text` (`app/helpers/portal_helper.rb:96-98` →
`lib/chatwoot_markdown_renderer.rb:21-23`), returning a non-`html_safe` String, printed escaped at
`app/views/public/api/v1/portals/search/_results.html.erb:27` and
`.../documentation_layout/_article_card.html.erb:11`. Titles there are escaped too (`:24` and `:10`).
`render_emoji_or_icon` validates against `/\A[a-z][a-z0-9-]*\z/` and the colour against `/\A#\h{3,8}\z/`
(`portal_helper.rb:101-110`). The sitemap carries only URLs built from slugs, no titles
(`app/views/public/api/v1/portals/sitemap.xml.erb:16-23`). `show_markdown` serves the raw source as
`text/markdown` (`articles_controller.rb:29-33`), which does not render HTML.

**`Article#slug` in a `<script>` context is safe, though the slug itself is barely validated.** This is the
other `<script>`-context interpolation of author-controlled data, so I checked it. The slug is **not**
charset-validated: `ensure_article_slug` is `self.slug ||= …` (`app/models/article.rb:234-236`), so a
client- or form-supplied value is stored verbatim — `:slug` is permitted by both the HC API
(`app/controllers/api/v1/accounts/articles_controller.rb:110`) and the Super Admin form
(`custom/app/dashboards/article_dashboard.rb:17,36`) — and the only validation is the reserved-word exclusion
(`app/models/article.rb:63,69`). The route constraint `/[a-z0-9][a-z0-9\-_]*/` applies to the `/docs/:article_slug`
redirect entry point (`config/routes/documentation.rb:25-26`), **not** to `/hc/:slug/articles/:article_slug`
(`config/routes.rb:519`). It is still not exploitable: the one `<script>`-context use is
`img.src = '<%= request.base_url %>/hc/<%= @portal.slug %>/articles/<%= @article.slug %>.png';`
(`app/views/layouts/_portal_scripts.html.erb:9`), and `<script>` content is RAWTEXT — the HTML parser never
decodes entities there — so ERB's `'` → `&#39;` stays literal inside the JS string instead of terminating it,
and `</script>` → `&lt;/script&gt;` cannot close the element. Everywhere else the slug lands in a path helper or
an ERB-escaped `href`.

## 4. What the editor upgrade would newly expose

| Capability | New exposure | Mapped to |
|---|---|---|
| WYSIWYG paste from a browser / Word / Google Docs | Pasted HTML must be converted, not stored. If the upgrade reaches for `:UNSAFE` so the editor's own markup round-trips, F1 fires instantly and every article becomes a script-injection on the super admin's origin. | F1 |
| `FullEditor` / `@chatwoot/prosemirror-schema` adoption | Imports the deliberate script re-execution primitive (F3) into the Super Admin browser, and widens the embed set that reaches it. | F3 |
| Richer embed catalogue | Every new `config/markdown_embeds.yml` entry is an unsanitized raw-HTML template keyed on a URL. Each `<script src>` added is a new third party with same-origin execution on the privileged origin. | F2 |
| Image / media upload | File type and `Content-Disposition` become XSS-relevant (SVG, HTML masquerading as an image). Agent 084's and 083's scope; the hand-off is that the article renderer applies no scheme or type policy of its own beyond §2.2. | F2, 083, 084 |
| Structured rich-content components | If components serialize to raw HTML in `content` rather than to Markdown constructs, the renderer's raw-HTML omission silently eats them — which pushes toward `:UNSAFE`. Any component system must serialize to Markdown or to a renderer extension, never to raw HTML. | F1 |
| A lower-privileged author role | `app/controllers/api/v1/accounts/articles_controller.rb:109-114` already permits `content`, `title`, `draft_content`, `draft_title` and `meta` for account users on tenant portals, so the "trusted super admin" premise is **already false** for the shared render path. A documentation author role inherits F2 and F4 on the privileged origin. | F2, F4 |

## 5. Required controls — minimum set, each mapped to an existing mechanism

1. **Add a real sanitizer at the end of `render_article`, and keep `:DEFAULT`.** `rails-html-sanitizer 1.7.1`
   and `loofah 2.25.2` are already in the lockfile (`Gemfile.lock:533,728`); no new dependency. One
   `Rails::HTML5::SafeListSanitizer` with an explicit element/attribute allowlist, applied inside
   `ChatwootMarkdownRenderer#render_as_html_safe` (`lib/chatwoot_markdown_renderer.rb:27-31`) — the single
   choke point every layout already goes through. Defence in depth, not a replacement: `:DEFAULT` stays.
2. **Make the embed templates pass that allowlist, or stop emitting them.** Either drop `github_gist` and the
   Wistia `<script>` tags from `config/markdown_embeds.yml` in favour of iframe-only players, or allowlist
   `<iframe>` with a fixed `src` host set and `sandbox`. The host set is already enumerated in that file; the
   only missing step is treating it as a policy rather than as a template library. (Extends
   `config/markdown_embeds.yml` and `CustomMarkdownRenderer`; adds nothing.)
3. **Finish the CSP.** `config/initializers/content_security_policy.rb` already says stage two is
   `script-src`/`style-src`, report-only first. The portal is the cheapest place to start: it loads a known,
   short list of hosts. Without it, every finding above is unmitigated at runtime.
4. **Move the Super Admin preview off the privileged origin, or stop previewing drafts there.** Serve the
   preview from the portal's `custom_domain` when one exists (the mechanism exists —
   `custom/app/helpers/documentation_helper.rb:29-33` and `app/controllers/public_controller.rb:9-20`), and
   build the redirect at `custom/app/controllers/super_admin/articles_controller.rb:24` from
   `portal_absolute_url` rather than from a relative path.
5. **One XSS regression spec file.** Assert that `<script>`, `<img onerror>`, `<svg onload>`, `<iframe>` and
   `<style>` in `content` produce `<!-- raw HTML omitted -->`, and that `javascript:` / `jav&#x09;ascript:` /
   `data:text/html` link and image URLs produce an inert `href`/`src`. Extends
   `spec/lib/chatwoot_markdown_renderer_spec.rb`. Without it, control 1 and the `:DEFAULT` option are
   undefended against a future refactor.
6. **Validate `cw_image_width` in the JS formatter the way Ruby does.** Reuse the Ruby bound (1..2000 px,
   `/\A\d+px\z/`) in `app/javascript/shared/helpers/MessageFormatter.js:5-19`. Small, and it removes a live
   clickjacking primitive from the dashboard.
7. **Drop `.html_safe` from `og_image_url`** at `app/views/public/api/v1/portals/articles/_meta_head.html.erb:18-20`
   and `.../documentation_layout/articles/_meta_head.html.erb:59-60`. It is unnecessary and it removes the only
   backstop on an author-controlled title.
8. **Gate corpus content in CI.** The seeder publishes PR Markdown by default
   (`custom/app/services/documentation/content_seeder.rb:20,101`). A CI check that flags raw HTML and embed URLs
   in `custom/db/documentation/**/*.md` makes threat (b) visible to a reviewer. Extends the existing
   `lib/tasks/documentation*.rake` family rather than adding a pipeline.

## 6. Not checked

- Runtime confirmation. Per the brief I ran no server and no `rspec`; every claim above is from reading the
  source, including the vendored gem C and Ruby.
- Whether a deployed installation sets a CSP at the reverse proxy or CDN rather than in Rails. If one does, the
  severity of F2/F3/F4 drops. `config/initializers/content_security_policy.rb:10-13` states the application does
  not.
- ActiveStorage blob `Content-Type`/`Content-Disposition` behaviour for uploaded media (agents 083, 084).
- The Super Admin session cookie's flags and whether `/super_admin` carries any additional origin isolation.
- Whether any tenant portal is served on a `custom_domain` in this installation, which would change the origin
  analysis in F4 for that portal only.
