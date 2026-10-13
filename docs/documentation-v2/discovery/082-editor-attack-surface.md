---
agent: 082
scope: The attack surface the editor upgrade will create — preview, uploads, paste, rich components, SEO fields, autosave, CSRF
confidence: high
---

# Editor attack surface

Read-only against `claude/documentation-v2`. No server run, no database touched. Every claim below carries a
`file:line`. Where I could not verify something I say so.

One finding reframes the brief: **the editor the upgrade wants already exists in this repository**. The tenant
Help Center has a ProseMirror editor with uploads, drag/drop/paste handling, client-side embed preview, a
500 ms autosave and a draft/diff workflow (`app/javascript/dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditor.vue:1-247`,
`app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue:1-646`). Most of the attack surface in
this brief is therefore not hypothetical — it is built, and its controls can be read. What changes when it is
pointed at Super Admin is the **blast radius of the origin it runs in** and the **absence of the account scoping
that its server endpoints assume**.

---

## 1. Attack surface

### 1.1 Today (Administrate + a textarea)

| Surface | Evidence | Reachable by |
|---|---|---|
| `article[content]` free-text CommonMark | `custom/app/dashboards/article_dashboard.rb:19` (`Field::Text.with_options(rows: 28)`) | super admin |
| `article[meta][...]` six named inputs | `custom/app/views/fields/article_meta_field/_form.html.erb:5-21` | super admin |
| `resource_params` + `normalized_meta` | `custom/app/controllers/super_admin/articles_controller.rb:39-53` | super admin |
| `POST publish` / `POST unpublish` | `custom/app/controllers/super_admin/articles_controller.rb:10-18`, `config/routes/documentation.rb:13-17` | super admin |
| `GET preview` → `redirect_to "/hc/…?show_plain_layout=true"` | `custom/app/controllers/super_admin/articles_controller.rb:22-25` | super admin |
| Draft served to a signed-in super admin on the public portal | `app/controllers/public/api/v1/portals/articles_controller.rb:80-88` | any signed-in super admin, any portal |
| Public render of author content | `app/controllers/public/api/v1/portals/articles_controller.rb:26,109-111` → `lib/chatwoot_markdown_renderer.rb:13-19` | the world |

### 1.2 What the upgrade adds

Uploads (`POST` of bytes), a paste pipeline, an in-page preview, structured components, SEO field editing, and an
autosave endpoint. Each is enumerated in §3 and §4.

---

## 2. What the existing defence actually does

Four defences exist. Three are real; one is an accident of Rails defaults, not of this repository's code.

**(a) Raw HTML in article Markdown is dropped, and it is tested.** `render_article` constructs
`CustomMarkdownRenderer.new` with no `options:` argument, so the renderer's options are `:DEFAULT`
(`lib/chatwoot_markdown_renderer.rb:14`, `vendor/bundle/ruby/3.4.0/gems/commonmarker-0.23.12/lib/commonmarker/renderer.rb:10-11`).
CommonMarker then replaces both block and inline raw HTML:

```ruby
def html(node)
  block do
    if option_enabled?(:UNSAFE)
      out(tagfilter(node.string_content))
    else
      out("<!-- raw HTML omitted -->")
    end
  end
end
```
(`…/commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb:110-126`, `inline_html` identical)

`CustomMarkdownRenderer#html` overrides this only to swallow the `<!--cw-colwidths:…-->` marker and otherwise
calls `super` (`lib/custom_markdown_renderer.rb:22-27`). A spec pins the behaviour:
`spec/lib/custom_markdown_renderer_spec.rb:33-36` asserts `<script>alert("xss")</script>` renders as
`<!-- raw HTML omitted -->`. **This is the single most load-bearing control in the whole documentation system,
and it is a renderer option, not a sanitizer.** Any second rendering path — a JS live preview, a different
`CommonMarker.render_doc` call, a future `:UNSAFE` to make embeds "work" — does not inherit it.

**(b) URL schemes are filtered on links and images.**

```ruby
DANGEROUS_URL_PATTERN = /\A(?:javascript:|vbscript:|file:|data:)/i
SAFE_DATA_IMAGE_PATTERN = %r{\Adata:image/(?:png|gif|jpeg|webp)}i
```
(`lib/markdown_renderer_url_sanitizer.rb:3-4,14-19`)

`image/svg+xml` is **not** in the data-URI allowlist, so `data:image/svg+xml,<svg onload=…>` is blanked. The
surviving URL is then run through cmark's `escape_href`, whose `HREF_SAFE` table excludes `"`, `<` and `>`
(`vendor/bundle/ruby/3.4.0/gems/commonmarker-0.23.12/ext/commonmarker/houdini_href_e.c:32-44`), so neither
`lib/custom_markdown_renderer.rb:61-71` (`out(%(<img src="#{src}"))`) nor the `<a href>` path can be broken out
of. I checked this specifically because both write raw attribute text.

