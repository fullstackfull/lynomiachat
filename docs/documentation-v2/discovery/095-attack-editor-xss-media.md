---
agent: 095
scope: Adversarial attack on the editor and media security conclusions — refute "safe", refute "vulnerable", and name the recommended controls that would miss
confidence: high
---

# 095 — Attack the editor: XSS and media

Nothing was executed. No server, no Rails, no payload. Every claim below is read from
`lib/`, `custom/`, `app/`, `config/`, the installed `commonmarker-0.23.12` C and Ruby sources, and
`activestorage-7.2.3.2`. Where a claim depends on a browser or a CSS parser rather than on this repository it is
marked and moved to §4.

**The headline: both render-path reports concluded that an author cannot get a `<script>` tag into a published
article except through two embed templates. That is wrong. There is a direct, unconditional stored-XSS sink in the
article renderer, it needs no raw HTML, no link, no embed and no configuration change, and it is reachable by every
tenant account administrator as well as by Super Admin.** It is the fenced-code-block info string. The Ruby port of
cmark's HTML renderer dropped the escape that the C renderer performs, and `CustomMarkdownRenderer` does not
override the method.

---

## 1. What I attacked

Peer reports available at the time of writing: **065** (`065-markdown-render-sanitization.md`) and **085**
(`085-external-links-iframes.md`). **081, 082, 083 and 084 do not exist yet** — there is no file for them in
`docs/documentation-v2/discovery/`. For those four scopes I attacked the conclusions a competent agent would
reach from this code, and I read the code myself rather than waiting, so §2 and §3 do not depend on any peer.

| # | Claim attacked | Source |
|---|---|---|
| A1 | "Raw HTML in a documentation article is neither rendered nor escaped — it is deleted." The renderer's `:DEFAULT` options "are the entire raw-HTML defence", so a typed `<script>` cannot execute | 065 preamble, §2.1, §3.1(2), payload table; 085 §2.5 and its "findings that did not hold" |
| A2 | "`CGI.escapeHTML` blocks the Wistia `<style>` CSS-injection angle"; "the captures are HTML-escaped so the CSS string cannot be broken" | 065 §3.1(5); 085 §2.5 |
| A3 | "There is **one** article render path, not three" | 065 §1.1 |
| A4 | `javascript:`/`data:`/entity/whitespace bypasses of `MarkdownRendererUrlSanitizer` | 065 §3.1(3), 085 §2.4 |
| A5 | "`onerror`/`onload` attributes — not reachable" | 065 §3.1(4) |
| A6 | "The JSON-LD block is correctly escaped; a title cannot close the `<script>`" | 065 "checked and safe" |
| A7 | `?show_plain_layout=true` framing is **major**; "a framed draft preview plus a logged-in super admin is worse" | 065 F3 and Risk 5; 085 §2.7 |
| A8 | The embed `<script src>` finding's impact rests on the portal sharing the dashboard's cookie origin | 085 F2 |
| A9 | The Administrate authoring surface (fields, views, dashboard) is an injection surface | the 082 scope, unwritten |
| A10 | SVG and dangerous media uploaded through ActiveStorage are a stored-XSS vector; blob exposure | the 083/084 scopes, unwritten |
| A11 | The recommended controls (C1–C8, A1–A3, B1–B3) stop what they are aimed at | 065 §4, 085 §5 |

---

## 2. Refutations

### R1 — BLOCKER. Stored XSS in every article via the fenced-code-block info string. Refutes A1.

`CustomMarkdownRenderer` overrides `html`, `table`, `text`, `link` and `image` and nothing else
(`lib/custom_markdown_renderer.rb:22,29,43,54,61`). `code_block` therefore falls through to the gem:

```ruby
# vendor/bundle/ruby/3.4.0/gems/commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb:98-103
out("<pre#{sourcepos(node)}><code")
if node.fence_info && !node.fence_info.empty?
  out(' class="language-', node.fence_info.split(/\s+/)[0], '">')
else
  out(">")
end
out(escape_html(node.string_content))
```

The *body* is escaped at `:105`. The *info string* at `:100` is not, and `out` has no escaping in it at all:

```ruby
# commonmarker-0.23.12/lib/commonmarker/renderer.rb:20-33
def out(*args)
  args.each do |arg|
    case arg
    when :children then @node.each { |child| out(child) }
    ...
    else @stream.write(arg)
```

This is a defect in the Ruby port, not in cmark. cmark's own C renderer escapes the same value:

```c
// ext/commonmarker/html.c:242-243
cmark_strbuf_puts(html, "><code class=\"language-");
escape_html(html, node->as.code.info.data, first_tag);
```

And the parser hands the renderer raw, *entity-decoded* bytes — it actively helps the payload:

```c
// ext/commonmarker/blocks.c:337-342
cmark_strbuf tmp = CMARK_BUF_INIT(parser->mem);
houdini_unescape_html_f(&tmp, node_content->ptr, pos);   // entities DECODED
cmark_strbuf_trim(&tmp);
cmark_strbuf_unescape(&tmp);                              // backslash escapes removed
b->as.code.info = cmark_chunk_buf_detach(&tmp);
```

**Payload.** `split(/\s+/)[0]` keeps only the first whitespace-free token, so the payload carries no spaces. Two
forms, both valid CommonMark (a fence info string may contain any character except a backtick, and `~~~` fences
permit even that):

````
```x"></code></pre><script>alert(document.domain)</script><pre><code>
anything
```
````

renders as

```html
<pre><code class="language-x"></code></pre><script>alert(document.domain)</script><pre><code>">anything
</code></pre>
```

and the attribute-free variant, for a reviewer who filters on the string `script`:

````
```x"><svg/onload=alert(document.domain)>
anything
```
````

Entity-encoding works too, because of `blocks.c:338`: ```` ```x&quot;&gt;&lt;svg/onload=alert(1)&gt; ````.

**The path to the browser, with no control on it.** `articles_controller.rb:26` →
`chatwoot_markdown_renderer.rb:13-19` (`CustomMarkdownRenderer.new`, `:DEFAULT`) → `html.html_safe` at
`chatwoot_markdown_renderer.rb:29` → `_content.html.erb:18` `<%= parsed_content %>`. No `sanitize` anywhere in
that chain, and the only CSP is `object_src :none; base_uri :self`
(`config/initializers/content_security_policy.rb:14-17`), which constrains neither inline nor external script.

**Reachability is much wider than "a trusted Super Admin typing in a textarea".** `Article#content` is validated
for presence only (`app/models/article.rb:65-69`) and `ArticlePolicy#create?`/`#update?` are
`@account_user.administrator?` (`app/policies/article_policy.rb:6-20`), so **every tenant account administrator**
can publish this on their own account's help-center portal through
`Api::V1::Accounts::ArticlesController#create`/`#update` (`app/controllers/api/v1/accounts/articles_controller.rb:26-35`).
Super Admin reaches the platform documentation portals the same way through the textarea at
`custom/app/dashboards/article_dashboard.rb:19`.

**The same hole exists on the message/email renderer.** `BaseMarkdownRenderer` also does not override `code_block`
(`lib/base_markdown_renderer.rb` overrides only `image`), so `render_message` is affected at
`app/helpers/email_helper.rb:10` and in the three `conversation_reply_mailer` views
(`reply_with_summary.html.erb:16`, `conversation_transcript.html.erb:33`, `reply_without_summary.html.erb:4`).
It is **not** reachable through the Liquid drops: `MessageDrop#text_content` runs
`transform_user_mention_content` first (`app/drops/message_drop.rb:10` →
`app/helpers/message_format_helper.rb:10`, `to_plaintext`), which flattens the fence before rendering. Scoping
that precisely is outside my brief; it is listed so 030/034 are told.

**Nothing would catch it.** `spec/lib/custom_markdown_renderer_spec.rb` has no `code_block` example at all — its
`describe`/`context` blocks are `#text`, `#html`, broken `^`, `#link` (fifteen embed contexts), `#table` and
`#image`. `grep -n 'code_block\|language-\|fence' spec/lib/custom_markdown_renderer_spec.rb
spec/lib/base_markdown_renderer_spec.rb` returns nothing. The corpus is clean today: only
`custom/db/documentation/en/integrations/webhooks.md` and its Arabic twin contain fences (`:79,81`) and neither
carries an info string, so this is latent in the content and live in the code — which is exactly the state 065
and 085 assigned to the embed findings, and this one is strictly worse.