**(c) Administrate's strong parameters are a key allowlist, not an open hash.** `permitted_attributes` asks each
field (`…/administrate-0.20.1/lib/administrate/base_dashboard.rb:71-85`), and `ArticleMetaField` answers with a
closed list:

```ruby
STRING_KEYS = (SEO_KEYS + RELEASE_KEYS + %w[feature_image]).freeze
def self.permitted_attribute(attr, _options = nil)
  { attr => STRING_KEYS + [{ tags: [] }, :tags] }
end
```
(`custom/app/fields/article_meta_field.rb:13,33-35`)

So the brief's question — *can arbitrary `meta` keys be set?* — answers **no**. Six keys, nothing else.
`resource_params` is `params.require(:article).permit(dashboard.permitted_attributes(action_name))`
(`…/administrate-0.20.1/app/controllers/administrate/application_controller.rb:203-207`). `article[meta][doc_key]`,
`article[account_id]`, `article[author_id]`, `article[views]` are all unpermitted — `FORM_ATTRIBUTES` is
`portal category title slug description content locale status position meta` (`custom/app/dashboards/article_dashboard.rb:36`).
There is no mass-assignment exposure here. There is a **mass-deletion** one — see F1.

**(d) CSRF is on by default for everything under `super_admin/`.** `Administrate::ApplicationController` declares
`protect_from_forgery with: :exception` at `…/administrate-0.20.1/app/controllers/administrate/application_controller.rb:3`,
`SuperAdmin::ApplicationController` inherits it and adds `before_action :authenticate_super_admin!`
(`app/controllers/super_admin/application_controller.rb:7,16`), and the layout emits the token
(`app/views/layouts/super_admin/application.html.erb:27`). The thing to avoid is the pattern at
`app/controllers/public_controller.rb:3-5`, which is `ActionController::Base` + `skip_before_action :verify_authenticity_token`.

**What does not exist:** a Content Security Policy worth the name. The policy is two directives:

```ruby
Rails.application.config.content_security_policy do |policy|
  policy.object_src :none
  policy.base_uri :self
end
```
(`config/initializers/content_security_policy.rb:14-17`, with the comment at `:10-13` stating `script-src` and
`default-src` are deliberately deferred to "stage two, report-only first")

No `script-src`, no `img-src`, no `frame-src`, no `connect-src`, no `frame-ancestors`. Every finding below that
says "CSP would stop this" is naming work that is already planned and not yet done.

---

## 3. Findings

### F1 — Saving an article in Super Admin destroys `meta['doc_key']` and silently breaks contextual help
**Severity: blocker. Reachable today.**

*Convergent, three independent reads.* Agents 064 (`064-editor-backend-model.md:16,361-385`) and 069
(`069-authoring-workflow-source-of-truth.md:215-236`) found this too; 064 rates it BLOCKER and I adopt that
rating over my own initial "major today". I reached it from the editor side and keep it here because the
**autosave** multiplier below is the part that is specific to this brief.

The content seeder writes `doc_key` into `meta` (`custom/app/services/documentation/content_seeder.rb:106-113`)
and `Documentation::Library.article_for` resolves every contextual-help key through
`articles.meta->>'doc_key' = ?` (`custom/app/services/documentation/library.rb:55`, per
`docs/documentation-v2/01-current-system.md` §1).

`doc_key` is in neither the form (`custom/app/views/fields/article_meta_field/_form.html.erb:5-21` renders only
`STRING_KEYS` + tags) nor the permitted set (`custom/app/fields/article_meta_field.rb:33-35`). The controller then
replaces the whole jsonb:

```ruby
def normalized_meta(meta)
  return meta if meta.blank?
  meta = meta.to_h.compact_blank
  ...
end
```
(`custom/app/controllers/super_admin/articles_controller.rb:47-53`; Administrate calls
`requested_resource.update(resource_params)` at `…/administrate-0.20.1/app/controllers/administrate/application_controller.rb:60`)

The form always submits `article[meta][...]`, so `permitted.key?(:meta)` is always true, so `meta` is always
rewritten from the six form keys and `compact_blank` drops the rest. **One Save of one article with no edit at
all deletes its `doc_key`.** Afterwards `Library.article_for` falls through to the literal-slug branch
(`library.rb:54-57`); for an Arabic article whose slug carries the `-ar` suffix (`content_seeder.rb:85-87`) there
is no match at all, and `DocumentationController#article` returns 404 by design
(`custom/app/controllers/documentation_controller.rb:18-26`). The product's in-app help link goes dead and nothing
reports it. It is repaired only by a re-run of `documentation:content`, which nothing in the deploy calls
(`docs/documentation-v2/01-current-system.md` §4).

An autosave path turns one deliberate click into a write every 500 ms (the tenant editor's cadence,
`ArticleEditor.vue:83-95`), so the damage happens from merely opening the editor.

**Minimum control:** merge instead of replace in `normalized_meta` —
`article.meta.merge(permitted_meta)` — and keep the key allowlist as the write filter. Existing mechanism: the
field's own `permitted_attribute`. No new validation layer. Agent 064 additionally recommends promoting
`doc_key` to an indexed column (`064-editor-backend-model.md:502-503`); the merge is the minimum **either way**,
because it protects every future `meta` key the form does not render, not just this one.

### F2 — The in-page preview would run author content in the Super Admin origin; the current redirect preview is *less* isolated than it looks
**Severity: major. Reachable after the upgrade.**

`preview` redirects to a **relative** path:

```ruby
redirect_to "/hc/#{article.portal.slug}/articles/#{article.slug}?show_plain_layout=true"
```
(`custom/app/controllers/super_admin/articles_controller.rb:22-25`)

That is a full-page navigation to the **same origin** as `/super_admin` — not a sandbox. The safety of today's
preview therefore does not come from origin separation at all; it comes from §2(a): the server renderer omits
raw HTML, so there is nothing to execute. The portal is reachable on a per-portal `custom_domain`
(`app/controllers/public_controller.rb:9-20`), but nothing makes the preview *use* it, and the platform
documentation portals' custom-domain state is **unverified** — I did not query the database.

Two further properties of that target page matter:

- It serves **unpublished drafts** to any signed-in super admin:
  `scope = previewing_as_super_admin? ? @portal.articles : @portal.articles.published`
  (`app/controllers/public/api/v1/portals/articles_controller.rb:80-88`). So the preview carries the super admin
  session, by design.
- `show_plain_layout=true` **removes the frame guard**: `response.headers.delete('X-Frame-Options') if @is_plain_layout_enabled`
  (`app/controllers/public/api/v1/portals/base_controller.rb:66-68`). An iframe preview works without config
  changes; it is also framable by any third-party site.

What an in-page preview changes: if it renders author Markdown **in JavaScript** it introduces a second renderer
that does not inherit §2(a). The tenant editor already parses with `MarkdownIt('commonmark', { html: false, … })`
(`node_modules/@chatwoot/prosemirror-schema/src/schema/markdown/articleParser.js:40-44`) — `html: false` is the
JS-side equivalent of the omission, and it is the only reason a `v-html`/`innerHTML` preview is not already an
XSS sink. That flag is one line away from being flipped by anyone who wants a raw-HTML escape hatch, and with no
`script-src` (§2) nothing behind it would catch the mistake.

**Minimum control:** render the preview **server-side only**, through the one path that already exists —
`ChatwootMarkdownRenderer#render_article` — delivered into an `<iframe srcdoc>`/`src` rather than into the Super
Admin DOM. If an iframe is used, it must carry `sandbox` **without** `allow-same-origin` and **without**
`allow-scripts`; `sandbox="allow-same-origin"` re-grants exactly the access the iframe is there to withhold.
Existing mechanisms: the renderer, and `show_plain_layout` (`base_controller.rb:14-16,26-32`).

### F3 — Reusing `FullEditor` in Super Admin makes third-party `<script>` tags execute in the Super Admin origin on keystroke
**Severity: major. Reachable after the upgrade.**

The editor's client-side embed preview injects the embed template and then **deliberately re-creates script
elements so they run**:

```js
wrapper.innerHTML = html;
// innerHTML doesn't execute <script> tags — re-create them so they do.
wrapper.querySelectorAll("script").forEach(stale => { … stale.replaceWith(fresh); });
```
(`node_modules/@chatwoot/prosemirror-schema/src/plugins/embedPreview.js:172-190`)

Two embed templates contain `<script src>`: `wistia` (`config/markdown_embeds.yml:91-92`, two tags) and
`github_gist` (`:154`). `github_gist` is excluded from the editor preview
(`app/javascript/dashboard/helper/markdownEmbeds.js:3-4`); **`wistia` is not**. So an author who types or pastes
a `*.wistia.com/medias/<id>` URL on its own line causes `fast.wistia.com/player.js` and
`fast.wistia.com/embed/<id>.js` to execute in the editor page — no click, no publish. In the tenant dashboard
that is an agent session. In Super Admin it is the super-admin session, with `/super_admin/*` same-origin.