**Severity: blocker.** It is the single finding in this program so far that is a complete, unconditional stored
XSS with no precondition.

### R2 — MAJOR (reasoning), minor-to-major (effect). `CGI.escapeHTML` is the wrong escaper for the one capture that lands in a CSS context, and a literal newline reaches it. Refutes A2.

Both reports close the Wistia `<style>` angle with the same argument, and both consider only quotes. 065 §3.1(5):
*"`CGI.escapeHTML` turns `'` and `"` into `&#39;`/`&quot;`, which inside a raw-text `<style>` element stay literal
characters and therefore cannot close the CSS string. The rule breaks; it does not escape."* 085 §2.5 says the
same.

A CSS string literal is also terminated by a newline, and `CGI.escapeHTML` does not escape newlines.

The capture is `(?<video_id>[^&/?]+)` (`config/markdown_embeds.yml:88`). A Ruby negated character class matches
`\n`. And a newline is reachable in `node.url`:

- the link-destination scanner breaks only on `cmark_isspace` (`ext/commonmarker/inlines.c:1084-1088`), and the
  five bytes `&#10;` contain no space, so the destination is accepted;
- `cmark_clean_url` then decodes it — `cmark_chunk_trim`, then `houdini_unescape_html_f`, then
  `cmark_strbuf_unescape` (`ext/commonmarker/inlines.c:871-885`);
- `houdini_unescape_ent` replaces only codepoint 0, the surrogate range and anything ≥ 0x110000 with U+FFFD
  (`ext/commonmarker/houdini_html_u.c:73-79`). **LF is codepoint 10 and is emitted literally.**

The embed path then uses `CGI.escapeHTML` and nothing else, and never `sanitized_href` — `link` returns before
`super` (`lib/custom_markdown_renderer.rb:54-58`), and the substitution is
`template.gsub("%{#{var_name}}", CGI.escapeHTML(value))` (`:206`).

So `[v](https://a.wistia.com/medias/x&#10;}body{display:none}q{)` puts a raw LF inside
`markdown_embeds.yml:93-100`:

```css
wistia-player[media-id='x
}body{display:none}q{']:not(:defined) { … }
```

`markdown_embeds.yml:93` is the **only** non-attribute capture context in the whole file — every other `%{…}` sits
inside a quoted HTML attribute (verified by `grep -n '%{' config/markdown_embeds.yml | grep -v '="%{' | grep -v
"='%{"`, which leaves only the `<style>` selector at `:94` and its `url()` at `:95`). So the *effect* is one
template wide, and 065's option A1 would delete it. What is refuted is the *reason* both reports give for the
layer being safe. An HTML escaper placed in front of a CSS context is not a control; here it blocks the quote and
is silent about the delimiter that CSS actually honours, which is the shape of bypass my brief asks about.

I did not test whether CSS error recovery yields a *complete applied rule* from the above — see §4. The newline
reaching the CSS context is proven from code; the rule taking effect is not.

### R3 — MINOR today, major as a model error. There are two renderers of article content reaching a browser, with different HTML policies. Refutes A3.

065 §1.1 concludes *"There is **one** article render path, not three"*, correctly observing that all three layouts
share `_content.html.erb`. But the portal's search-suggestions dropdown renders article content client-side:

```html
<!-- app/javascript/portal/components/SearchSuggestions.vue:111 -->
<span v-dompurify-html="prepareContent(article.content)" … />
```

`prepareContent` → `highlightContent` (`app/javascript/shared/composables/useMessageFormatter.js:62-76`) →
`getPlainText` → `MessageFormatter#plainText`:

```js
// app/javascript/shared/helpers/MessageFormatter.js:119-125
get plainText() {
  const strippedOutHtml = new DOMParser().parseFromString(this.formattedMessage, 'text/html');
  return strippedOutHtml.body.textContent || '';
}
```