The script host is fixed by the YAML, so this is a third-party-supply-chain exposure rather than arbitrary XSS.
It is still the most direct route from "author types a URL" to "super admin session compromised".

*Partially convergent.* Agent 081 quotes the same `buildEmbedWidget` re-creation (`081-xss-sanitizer.md:289,299`).
Two things here are mine and should not be lost in deduplication: that the destination origin becomes **Super
Admin** once `FullEditor` is reused there, and that **`wistia` is the one script-bearing embed `markdownEmbeds.js`
does not exclude** — `NON_PREVIEWABLE_EMBEDS` lists `github_gist` only
(`app/javascript/dashboard/helper/markdownEmbeds.js:3-4`).

**Minimum control:** do not enable `embedPreviewPlugin` in the Super Admin editor instance (it is passed
explicitly at `FullEditor.vue:108`, so omitting it is a one-line change), and add `script-src` to the CSP whose
stage two is already scheduled (`config/initializers/content_security_policy.rb:10-13`). Note the public portal
keeps these scripts regardless — that is agent 085's call, not mine.

### F4 — The upload endpoint applies no server-side content-type, size or count limit; all three gates are client-side
**Severity: major. Reachable today for tenants, newly reachable for platform documentation after the upgrade.**

Client side, `bucketFor` is a real allowlist and it covers picker, drop and paste alike:

```js
const ALLOWED_IMAGE_TYPES = ['image/png','image/jpeg','image/jpg','image/gif','image/webp'];
const ACCEPTED_FILE_TYPES = [...ALLOWED_IMAGE_TYPES, 'video/mp4'].join(', ');
```
(`app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue:40-50,371-397`, with the comment at
`:41-42` acknowledging that "drop and paste bypass the file input's accept filter")

Server side there is nothing:

```ruby
def create_from_file
  attachment = params[:attachment]
  create_and_save_blob(attachment.tempfile, attachment.original_filename, attachment.content_type)
end
```
(`app/controllers/api/v1/accounts/upload_controller.rb:16-19,39-45`)

No content-type check, no byte-size check, no `Attachment` model, therefore none of
`validate_file_content_type` / `validate_file_size` (`app/models/attachment.rb:201-213`) and none of
`FileTypeHelper#image_file?`, which is an exact-match allowlist with no `image/svg+xml` and no prefix matching
(`app/helpers/file_type_helper.rb:17-27`). The only size bound in the whole path is the **URL** branch's
`SafeFetch` cap of `MAXIMUM_FILE_UPLOAD_SIZE` or 40 MB (`lib/safe_fetch/request_options.rb:50-54`,
`lib/safe_fetch.rb:9`); the file branch has none. Rack::Attack throttles the endpoint at 60/hour but only via an
account-id path regex: `%r{/api/v1/accounts/(?<account_id>\d+)/upload}` (`config/initializers/rack_attack.rb:271-273`).

Three consequences for the brief's list:

- **SVG / HTML / polyglot files are mitigated, but by Rails, not by this repository.** `create_and_upload!` leaves
  `identify: true`, so `unfurl` re-sniffs with Marcel using the client type only as a hint
  (`vendor/bundle/ruby/3.4.0/gems/activestorage-7.2.3.1/app/models/active_storage/blob.rb:270-275,367-369`). A
  real SVG mislabelled `image/png` is re-identified as `image/svg+xml`, which is in Rails' default
  `content_types_to_serve_as_binary` together with `text/html` (`…/activestorage-7.2.3.1/lib/active_storage/engine.rb:55-65`),
  so `service_metadata` serves it as `application/octet-stream; disposition=attachment`
  (`…/blob.rb:375-379`). `config/initializers/active_storage.rb:5-13` only **adds** audio types to
  `content_types_allowed_inline` and does not touch the binary list — so the mitigation holds, and a future edit
  to that list would silently remove it.
- **Filename traversal is not exploitable on the storage path.** The blob key is a generated token, not the
  filename, and the filename is only an attribute. The risk is display, not path.
- **Zip bombs and image-parser bugs are not reached for article media today.** `config.active_storage.previewers = []`
  (`config/application.rb:71`) disables PDF/video previewers, and no article path generates a variant — the
  endpoint returns the original (`upload_controller.rb:48`, `url_for(file_blob)`). `representation` is called only
  for message attachments, Slack uploads and avatars (`app/models/attachment.rb:71`,
  `app/controllers/slack_uploads_controller.rb:22`, `app/models/concerns/avatarable.rb:16`). If the editor upgrade
  adds article thumbnails it reaches libvips (deploy stage 4b exists for exactly that dependency,
  `docs/documentation-v2/01-current-system.md` §4), and the exposed decoders are then whatever
  `web_image_content_types` allows — by default png/jpeg/gif only (`…/engine.rb:49-53`).