That **un-escapes exactly what `html: false` escaped** (`MessageFormatter.js:45`) and the decoded result is then
inserted as HTML. The server's "raw HTML is omitted" property does not hold on this path at all. What holds is
DOMPurify, registered at `app/javascript/portal/portalHelpers.js:94,112` with `domPurifyConfig`
(`app/javascript/shared/helpers/HTMLSanitizer.js:25-34`).

In practice the bytes are already flattened server-side — the public serializer emits a plain-text snippet
(`app/views/public/api/v1/models/_search_article.json.jbuilder:1-3`, `render_markdown_to_plain_text`) — but
cmark's `to_plaintext` emits HTML nodes literally, so tag-shaped text does travel and DOMPurify is what removes
the handler. Impact today: low. Impact of the claim: 065 §2.1's statement that the `:DEFAULT` render options are
"the entire raw-HTML defence" is wrong about which control is load-bearing where, and that is precisely the
reasoning an editor upgrade would be built on.

### R4 — MINOR. The colwidths sizing input is unbounded, uniquely among the sizing inputs.

`COLWIDTHS_COMMENT = /<!--cw-colwidths:([\d,]+)-->/` and `match[1].split(',').map(&:to_i)`
(`lib/custom_markdown_renderer.rb:17,26`). Those integers reach `total_width` (`:111-113`),
`table_sizing_style` (`:118-123`) and `colgroup_html` (`:125-128`). They are integers, so there is no injection —
but every other sizing input in this renderer is deliberately bounded to `1..2000`, with the reason written into
the code (`lib/base_markdown_renderer.rb:32-39`: *"Only allow a bounded `<digits>px` value so the decoded query
param can't break out of the inline style attribute"*; same guard at `custom_markdown_renderer.rb:141-146`), and
this one has no bound on the value or on the count. `<!--cw-colwidths:1,1,1,…-->` before a table emits one
`<col style="width: 1px;">` per entry — about 26 output bytes per 2 source bytes. Recorded because the editor
programme is specifically about making an editor write this marker.

### R5 — MINOR. The embed substitution is a `gsub` replacement string, so backslash backreferences in a capture are interpreted.

`template = template.gsub("%{#{var_name}}", CGI.escapeHTML(value))` (`lib/custom_markdown_renderer.rb:206`).
Ruby interprets `\0`, `\&`, `` \` ``, `\'`, `\1`–`\9` and `\\` in a `gsub` replacement string. `CGI.escapeHTML`
escapes `&` but **not** `\`, and `video_id`, `username`, `user` and `pen_id` all permit a backslash
(`markdown_embeds.yml:14,26,58,73,88,109,123,140,152`). `CGI.escapeHTML('\&')` is `'\&amp;'`, which `gsub` reads
as `\&` → splices the whole match (`%{video_id}`); `` \` `` and `\'` splice the template text before and after the
placeholder.

Not an injection: the spliced bytes are always template text or the literal placeholder, never raw capture bytes.
It is one escaping change away from being one, and the spec that pins capture escaping covers `<>&"'` and not `\`
(`spec/lib/custom_markdown_renderer_spec.rb:285-301`).

### R6 — MINOR, correcting a severity. `?show_plain_layout=true` framing is minor, not major. Refutes A7.

The fact is confirmed: `base_controller.rb:14-16` sets `@is_plain_layout_enabled` from the param and
`:66-68` deletes `X-Frame-Options` in an `after_action`, with no `frame-ancestors` to replace it. The stated
impact does not follow.

- Framing is cross-origin, so the framer cannot read the frame's content.
- Draft confidentiality is enforced server-side, not by the header: `scope = previewing_as_super_admin? ?
  @portal.articles : @portal.articles.published` (`app/controllers/public/api/v1/portals/articles_controller.rb:80-83`),
  with the reason written above it, and `show_markdown` gates independently (`:30`).
- The Super Admin preview is a **redirect**, not an iframe
  (`custom/app/controllers/super_admin/articles_controller.rb:22-25`), so 065's Risk 5 composition does not exist
  as described.
- The residual risk is clickjacking of the article body, which on the documentation layout contains no
  state-changing control (`show.html+documentation.erb:1-35`).

Correct severity: **minor**. Carrying it at major puts `frame-ancestors` ahead of `script-src` on a priority list,
and `script-src` is the directive that would contain R1.

### R7 — MINOR, correcting a rationale. 085 F2's cookie-theft impact rests on a premise 085 marks "not checked". Refutes A8.

085 F2 states that a provider script *"would read"* the non-HttpOnly `cw_d_session_info` cookie, while the same
report lists *"whether production uses a separate `DOCUMENTATION_URL` host"* under "not checked". A finding may
not carry in its impact statement a consequence that depends on an unverified premise. I found no documentation
host split in `config/`, so the premise is unresolved in both directions. The embed `<script src>` finding stands
on its own merits without it — full DOM control of a page a reader trusts is major by itself — and the cookie
sentence should be demoted to a conditional.

---

## 3. Survived

Everything here I tried to break and could not. Each row names the line that stops it, because "it is escaped" is
not an answer.

**S1 — `MarkdownRendererUrlSanitizer` holds against every scheme form I could construct.** `\A`-anchored
deny-list at `lib/markdown_renderer_url_sanitizer.rb:3`, applied at `:16`. The anchor is not the weakness,
because the parser normalises first: `cmark_chunk_trim` strips leading whitespace and
`houdini_unescape_html_f` decodes entities before `node.url` exists (`ext/commonmarker/inlines.c:871-885`), and
`cmark_strbuf_unescape` only drops a backslash before punctuation, so `\javascript:` keeps the backslash.
Anything that survives the check goes through `escape_href`, whose `HREF_SAFE` table percent-escapes `"`, `<`,
`>`, space and every byte ≥ 128 and entity-encodes `&` and `'` (`ext/commonmarker/houdini_href_e.c:32-44,65-94`).
I could not find an attribute breakout.

**S2 — an embed template cannot be reached inside an image's `alt` attribute.** This is the route neither report
tried and the one I expected to work: `image` writes `out(' alt="', :children, '"')` inside `plain do`
(`lib/custom_markdown_renderer.rb:64-66`), and `link` → `render_embedded_content` `out`s a template **verbatim**
(`:164-172`), which inside `alt="` would be an attribute breakout with arbitrary HTML. It does not fire. The
control is one line in the gem:

```ruby
# commonmarker-0.23.12/lib/commonmarker/renderer.rb:40-41
elsif @in_plain && node.type != :text && node.type != :softbreak
  node.each { |child| render(child) }
```

Inside `plain`, no node type but `:text` and `:softbreak` is dispatched to its handler, so `link`, `image` and
`inline_html` are all skipped and only their children render. Nobody in this repository wrote that control and
nothing pins it — a commonmarker upgrade that changed it would open S2 silently.

**S3 — `onerror` is not reachable on a rendered `<img>`.** Raw HTML never becomes markup (`html_renderer.rb:110-126`
with `UNSAFE` off: `option_enabled?(:UNSAFE)` is `(0 & 131072) != 0`, and `grep -rn "UNSAFE" --include=*.rb app/
lib/ custom/ config/ spec/` is empty). The hand-built `<img>` interpolates only `escape_href`'d src, `escape_html`'d
title and a `\A(\d+)px\z` / `1..2000`-bounded width (`lib/custom_markdown_renderer.rb:61-71,141-146`).

**S4 — a `</script>` in an article title cannot break the JSON-LD block, and the reason is not `to_json`.**
`documentation_structured_data` is `tag.script(json_escape(payload.to_json).html_safe, type: 'application/ld+json')`
(`custom/app/helpers/documentation_helper.rb:100`). `ERB::Util.json_escape` rewrites `<`, `>`, `&`, U+2028 and
U+2029 to `\u00xx` form, so no literal `<` reaches a raw-text element and the `</script` tokenizer sequence cannot
be formed; `<!--`-based script-data-escaped tricks need a literal `<` too. The title flows in at `:85`
(`documentation_article_schema`) and `:65-67` (`documentation_breadcrumb_schema`), and `documentation_structured_data`
is the only `application/ld+json` emitter in the repository. The comment at `:97-98` credits `to_json`; it is
`json_escape` that does the work, which matters because `to_json`'s HTML escaping is a configurable global.

**S5 — `og_image_url.html_safe` cannot be broken out of.** Nine call sites (`app/views/public/api/v1/portals/**/_meta_head.html.erb`,
`_hero.html.erb:7-9`). The value is built by `set_og_image_url` (`app/helpers/portal_helper.rb:3-15`), which
`URI.parse`es an installation config, forces `uri.path = '/og'` and sets `uri.query = URI.encode_www_form(...)`;
the article title only ever lands in the percent-encoded query.

**S6 — the Administrate authoring surface is not an injection surface.** `grep -rn "html_safe\|<%= raw\|sanitize"
custom/app/views/ app/views/fields/ app/views/administrate/` returns nothing. The custom field templates are
`<%= field.to_s %>` (`custom/app/views/fields/article_meta_field/_show.html.erb:1`, `_index.html.erb:1`,
`article_author_field/_show.html.erb:1`) and `value="<%= field.value_for(key) %>"`
(`article_meta_field/_form.html.erb:11,19`), all ERB-escaped. `content` is a plain textarea
(`custom/app/dashboards/article_dashboard.rb:19`) and `resource_params` only reshapes `meta['tags']`
(`custom/app/controllers/super_admin/articles_controller.rb:39-53`).

**S7 — the portal's inline `<script>` interpolations are not injectable.** `_portal_head.html.erb:32`
(`localStorage.theme = '<%= @theme_from_params %>'`) is fed only from `base_controller.rb:19`, which permits
exactly `dark` and `light`. `_portal_analytics.html.erb` uses `escape_javascript` at `:10,21,47,57`, `.to_i` at
`:30` and ERB attribute escaping at `:16,41`, over values constrained by `Portal::ANALYTICS_CONFIG_FORMATS`
(`app/models/portal.rb:77-85`, e.g. `/\AGTM-[A-Z0-9]+\z/`). `_portal_scripts.html.erb:101` interpolates
`ENV['FRONTEND_URL']` and a generated `website_token` (`app/models/channel/web_widget.rb:64-79`). Note for
anyone who "fixes" `_portal_head.html.erb:32` by escaping harder: ERB escaping is already the wrong escaper for a
JS string context, and what saves that line is the allowlist at `base_controller.rb:19`, not the escape.

**S8 — SVG uploaded through ActiveStorage is not a stored-XSS vector here.** This is the conclusion I expected 084
to invert. `config/initializers/active_storage.rb:5-13` adds seven **audio** types to
`content_types_allowed_inline` and leaves `content_types_to_serve_as_binary` at the Rails default, which contains
`text/html`, `image/svg+xml`, `text/xml`, `application/xml` and `application/xhtml+xml`
(`activestorage-7.2.3.2/lib/active_storage/engine.rb:55-65`). For those types:

```ruby
# activestorage-7.2.3.2/app/models/active_storage/blob/servable.rb:4-16
def content_type_for_serving
  forcibly_serve_as_binary? ? ActiveStorage.binary_content_type : content_type
end
def forced_disposition_for_serving
  :attachment if forcibly_serve_as_binary? || !allowed_inline?
end
```

So an SVG is served as `application/octet-stream` with `Content-Disposition: attachment`. `image/svg+xml` is also
absent from `variable_content_types` (`engine.rb`), so it cannot be rasterised into a variant. An SVG inserted as
an article image would **download instead of rendering** — a product defect for the media work, not an XSS. The
repository also already reasons about this correctly in one place:
`custom/app/controllers/super_admin/platform_support_controller.rb:68` gates on
`ActiveStorage.content_types_allowed_inline`, and
`custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:1-38` is the only authorised
blob download in the repository, with the reasoning written out.

Two caveats so nobody over-reads S8. (a) The forcing happens in Rails' serving layer; a bare object URL on a
public S3/`s3_compatible` bucket, or a CDN in front of one, carries the stored `Content-Type` with no
`response-content-type` override and no `X-Content-Type-Options`. Bucket ACLs are not in the repository (§4).
(b) `Attachment#media_file?` accepts **any** `image/*`, `video/*` or `audio/*` from the declared content type
(`app/models/attachment.rb:202,216`), so an `image/svg+xml` message attachment is accepted on upload — it is the
serving layer, not the upload validation, that contains it. A MIME allowlist over a client-declared content type
is not a control on the bytes.

**S9 — drafts are not publicly readable, and the markdown endpoint is not a sniffing vector.**
`articles_controller.rb:80-83` (quoted in R6) and `:29-33` (`render plain: …, content_type: 'text/markdown'`),
with `X-Content-Type-Options: nosniff` from `load_defaults 7.0` (`config/application.rb:39`). Any "draft leak"
finding would be wrong.

**S10 — the server-side search snippet is escaped.** `portal_helper.rb:96-99` returns `to_plaintext`'s plain
String and ERB escapes it at `search/_results.html.erb:27`; `render_emoji_or_icon` (`portal_helper.rb:102-110`)
allowlists `\A[a-z][a-z0-9-]*\z` and `\A#\h{3,8}\z` and `html_escape`s anything else.

**S11 — I could not break the embed capture escaping in an attribute context.** `CGI.escapeHTML`
(`custom_markdown_renderer.rb:206`) escapes `&"'<>`; every regex is anchored on `https?://`
(all eleven, `markdown_embeds.yml:14,26,36,48,58,73,88,109,123,140,152`), which is what prevents the embed path's
bypass of `sanitized_href` from also being a scheme bypass; the hosts are literal in the templates; and the
`mp4` capture, the only one with no host restriction, is `(?<link_url>https?://(?:www\.)?.+\.mp4)` — `.` excludes
newline, so R2's newline trick does not apply to it. `apply_embed_width`'s `Nokogiri::HTML5.fragment` round-trip
(`:177-185`) interpolates only a `1..2000`-bounded `\d+px`, and I found no decode/re-emit asymmetry in it
(`<style>` is a raw-text element both on parse and on serialise).

---

## 4. The forward question — recommended controls that would miss

This is the part nobody else owns. Of the controls 065 and 085 recommend, these would not stop what they are
aimed at.

1. **A scheme allowlist in `MarkdownRendererUrlSanitizer` (085 C1) touches neither R1 nor R2.** R1's sink is not
   a URL. R2's sink is on the embed path, which returns before `super` and so never enters the module at all
   (`custom_markdown_renderer.rb:55`). Both reports treat that module as "the renderer's sanitizer"; it governs
   only `<a href>` and `<img src>` for non-embed nodes. The renderer has no sanitizer.

2. **A `script-src` allowlist (065 B2, 085 C7) only stops R1 in its nonce form, and both reports describe the
   allowlist form.** The portal head carries inline `<script>` at `_portal_head.html.erb:32,35-44` and throughout
   `_portal_scripts.html.erb`, which forces either `'unsafe-inline'` or a nonce. With `'unsafe-inline'`, R1's
   `<script>alert(1)</script>` runs. Only the nonce form blocks it — and only the nonce form blocks R1's
   `<svg/onload=…>` variant too, since inline event handlers fall under `script-src` and need `'unsafe-hashes'`
   to run. Both reports also recommend starting **report-only**, which stops nothing at all for as long as it
   stays report-only. R1 should not be left waiting on that staging.

3. **A corpus lint (085 C6) is structurally blind to R1.** C6 checks schemes, hosts, images, raw HTML and embed
   patterns. ```` ```x"><svg/onload=1> ```` is well-formed CommonMark, contains no URL, produces a `code_block`
   node and not an `html_block`, and matches no embed regex. A lint that reads the *source* cannot see a sink
   that lives in the *renderer*. The check that would catch it is the one neither report proposes: render each
   corpus file through `ChatwootMarkdownRenderer#render_article` and assert the output contains no `<script`, no
   `on\w+=`, and no element outside a fixed allowlist. That same assertion is what would have caught R1 in CI
   before this program started.

4. **"The editor previews through the real renderer, so WYSIWYG is true" (085 C8) is false as written.**
   `custom/app/controllers/super_admin/articles_controller.rb:24` redirects with `?show_plain_layout=true`, and
   `set_view_variant` makes `:plain` win over `:documentation` (`base_controller.rb:26-32`). The author previews
   the **plain** variant and publishes the **documentation** variant: same body partial, different chrome,
   different `link_class` (`show.html+documentation.erb:16-18` vs `show.html+plain.erb`), and analytics
   suppressed (`_portal_head.html.erb:27`). For R1 and R2 the preview is faithful; for anything layout-dependent
   it is not — and the preview is the control C8 leans on.

5. **`:UNSAFE` plus `tagfilter` is still a hole, which 065 F7 does not say.** F7 correctly warns that
   `chatwoot_markdown_renderer.rb:14` constructs the renderer with `extensions: []`, so `@tagfilter` is false
   (`renderer.rb:17`) and enabling `:UNSAFE` would skip the filter. The stronger point is that `tagfilter`
   neutralises eight tag names and nothing else (`renderer.rb:105-121`): `<div onclick=…>`, `<a
   href="javascript:…">` and `<svg onload=…>` all pass it. Fixing F7 by adding `[:tagfilter]` would read as a fix
   and would not be one.

6. **Any control at the Administrate form is bypassed by the other writer into the same column.**
   `Documentation::ContentSeeder` writes `Article#content` from the Markdown corpus, and the tenant API writes it
   for any account administrator (`app/controllers/api/v1/accounts/articles_controller.rb:26-35`,
   `app/policies/article_policy.rb:18-20`). The model validates presence only
   (`app/models/article.rb:65-69`). The earliest shared entry point for article content is the renderer.

7. **065 A1 (drop `wistia` and `github_gist`) is the one recommended control that happens to close one of my
   findings** — it closes R2 by deleting the only non-attribute capture context in
   `config/markdown_embeds.yml`. It closes it for the wrong reason, which is worth recording so that a future
   template addition is reviewed against *context* and not only against "are the captures escaped".

---

## 5. Not checkable

Nothing was executed, per `00-program.md` §6.1. These remain open.

| # | What | What would settle it |
|---|---|---|
| N1 | R1's exact emitted markup, and R2's emitted `<style>` bytes | One RSpec file calling `ChatwootMarkdownRenderer.new(payload).render_article` and asserting the output string. No server, no database, no deploy. This is also the regression test that is missing |
| N2 | Whether R2's injected CSS yields a rule the browser **applies**, rather than only breaking the Wistia rule through error recovery | The recorded markup from N1 loaded as a static HTML file in current Chrome, Firefox and Safari |
| N3 | Whether the documentation portal shares an origin with the dashboard in production — the premise under R7 | Deployment configuration; no `DOCUMENTATION_URL` host split exists in `config/` |
| N4 | Bucket and CDN ACLs for the S8 caveat (a public object URL bypassing Rails' disposition forcing) | Infrastructure, not in the repository |
| N5 | Gumbo's `<noscript>` scripting-flag behaviour on the `github_gist` template through `apply_embed_width`'s `Nokogiri::HTML5.fragment` round-trip (`custom_markdown_renderer.rb:177-185`) | A Ruby snippet parsing and re-serialising that one template |
| N6 | Whether the Help Center feature is enabled for tenant accounts in production (`ensure_portal_feature_enabled`) | Production data, which §3 forbids. It sets whether R1 is reachable by tenant administrators in practice or only by Super Admin. The policy and the controller already permit it |
| N7 | Whether `render_message`'s exposure of R1 reaches a contact-authored message in any live template | Agents 030/034 own the message and notification surfaces; I confirmed the renderer and the `email_helper.rb:10` call site, not the full set of senders |
| N8 | Whether CommonMark's fence-info production rejects any of the bytes in R1's payload | The scanner is re2c-generated; I read the spec's rule and `blocks.c:328-342`, which stores the first line verbatim after entity decoding, but not the generated state machine. N1 settles this outright |

**Blockers for the orchestrator.** R1 is a live stored-XSS in a shipped product, reachable by every tenant
account administrator, and it invalidates the central conclusion of 065 and 085. It is not an editor-programme
finding that can wait for a contract freeze. 065's and 085's render-path sections need correcting before
`06-security-review.md` is written, and the "checked and safe, recorded so nobody re-checks it" list in 065 §3.3
should not be carried forward as-is while a method it did not check holds the worst finding in the area.