**Minimum control:** validate content type and byte size at the controller boundary, reusing
`FileTypeHelper#image_file?` and `app/models/attachment.rb:209-213`'s `MAXIMUM_FILE_UPLOAD_SIZE` read, and return
`422` (the controller already has `render_error(..., :unprocessable_entity)` at `upload_controller.rb:51-53`). Do
not add a new allowlist; the exact-match one in `FileTypeHelper` is the existing mechanism. If article thumbnails
are added, leave `web_image_content_types` at its default.

### F5 — Platform documentation has no upload endpoint, and the obvious one to copy is unthrottled and account-scoped
**Severity: major. Reachable after the upgrade.**

Both article upload actions post to `/api/v1/accounts/${accountId}/upload`
(`app/javascript/dashboard/helper/uploadHelper.js:27-55,65-81`), reached through
`articles/attachImage` and `articles/uploadExternalImage`
(`app/javascript/dashboard/store/modules/helpCenterArticles/actions.js:164-172`). Platform documentation portals
have `account_id = NULL` and that is load-bearing for tenant isolation
(`docs/documentation-v2/01-current-system.md` §1, §10). **There is no account to scope a super-admin article
upload to**, so the upgrade must add an endpoint, and a new endpoint:

- will not match the Rack::Attack regex, so it is **unthrottled** (`config/initializers/rack_attack.rb:272-273`);
- must not be written as `ActionController::Base` + `skip_before_action :verify_authenticity_token`, the pattern
  at `app/controllers/public_controller.rb:3-5`;
- has no CSRF wiring to inherit on the client: the Super Admin Vue island
  (`app/javascript/entrypoints/superadmin_pages.js:1-34`) configures `VueDOMPurifyHTML` and nothing else — no
  axios instance, no `X-CSRF-Token` header. The token is in the layout (`app/views/layouts/super_admin/application.html.erb:27`)
  and must be read from there.

**Minimum control:** put the endpoint under `namespace :super_admin` in `config/routes/documentation.rb` so it
inherits `authenticate_super_admin!` and Administrate's `protect_from_forgery with: :exception`
(`app/controllers/super_admin/application_controller.rb:16`,
`…/administrate-0.20.1/app/controllers/administrate/application_controller.rb:3`), and add a path-matched throttle
beside the existing one in `rack_attack.rb`.

### F6 — Pasted clipboard HTML is already safe; the residual paste risk is a *failed* image mirror persisting a third-party URL
**Severity: minor for the author, major for readers. Reachable today.**

The brief asks about clipboard HTML carrying `<script>`, `onerror` and `javascript:` URLs. The pipeline closes
all three, at three layers, and it is worth stating plainly because it is the part that does not need fixing:

1. ProseMirror's clipboard parser maps pasted DOM onto the article schema. There is no raw-HTML node in
   `node_modules/@chatwoot/prosemirror-schema/src/schema/article.js`, so `<script>`, `onerror` and every unknown
   attribute are dropped on parse; a `<script>`'s text survives only as text.
2. Serialization goes back to Markdown (`ArticleMarkdownSerializer`, `FullEditor.vue:350-355`), so the stored
   column is CommonMark, not HTML. A pasted `javascript:` link can survive as `[x](javascript:…)`.
3. At render, that link is blanked by `DANGEROUS_URL_PATTERN` (`lib/markdown_renderer_url_sanitizer.rb:3,14-19`),
   and any HTML that somehow reached the column is omitted (§2(a)).

Pasted **remote images** are handled better than the brief assumes: they are mirrored into own storage.

```js
if (isSameOrigin(url)) return;
if (isValidImageUrl(url)) external.push(url);   // http/https only
else invalid.push(url);
```
(`node_modules/@chatwoot/prosemirror-schema/src/plugins/image.js:5-45`)

So the leak the brief describes is narrower than feared and wider in one place:

- **At paste time**, the image stays visible while mirroring (`image.js:25-27`), so the author's browser does make
  one request to the third-party host — the super admin's IP and the paste timing. `Referrer-Policy:
  strict-origin-when-cross-origin` (a Rails 7.0 default; `config.load_defaults 7.0` at `config/application.rb:39`,
  with no override anywhere in `config/`) means only the origin leaks, not the article path. This is the author's
  own action and I rate it **minor**.
- **When a mirror fails**, the node keeps its external `src` with retry/remove controls
  (`node_modules/@chatwoot/prosemirror-schema/src/plugins/uploads.js:194-222`), and **autosave does not wait for
  uploads**: `scheduleSave` checks only `isNewArticle` (`ArticleEditor.vue:121-124`), while `hasPendingUploads()`
  gates only route-leave and create (`:71-78,183-194`). So the third-party URL is persisted. Once published, every
  portal reader's browser hits that host, and the third party controls the bytes thereafter. With no `img-src`
  directive (§2) nothing constrains it. **Major**, and a documentation corpus is exactly the content where a
  silently-swapped image matters.

**Minimum control:** reject non-own-origin image URLs at save, where the corpus contract is already enforced —
the `lynomia:docs:seo_audit` rake task is the existing read-only auditor and already exits 1 on an error
(`docs/documentation-v2/01-current-system.md` §8). Add "article content references an off-installation image host"
as an error there; it costs nothing at author time and it is a release gate by construction. `img-src` in CSP
stage two is the defence in depth.

### F7 — SEO fields: no arbitrary keys, but no validation either, and the audit turns a blank field into a release blocker
**Severity: minor–major. Reachable today.**

Mass assignment is closed (§2(c)). What is open is **content**:

- `meta['title']` and `meta['description']` have no length or format validation anywhere — not in the field
  (`custom/app/fields/article_meta_field.rb`), not in the model (`app/models/article.rb:65-69` validates
  `account_id`, `author_id`, `title`, `content` and slug exclusion only). The hints state the intent in prose
  ("Around 150 characters reads best", `article_meta_field.rb:26`) and nothing enforces it.
- `compact_blank` (`articles_controller.rb:50`) **removes** a cleared key. An author who clears both the SEO
  description and the article description produces an article with neither, which the SEO audit grades as an
  **error**, and the audit exits non-zero — a release blocker by construction
  (`docs/documentation-v2/01-current-system.md` §8, §10). A text field with no validation can therefore stop a
  deploy. **Major**, as an availability finding rather than a security one.
- `feature_image` is a free-text "Feature image URL" (`article_meta_field.rb:21,30`) with no scheme or host
  check. Today it is rendered only by Vue as `:src` on the changelog card
  (`app/javascript/dashboard/components-next/changelog-card/StackedChangelogCard.vue:59-75`), where a
  `javascript:` value does not execute. **Minor today.**

One thing the upgrade must not do. `og:image` is emitted with `html_safe`:

```erb
<meta property="og:image" content="<%= og_image_url.html_safe %>">
```
(`app/views/public/api/v1/portals/documentation_layout/articles/_meta_head.html.erb:58-61`, and the same at
`…/categories/_meta_head.html.erb:30-33`, `…/portals/articles/_meta_head.html.erb:16-21`,
`app/views/public/api/v1/portals/_hero.html.erb:5-9`)

That is safe **only** because `og_image_url` is not author-controlled: it is built from `GlobalConfig` through
`URI.encode_www_form` (`app/helpers/portal_helper.rb:3-18`,
`app/controllers/public/api/v1/portals/articles_controller.rb:25`), which percent-encodes `"` and `<`. The field
is already labelled "Feature image URL" and an SEO-fields upgrade will want to wire it to `og:image`. **Wiring
`meta['feature_image']` into any of those four `html_safe` interpolations is immediate stored HTML injection into
the public `<head>`: `"><script>…</script>` breaks straight out of the `content` attribute.** Blocker, if it
happens.

**Minimum control:** validate the SEO fields at the controller boundary and return `422`, which is this
codebase's stated rule for request-boundary validation. The thresholds already exist as the audit's own numbers
(60-char title, 50–160 description, `docs/documentation-v2/01-current-system.md` §8) — read them from one place
rather than restating them. For `feature_image`, constrain to `https` on the installation's own host. For the
`<head>`, drop `.html_safe` rather than sanitizing around it: ERB's default escaping is the mechanism.

### F8 — Rich content components: 071's recommendation is the safe form; three implementation details decide whether it stays safe
**Severity: n/a (design finding). Reachable after the upgrade.**

First, the general rule, from the one component mechanism this repository already ships.
`config/markdown_embeds.yml` defines components as **regex + server-owned HTML template**; the author writes only
a URL on its own line (`lib/custom_markdown_renderer.rb:54-59,148-172`), and author input reaches the template
only through named captures, HTML-escaped at interpolation:

```ruby
match_data.named_captures.each do |var_name, value|
  template = template.gsub("%{#{var_name}}", CGI.escapeHTML(value))
end
```
(`lib/custom_markdown_renderer.rb:198-209`)

The editor preview reads **the same YAML file** (`app/javascript/dashboard/helper/markdownEmbeds.js:1`) and
escapes identically (`node_modules/@chatwoot/prosemirror-schema/src/plugins/embedPreview.js:35-49`). One source
of truth, two renderers that cannot drift in what they allow. So the safe form of a documentation component is
**a declarative registry entry, not author-written markup**: the author supplies parameters, the markup is
operator-owned and reviewed as code, both renderers read the same registry.

Agent 071 lands on exactly that shape and I endorse it on security grounds:
`docs/documentation-v2/discovery/071-structured-rich-content.md` §4.2 recommends **a blockquote whose first
inline child is a strong mark matching a declared label, recognised by `CustomMarkdownRenderer#blockquote` and
styled from a declarative `label → { class, icon, en, ar }` YAML map**, with its §4.4 explicitly rejecting raw
HTML, `<details>`, `<kbd>` and `> [!NOTE]`. Security-wise this is **strictly better than the embeds registry it
is modelled on**, for one reason worth naming: 071's map has **no `template` key**. The embeds map's `template`
field is precisely how this codebase ended up emitting third-party `<script src>` from author-written Markdown
(`config/markdown_embeds.yml:91-92,154`; F3, and `01-current-system.md` §5). A map of class names, icon
references and label text cannot do that. **Keep it that way: the moment a `template:` field appears in the
callout map, the mechanism has regressed to the embeds one.**

Three implementation details decide whether the recommendation survives contact with code:

1. **Emit the map's `class`, never the author's matched text.** 071's source form is `> **Note** — body`. A
   `blockquote` override that builds `class="cw-callout cw-callout-#{matched_label}"` from the author's bytes is
   attribute injection: `> **note" onmouseover=alert(1) x="** …`. The lookup must resolve the author's text to a
   **declared** entry and then interpolate that entry's own `class` and locale label. Mechanism: the same
   `self.class.config[embed_key]` lookup-then-use pattern at `lib/custom_markdown_renderer.rb:198-201`.
2. **The body must still go through the child-node path.** `out(:children)` or `super` keeps §2(a) in force
   inside the callout. The override must not build body HTML by string manipulation — note that the existing
   `table` override does exactly that (`capture_html` then `html.sub(/<table[^>]*>\n?/, opening)`,
   `lib/custom_markdown_renderer.rb:95-108`), which is safe only because every substituted value is a bounded
   integer. A callout override that copies that shape with a string value is not.
3. **The editor-side styling pass must not reuse `buildEmbedWidget`.** That function re-creates `<script>`
   elements to make them execute (`…/embedPreview.js:172-190`; F3). A callout preview needs CSS classes, not an
   HTML widget; styling the existing blockquote node is enough, and 071 §4.2 already says "nothing to build".

One caveat that belongs to the existing registry rather than to 071: `mp4`'s capture is an arbitrary host
(`config/markdown_embeds.yml:48`, `(?<link_url>https?://(?:www\.)?.+\.mp4)`) interpolated into `<source src>` —
the same reader-IP-leak shape as F6, by a different route.

### F9 — The autosave path: the tenant pattern is sound; the Super Admin version has no equivalent
**Severity: minor. Reachable after the upgrade.**

`articles.draft_content` and `articles.draft_title` already exist (`app/models/article.rb:8-9`) and the tenant
API writes them with the one correct subtlety:

```ruby
if keys.any? && (keys - %w[draft_title draft_content]).empty?
  @article.assign_attributes(article_params)
  @article.update_columns(article_params.to_h) if @article.valid?
else
  @article.update!(article_params)
end
```
(`app/controllers/api/v1/accounts/articles_controller.rb:94-106`)

`update_columns` skips timestamps **and** validations, and they assign-then-`valid?` first so the skip cannot
persist invalid data. That is the pattern to copy. Two things do not carry over:

- Super Admin has **no draft endpoint at all** — `config/routes/documentation.rb:11-17` is `resources :articles`
  plus `publish`/`unpublish`/`preview`. Adding one brings F5's CSRF and throttling questions with it.
- F1 is multiplied by autosave frequency. Fix F1 **before** autosave exists, not after.

Separately: a Super Admin draft is already visible to any signed-in super admin on the public portal
(`app/controllers/public/api/v1/portals/articles_controller.rb:80-88`), and `draft_content` is **not** what that
path renders — `show` renders `@article.content` (`:26`). An autosave-to-draft editor whose preview reads
`content` shows the author the wrong text. Correctness, not security, but it is the preview design's problem.

---

## 4. What the editor upgrade would newly expose

| Addition | New exposure | Already-present control | Gap |
|---|---|---|---|
| In-page live preview | author content executing with the super-admin session, same origin | server renderer omits raw HTML (§2a); JS parser `html: false` | no `script-src`; two renderers to keep in step; F2 |
| Embed preview in the editor | third-party `<script>` in the Super Admin origin on keystroke | `github_gist` excluded; captures escaped | `wistia` not excluded; F3 |
| Uploads | arbitrary content type, unbounded size, unthrottled new endpoint | Marcel re-identification + Rails binary-serving defaults; `FileTypeHelper`; `Attachment` validators | none of the validators are on this path; F4, F5 |
| Paste | third-party image URL persisted on mirror failure | schema drops HTML; http(s)-only; server-side mirror | autosave does not wait for uploads; no `img-src`; F6 |
| Rich components | author-authored markup becoming an injection vector | `markdown_embeds.yml` registry, one source, escaped captures | 071's syntax unreviewed; F8 |
| SEO fields | unvalidated strings; `og:image` wired to author input | key allowlist (§2c); ERB escaping | no field validation; four `html_safe` sinks; F7 |
| Autosave / drafts | write amplification over F1; a new endpoint | `draft_*` columns; the tenant `update_columns` pattern | no Super Admin endpoint; F1 must land first; F9 |

---

## 5. Required controls

Minimum set. Each maps to a mechanism already in this repository; none introduces a second sanitizer, a second
renderer or a new framework.

1. **`normalized_meta` merges instead of replaces.** Mechanism: `ArticleMetaField.permitted_attribute` stays the
   write filter. Closes F1. **Do this before autosave exists.**
2. **The preview renders server-side, through `ChatwootMarkdownRenderer#render_article`, into a frame — never
   into the Super Admin DOM.** If framed, `sandbox` without `allow-same-origin` and without `allow-scripts`.
   Mechanism: the existing renderer and `show_plain_layout`. Closes F2.
3. **Do not pass `embedPreviewPlugin` to the Super Admin editor instance.** Mechanism: it is an explicit argument
   at `FullEditor.vue:108`. Closes F3.
4. **Validate content type and byte size at the upload controller, returning `422`.** Mechanism:
   `FileTypeHelper#image_file?` and the `MAXIMUM_FILE_UPLOAD_SIZE` read at `app/models/attachment.rb:209-213`.
   Closes F4. Leave `web_image_content_types` at its default if thumbnails are added.
5. **Any new editor endpoint lives under `namespace :super_admin`,** inheriting `authenticate_super_admin!` and
   Administrate's `protect_from_forgery with: :exception`, with its own Rack::Attack throttle beside
   `rack_attack.rb:271`. Never `skip_before_action :verify_authenticity_token`. Closes F5.
6. **Add "references an off-installation image or media host" as an SEO-audit error.** Mechanism:
   `lib/tasks/documentation_seo_audit.rake`, which already exits 1 on an error. Closes F6's reader-side half and
   `mp4`'s in F8.
7. **Validate SEO field length and `feature_image` scheme/host at the request boundary (`422`),** reading the
   thresholds from wherever the audit holds them. **Drop `.html_safe` from the four `og:image` interpolations
   before wiring any author field to them.** Mechanism: ERB's default escaping. Closes F7.
8. **Finish CSP stage two** — `script-src`, `img-src`, `frame-src` — report-only first, as
   `config/initializers/content_security_policy.rb:10-13` already plans. This is the single control that degrades
   F2, F3 and F6 from "works" to "reported", and it is the only item here that is not a few lines.

## 6. Not checked

- Whether the `lynomia-docs` / `lynomia-changelog` portals carry a `custom_domain` in production. That decides
  whether the preview is cross-origin in fact, and it is a database question (`Portal#custom_domain`,
  `app/controllers/public_controller.rb:13`).
- The sanitization question in `docs/documentation-v2/01-current-system.md` §5 end to end — that is agent 065's
  and 081's scope. I reached §2(a) independently and it agrees with §5's **corrected** text (raw HTML is
  *omitted*, not escaped) and with `065-markdown-render-sanitization.md`. I verified only the claims §2 needs; I
  did not re-check §5's further points (`blob:` / `intent:` / protocol-relative URLs passing the scheme filter,
  and `:UNSAFE` not enabling `tagfilter`). Both strengthen the case for control 8.
- Blob URL authorization and expiry (`urls_expire_in` is unset, so blob URLs are durable) — agent 083.
- Whether the portal's third-party embed hosts are an acceptable trust set — agent 085, whose
  `085-external-links-iframes.md` and `01-current-system.md` §5 both now call for removing `github_gist` and
  `wistia` from the YAML. F3 is the **editor-origin** half of that and survives independently: the removal fixes
  it at the source, and until then `wistia` is the one script-bearing embed the editor preview does not exclude.
- DOMPurify's configuration on the Super Admin island: `app.use(VueDOMPurifyHTML)` is called with no config
  (`app/javascript/entrypoints/superadmin_pages.js:23`), unlike the dashboard and widget entrypoints which pass
  `domPurifyConfig`. I did not trace what that difference permits.
