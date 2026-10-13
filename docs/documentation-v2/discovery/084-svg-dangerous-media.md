---
agent: 084
scope: SVG and dangerous media types for documentation article media
confidence: high
---

Read against `claude/documentation-v2`. Gem citations are to the version the lockfile resolves
(`activestorage (7.2.3.2)` — `Gemfile.lock:62`; `marcel (1.1.0)` — `Gemfile.lock:542`;
`commonmarker (0.23.12)` — `Gemfile.lock:174`; `image_processing (1.12.2)` — `Gemfile.lock:440`). Two
ActiveStorage trees and two Marcel trees are vendored side by side; 7.2.3.1 and marcel-1.2.1 are not loaded and
nothing here cites them.

One sentence first, because the rest of the report depends on it: **an SVG uploaded to this installation today
is stored, is analyzed by libvips, and is then served as `application/octet-stream` with
`Content-Disposition: attachment` — not because anybody decided that, but because Rails' default
`content_types_to_serve_as_binary` has never been edited.** The product has no SVG policy. It has a framework
default, and the one file in this repository that touches those lists edits the *other* one.

---

## 1. Attack surface

### 1.1 The media path a documentation image would travel

There is no documentation media path today. `01-current-system.md` §9.8 says "No media story at all", and that
is literally true: `grep -rn '!\[' custom/db/documentation/` returns nothing, no `Article` carries an
attachment (`has_one_attached`/`has_many_attached` appear on `Portal#logo`, `DataImport`, `AutomationRule`,
`Account#contacts_export`, `Attachment#file`, `Avatarable#avatar`, `Macro#files`,
`PlatformSupport::{Message,InternalNote}` — `app/models/portal.rb:50`, `app/models/attachment.rb:43`,
`app/models/concerns/avatarable.rb:10`, `custom/app/models/platform_support/message.rb:39` — and **not** on
`Article`), and `ArticleDashboard::FORM_ATTRIBUTES` has no file field at all
(`custom/app/dashboards/article_dashboard.rb:36`).

So the surface in scope is the surface an editor upgrade will *reuse*. There is exactly one realistic
candidate, and it is already wired to the Help Center article editor:

| Hop | Code | What it does |
|---|---|---|
| Browser picks a file | `app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue:43-50,371-397` | client-side allowlist `png/jpeg/jpg/gif/webp` + `video/mp4` |
| POST multipart | `app/javascript/dashboard/helper/uploadHelper.js:27-55` | `POST /api/v1/accounts/:id/upload`, field `attachment` |
| Blob created | `app/controllers/api/v1/accounts/upload_controller.rb:16-45` | `ActiveStorage::Blob.create_and_upload!(io:, filename:, content_type:)` — **no validation of any kind** |
| URL returned | `upload_controller.rb:47-49` | `url_for(file_blob)` + `signed_id` |
| Markdown stores it | `app/javascript/dashboard/store/modules/helpCenterArticles/actions.js:164-172` | the raw blob URL is written into the article body as `![](url)` |
| Rendered | `lib/custom_markdown_renderer.rb:61-71` | hand-built `<img src="…">` |
| Served | `ActiveStorage::Blobs::RedirectController#show` → `ActiveStorage::DiskController#show` | activestorage-7.2.3.2 `app/controllers/active_storage/blobs/redirect_controller.rb:12-15`, `disk_controller.rb:12-22` |

A second entry point on the same controller fetches by URL:
`upload_controller.rb:21-37` → `SafeFetch.fetch(params[:external_url])` with the default
`allowed_content_type_prefixes = %w[image/ video/]` (`lib/safe_fetch.rb:4`,
`lib/safe_fetch/request_options.rb:12`, `lib/safe_fetch/fetcher.rb:70-76`). `image/svg+xml` starts with
`image/`, so the prefix allowlist admits it.

`/upload` is throttled 60/hour per account (`config/initializers/rack_attack.rb:272-275`). There is **no
server-side byte-size cap on it** — `Attachment#validate_file_size` (`app/models/attachment.rb:208-213`) lives
on a model this path never reaches, and the repo's nginx template sets `client_max_body_size 0`
(`deployment/nginx_chatwoot.conf:48`).

### 1.2 Where a content type is decided

Three places, and only one of them looks at bytes.

- `ActiveStorage::Blob.create_and_upload!` → `unfurl(io, identify: true)` → `extract_content_type(io)` →
  `Marcel::MimeType.for io, name: filename.to_s, declared_type: content_type`
  (blob.rb:107-110, 270-275, 367-369). `identify:` defaults to `true`, so even though
  `UploadController` passes the client's declared type, **the bytes are re-sniffed**.
- Direct-upload blobs are created with the client's declared `content_type` and `byte_size` and no file at all
  (blob.rb:118-121). They are re-identified later, at attach time:
  `Attached::Changes::CreateOne#initialize` calls `blob.identify_without_saving`
  (`lib/active_storage/attached/changes/create_one.rb:12`), reading the first 4 KB back out of storage
  (`blob/identifiable.rb:26-32`), and `belongs_to :blob, autosave: true`
  (`app/models/active_storage/attachment.rb:31`) persists the correction. Two direct-upload controllers exist
  (`app/controllers/api/v1/accounts/conversations/direct_uploads_controller.rb`,
  `app/controllers/api/v1/widget/direct_uploads_controller.rb`); the bare Rails route is blocked
  (`config/initializers/active_storage.rb:52-64`).
- Nothing else. There is no second sniffer, no `file(1)` shell-out, no virus scanner.

### 1.3 Where a file is executed, parsed or transformed

| Mechanism | Trigger | Code |
|---|---|---|
| `ImageAnalyzer::Vips` → `Vips::Image.new_from_file` | any blob whose `content_type.start_with?("image")`, on first attach | `lib/active_storage/analyzer/image_analyzer.rb:15-17`, `.../image_analyzer/vips.rb:9-11,22-39`, blob.rb:213-215 |
| `VideoAnalyzer` → `ffprobe` | any `video/*` | `.../video_analyzer.rb:25-27,136-138` |
| `AudioAnalyzer` → `ffprobe` | any `audio/*` | `.../audio_analyzer.rb:15,56-58` |
| `ImageAnalyzer::ImageMagick` | never — requires `variant_processor == :mini_magick` | `.../image_analyzer/image_magick.rb`, and `load_defaults 7.0` sets `:vips` (railties `configuration.rb:254`) |
| Previewers (Poppler/MuPDF/ffmpeg) | **never** — `config.active_storage.previewers = []` | `config/application.rb:70-71` |
| Variant re-encode via libvips | only on an explicit `.representation(...)` / `.variant(...)`, processed on demand in the web process | `blob/representable.rb:100-112,151-165`; `ActiveStorage::Representations::RedirectController:10-13` |
| Preprocessed variants | never — no `has_*_attached` declares named variants | `app/models/active_storage/attachment.rb:36,134-144` |

Analysis runs in Sidekiq on the `active_storage_analysis` queue (`config/sidekiq.yml:31`), i.e. in a worker
process, asynchronously, on a file nothing has validated.

Three existing `.representation(...)` callers would each become a documentation-media caller if an editor got
thumbnails: `app/models/attachment.rb:67-76` (rescues `UnrepresentableError`),
`app/models/concerns/avatarable.rb:15-19` (guards with `representable?`), and
`app/controllers/slack_uploads_controller.rb:19-26` (**neither** — see Finding 7).

---

## 2. What the existing defence actually does

### 2.1 The four ActiveStorage lists, as this installation actually has them

`config.load_defaults 7.0` (`config/application.rb:39`). Exactly one application file edits any of these
lists, and the edit is additive and audio-only:

```ruby
# config/initializers/active_storage.rb:1-13
# Allow audio attachments (call recordings, voice notes) to serve inline so the
# in-app <audio> player can stream them. …
Rails.application.config.active_storage.content_types_allowed_inline += %w[
  audio/webm audio/ogg audio/mpeg audio/mp4 audio/x-m4a audio/wav audio/x-wav
]
```

Effective values, therefore:

| Setting | Value | Source |
|---|---|---|
| `content_types_to_serve_as_binary` | `text/html`, **`image/svg+xml`**, `application/postscript`, `application/x-shockwave-flash`, `text/xml`, `application/xml`, `application/xhtml+xml`, `application/mathml+xml`, `text/cache-manifest` | engine default, **untouched** — activestorage `lib/active_storage/engine.rb:55-65` |
| `content_types_allowed_inline` | `image/webp avif png gif jpeg tiff bmp vnd.adobe.photoshop vnd.microsoft.icon` + `application/pdf`, **plus the 7 audio types above** | engine.rb:67-78 + `config/initializers/active_storage.rb:5-13` |
| `variable_content_types` | `image/png gif jpeg tiff bmp vnd.adobe.photoshop vnd.microsoft.icon webp avif heic heif` — **no SVG, no video** | engine.rb:35-47, untouched |
| `web_image_content_types` | `image/png image/jpeg image/gif` — **not webp**, because webp only joins at `load_defaults 7.2` (railties `configuration.rb:330-332`) and this app pins 7.0 | engine.rb:49-53 |
| `variant_processor` | `:vips` | railties `configuration.rb:254` |
| `previewers` | `[]` | `config/application.rb:71` |
| `urls_expire_in` / `resolve_model_to_route` | unset → blob URLs never expire, redirect mode | corroborated by `custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:3-10` |

### 2.2 What those lists do to an SVG, quoted

```ruby
# activestorage-7.2.3.2/app/models/active_storage/blob/servable.rb:4-21
def content_type_for_serving
  forcibly_serve_as_binary? ? ActiveStorage.binary_content_type : content_type
end

def forced_disposition_for_serving
  if forcibly_serve_as_binary? || !allowed_inline?
    :attachment
  end
end
…
  def forcibly_serve_as_binary?
    ActiveStorage.content_types_to_serve_as_binary.include?(content_type)
  end
```

`image/svg+xml` is in that list, so **both** branches fire: the served `Content-Type` becomes
`application/octet-stream` and the disposition is forced to `attachment`. This is applied in all three serving
modes:

- redirect/disk — `Blob#url` passes `content_type_for_serving` and `forced_disposition_for_serving || disposition`
  into the service (blob.rb:236-239), the Disk service bakes both into the *signed* key
  (`lib/active_storage/service/disk_service.rb:156-181`), and `DiskController` sets them as response headers
  from that signed key (`disk_controller.rb:12-22`, `concerns/active_storage/file_server.rb:7-20`). The
  `?disposition=` query parameter cannot override a forced disposition — `forced_disposition_for_serving ||
  disposition` puts the force first.
- proxy/stream — `send_blob_stream` uses the same two methods
  (`concerns/active_storage/streaming.rb:63-72`), and this is the method both Lynomia authorized readers call
  (`custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:50`,
  `custom/app/controllers/super_admin/platform_support_controller.rb:63-70`).
- cloud — `service_metadata` writes `content_type: application/octet-stream, disposition: :attachment` onto the
  object itself (blob.rb:375-383), so an S3/GCS presigned URL carries them even though no Rails header does.

Rails' own default headers are not overridden anywhere (`grep -rn default_headers config/ app/ custom/` is
empty), so Rails-served responses carry `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN` and
`X-XSS-Protection` (actionpack `lib/action_dispatch/railtie.rb:33-36`). The repo's nginx proxies everything to
Rails with no `location /storage` and no static root (`deployment/nginx_chatwoot.conf:33-37`), so it does not
bypass those headers; it only adds HSTS (`:62`).

CSP is two directives: `object_src :none; base_uri :self`
(`config/initializers/content_security_policy.rb:14-17`). No `script-src`, no `default-src`, no `sandbox`, no
`frame-ancestors`.

### 2.3 The one deliberate SVG control in the repository

```ruby
# lib/markdown_renderer_url_sanitizer.rb:3-18
DANGEROUS_URL_PATTERN = /\A(?:javascript:|vbscript:|file:|data:)/i
SAFE_DATA_IMAGE_PATTERN = %r{\Adata:image/(?:png|gif|jpeg|webp)}i
…
  def sanitized_href(url)
    url = url.to_s
    return '' if url.match?(DANGEROUS_URL_PATTERN) && !url.match?(SAFE_DATA_IMAGE_PATTERN)
    escape_href(url)
  end
```

`data:image/svg+xml` is `data:`-dangerous and is deliberately *absent* from the safe list, and
`spec/lib/base_markdown_renderer_spec.rb:77-83` asserts it blanks. That is the only place in this codebase
where somebody wrote down a judgement about SVG. It covers inline data URIs only, not uploaded files.

The second SVG judgement is client-side, in the editor, with a spec:

```js
// FullEditor.vue:41-50  — "Drop and paste bypass the file input's accept filter, so bucketFor gates
//                          every entry point with the same allowlist the picker advertises."
const ALLOWED_IMAGE_TYPES = ['image/png','image/jpeg','image/jpg','image/gif','image/webp'];
const ACCEPTED_FILE_TYPES = [...ALLOWED_IMAGE_TYPES, 'video/mp4'].join(', ');
```

`FullEditor.spec.js:939-947` — *"rejects an image type the picker does not advertise"* — selects
`new File(['x'], 'diagram.svg', { type: 'image/svg+xml' })` and asserts nothing is uploaded. That allowlist is
`file.type`, i.e. the browser's own guess, enforced in the browser. `/api/v1/accounts/:id/upload` has no
counterpart.

### 2.4 Raw HTML, and why inline `<svg>` is not the live hole

Confirmed independently and consistent with the corrected `01-current-system.md` §5: `CustomMarkdownRenderer`
is built with `options: :DEFAULT` (`commonmarker-0.23.12/lib/commonmarker/renderer.rb:10-18`), `:UNSAFE` is
never set anywhere, and so both `html` and `inline_html` emit `<!-- raw HTML omitted -->`
(`commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb:110-126`). An author who pastes
`<svg onload="…">` into the Markdown body publishes a comment. `spec/lib/custom_markdown_renderer_spec.rb:33-36`
asserts it for `<script>`.

### 2.5 libvips is told not to trust the file

```ruby
# activestorage-7.2.3.2/lib/active_storage/vips.rb:33-41
unless Vips.respond_to?(:block_untrusted)
  raise <<~ERROR.squish
    libvips's unfuzzed operations are not safe to use with untrusted content, and Active Storage
    cannot disable them. …
  ERROR
end
Vips.block_untrusted(true)
```

`deployment/deploy.sh:247-263` makes this a hard pre-deploy gate, with the reasoning written out. ruby-vips
documents `block_untrusted` as "Block/unblock all untrusted operations from running. Use `vips -l` at the
command-line to see … which operations are marked as untrusted"
(`vendor/bundle/ruby/3.4.0/gems/ruby-vips-2.3.0/lib/vips.rb:831-834`). **Which loaders are in that set on this
host is not determinable from this repository** — it is a libvips build property. Unverified; needs `vips -l`
on the host. I therefore do not claim that `svgload` is blocked, nor that it is reachable.

Variant generation is additionally pinned to the first page/frame:
`processor.source(file).loader(page: 0).convert(format).apply(operations).call`
(`lib/active_storage/transformers/image_processing_transformer.rb:19-26`).

### 2.6 The three product allowlists that exist

| Surface | Allowlist | Code |
|---|---|---|
| Avatars | `image/jpeg png gif webp`, 15 MB | `app/models/concerns/avatarable.rb:7,30-36` |
| Platform Support files | `image/png jpeg gif webp`, `application/pdf`, `text/plain`, `text/csv`; 10 MB; 5 files; read from `blob.content_type` **before** attach, refusal names the allowed set | `custom/app/models/platform_support/message.rb:29-34`, `custom/app/controllers/api/v1/accounts/platform_support/base_controller.rb:62-90` |
| Message attachments | `ACCEPTABLE_FILE_TYPES` + extension fallback — **but** short-circuited by `media_file?`, and only applied to `Channel::WebWidget` | `app/models/attachment.rb:27-40,186-221` |

The Platform Support one is the model to copy. The message one is the anti-pattern:

```ruby
# app/models/attachment.rb:186-192, 201-206, 215-217
def should_validate_file?
  return unless file.attached?
  # we are only limiting attachment types in case of website widget
  return unless message.inbox.channel_type == 'Channel::WebWidget'
  true
end
…
def validate_file_content_type(file_content_type)
  return if media_file?(file_content_type) || ACCEPTABLE_FILE_TYPES.include?(file_content_type)
…
def media_file?(file_content_type)
  file_content_type.to_s.start_with?('image/', 'video/', 'audio/')
end
```

`'image/svg+xml'.start_with?('image/')` is `true`. So the one product allowlist that a message attachment
passes through **admits SVG by prefix**, and for every channel that is not the web widget it does not run at
all. `Portal#logo` (`app/models/portal.rb:50`) has no content-type validation whatsoever and is rendered as
`<img src="<%= url_for(portal.logo) %>">` (`app/views/public/api/v1/portals/documentation_layout/_topbar.html.erb:12`).

---

## 3. Findings

**F1 — Nothing in this installation rejects an uploaded SVG; the only thing that saves it is an unedited Rails
default.** *Claim*: an authenticated agent can `POST /api/v1/accounts/:id/upload` with an `.svg` containing
`<script>` and receive a permanent, unauthenticated, same-origin URL for it. *Evidence*:
`app/controllers/api/v1/accounts/upload_controller.rb:16-45` performs no validation; `grep -rni svg` over
`app/ custom/ lib/ config/` in Ruby returns exactly one hit, `config/initializers/assets.rb:20`, which is the
asset pipeline. *Impact today*: the response is `Content-Type: application/octet-stream` +
`Content-Disposition: attachment` (§2.2), so navigating to it downloads a file instead of executing it; the
embedded `<img src>` shows a broken image with no diagnostic. *Severity*: **major** — not because the payload
runs today, but because the control is a default nobody chose, is one `-= %w[image/svg+xml]` from gone, and the
only file in this repo that touches those lists is already editing the sibling list for a product reason
(`config/initializers/active_storage.rb:1-13`). *Reachable*: today, for storage; execution only after a config
change.

**F2 — Removing SVG from `content_types_to_serve_as_binary` is full same-origin account takeover, and the
request for that change will arrive as a feature request.** *Claim*: with `image/svg+xml` served inline from
the app origin, a published documentation article's image URL becomes stored XSS on the portal origin, and the
blob URL becomes a one-click takeover link for any agent or super admin who clicks it. *Evidence*: CSP is
`object-src 'none'; base-uri 'self'` and nothing else (`content_security_policy.rb:14-17`) — no `script-src` to
stop the SVG's own `<script>`; `X-Content-Type-Options: nosniff` does not help, because a correctly declared
`image/svg+xml` needs no sniffing; blob URLs never expire and carry no authorization
(`custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:3-10`, written as the
reason that controller exists). *Note in mitigation*: **both** lists must change for inline SVG to happen —
`forced_disposition_for_serving` returns `:attachment` on `forcibly_serve_as_binary? || !allowed_inline?`
(`servable.rb:8-12`), so adding SVG to `content_types_allowed_inline` alone changes nothing. That accidental
two-key lock is worth converting into a deliberate one. *Severity*: **blocker** as a design constraint on
Phase 5. *Reachable*: only after a config change — which is precisely the change a "make diagrams render"
ticket would propose.

**F3 — The remote-fetch upload path admits SVG by MIME prefix.** *Claim*: `POST /upload` with
`external_url` pulls any resource the origin labels `image/*`, SVG included. *Evidence*:
`upload_controller.rb:21-24` → `SafeFetch.fetch(url)`; `DEFAULT_ALLOWED_CONTENT_TYPE_PREFIXES = %w[image/
video/]` (`lib/safe_fetch.rb:4`); `allowed_content_type?` is `mime.start_with?(prefix)`
(`lib/safe_fetch/fetcher.rb:70-76`). *Impact*: same as F1, plus the type gate here is the *remote server's*
assertion, re-checked only by Marcel afterwards. SSRF itself is handled (`ssrf_filter`,
`fetcher.rb:46-50`). *Severity*: **minor** today, **major** under F2. *Reachable*: today.

**F4 — Content type is determined from bytes, but Marcel will accept a declared type that is a descendant of
what it sniffed — and will fall back to the declared type entirely when magic finds nothing.** *Claim*: the
sniff is good but is not a proof, and a padded file can carry a type the bytes do not support. *Evidence*:

```ruby
# marcel-1.1.0/lib/marcel/mime_type.rb:29-32, 89-93
def for(pathname_or_io = nil, name: nil, extension: nil, declared_type: nil)
  filename_type = for_name(name) || for_extension(extension)
  most_specific_type for_data(pathname_or_io), for_declared_type(declared_type), filename_type, BINARY
end
…
def most_specific_type(*candidates)
  candidates.compact.uniq.reduce do |type, candidate|
    Marcel::Magic.child?(candidate, type) ? candidate : type
  end
end
```

Three concrete consequences, all verifiable from `marcel-1.1.0/lib/marcel/tables.rb`:

1. SVG's magic is `['image/svg+xml', [[0..4096, b['<svg']]]]` (`tables.rb:2522`) — a scan of the **first 4 KB
   only**. `MAGIC.send(:find)` returns the first table match (`magic.rb:86-89,117-125`), and `image/png` sits
   at `tables.rb:2515`, ahead of it.
2. `'image/svg+xml' => %w(application/xml)` (`tables.rb:2401`) with
   `child?(child, parent) = child == parent || TYPE_PARENTS[child]&.any? {…}` (`magic.rb:113-115`). So an SVG
   padded past 4 KB that still opens `<?xml` sniffs as `application/xml` (`tables.rb:2823`) and is then
   *promoted back* to `image/svg+xml` by a declared type or an `.svg` filename. Marcel is robust in that
   direction.
3. The exploitable direction: an SVG with >4 KB of leading whitespace and **no** `<?xml`, uploaded as
   `diagram.png` with `Content-Type: image/png`. `for_data` → `nil`; the reduce starts at the declared
   `image/png`; `child?(BINARY, 'image/png')` is false. **Result: `blob.content_type == 'image/png'` for a file
   that is an SVG.**

*Impact*: `nosniff` plus modern browsers' refusal to re-type a declared `image/*` make this a broken image
rather than script execution — but it is served *inline*, it defeats any extension/type-agreement check, and an
S3 presigned URL carries no `nosniff` at all (only the object's stored type, per `service_metadata`,
blob.rb:375-383). *Severity*: **minor** today; **major** as a design input, because it proves that type
identification alone can never establish that a file is a well-formed raster image. *Reachable*: today.

**F5 — Polyglots are classified by whichever magic sits earlier in Marcel's table, and nothing looks past it.**
*Claim*: a file with a valid PNG signature at offset 0 and an SVG or HTML document appended is stored as
`image/png` and served inline. *Evidence*: table order, `tables.rb:2515` (`image/png`) before `:2521`
(`text/html`) and `:2522` (`image/svg+xml`); `by_magic` → `find` (`magic.rb:86-89`). Only the first 4 KB is
ever examined on the direct-upload path (`blob/identifiable.rb:26-32`). *Impact*: latent. The payload is inert
while the response says `image/png` and `nosniff` is present, and becomes live the moment anything re-types the
file — a CDN that maps extension to type, an operator who downloads and double-clicks it, a future export.
*Severity*: **minor**. *Reachable*: today.

**F6 — `image/svg+xml` reaches libvips during analysis, and `image/svg+xml` is never asked for a variant.**
*Claim*: an attached SVG is handed to `Vips::Image.new_from_file`, but will never be rasterized by the variant
path. *Evidence*: `Analyzer::ImageAnalyzer.accept?(blob)` is `blob.image?`
(`lib/active_storage/analyzer/image_analyzer.rb:15-17`), `blob.image?` is
`content_type.start_with?("image")` (blob.rb:213-215) — so SVG is accepted, and
`.../image_analyzer/vips.rb:22-39` opens it. Conversely `variable?` is
`ActiveStorage.variable_content_types.include?(content_type)` (`blob/representable.rb:110-112`) and SVG is not
in that list, and `previewable?` is false because previewers are `[]`, so `representation` raises
`UnrepresentableError` (`representable.rb:151-165`). *Impact*: the analysis hop is the one place an SVG parser
could be reached. Whether libvips' `svgload` (librsvg) is in the blocked-untrusted set on this host is
**unverified** (§2.5); if it is not, an uploaded SVG is parsed by librsvg in a Sidekiq worker, which is the
classic XXE / external-reference / billion-laughs surface. If it is blocked, `new_from_file` raises
`Vips::Error` and is swallowed at `image_analyzer/vips.rb:26-28`. *Severity*: **major if unblocked, none if
blocked** — this is the single most important thing in this report that cannot be settled from the repository.
*Reachable*: today. *What is needed*: `vips -l | grep -i untrusted`, or
`Vips::Image.new_from_buffer(File.read('x.svg'), '')` on the host.

**F7 — `SlackUploadsController` 500s on any `image/*` blob that is not variable.** *Claim*: an SVG, HEIC-less,
or otherwise unvariable `image/*` blob reached through this unauthenticated route raises
`UnrepresentableError`. *Evidence*: `app/controllers/slack_uploads_controller.rb:19-26` calls
`@blob.representation(resize_to_fill: [250, nil])` whenever `content_type.start_with?('image/')`, with no
`representable?` guard and no rescue — unlike `app/models/attachment.rb:70-75` and
`app/models/concerns/avatarable.rb:16`. *Impact*: 500 + Sentry noise, and it is a blob reader keyed on the raw
`key` with no authorization (083's scope). *Severity*: **minor**. *Reachable*: today.

**F8 — HTML, XHTML, XML and PostScript uploads are accepted and are safe only by the same default as SVG.**
*Claim*: `text/html`, `application/xhtml+xml`, `text/xml`, `application/xml` and `application/postscript` all
upload cleanly and all rely on `content_types_to_serve_as_binary`. *Evidence*: engine.rb:55-65 lists all five;
`upload_controller.rb` validates nothing; `Attachment::ACCEPTABLE_FILE_TYPES` explicitly *permits* `text/xml`
and `application/xml` (`app/models/attachment.rb:28,30`) and `ACCEPTABLE_FILE_EXTENSIONS` permits a bare `xml`
by extension when the type is `application/octet-stream` (`:39-40,203`). The existing Platform Support
attachment reader documents the dependency in its own comment: *"a `text/html` upload downloads instead of
rendering in the operator's session"*
(`custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:30-35`). *Severity*:
**major** as a design constraint — one list protects five dangerous types at once, so one edit for one reason
unprotects all five. *Reachable*: today, for storage.

**F9 — PDF is served inline, and it is the only executing format on the inline allowlist.** *Claim*: a PDF with
JavaScript, an embedded launch action or an auto-submitting form renders in-browser on the app origin.
*Evidence*: `application/pdf` is in the engine's `content_types_allowed_inline` (engine.rb:77) and in
Platform Support's `ALLOWED_CONTENT_TYPES` (`custom/app/models/platform_support/message.rb:32`), and
`forced_disposition_for_serving` returns `nil` for it, so `DEFAULT_BLOB_STREAMING_DISPOSITION = "inline"`
applies (`concerns/active_storage/streaming.rb:7,66`). *Mitigations present*: the browser PDF viewer, not the
page, executes it, so it is not same-origin DOM access; and `previewers = []`
(`config/application.rb:71`) means **no Poppler or MuPDF ever touches a PDF server-side** — the server-side PDF
parser surface is closed by an explicit, deliberate line. *Severity*: **minor** for documentation media, and
the straightforward answer is that a documentation *image* has no reason to be a PDF. *Reachable*: today.

**F10 — Video and audio: `ffprobe` runs on every upload, inline audio was deliberately widened, video is not
variable and not inline.** *Evidence*: `VideoAnalyzer.accept?` is `blob.video?` and shells to `ffprobe`
(`.../video_analyzer.rb:25-27,136-138`); `AudioAnalyzer` the same (`:15,56-58`); seven audio types were added
to the inline allowlist for the in-app player (`config/initializers/active_storage.rb:1-13`); no `video/*` is
in `variable_content_types` or `content_types_allowed_inline`. The product nevertheless *does* support article
video: the Help Center editor accepts `video/mp4` (`FullEditor.vue:50`) and `config/markdown_embeds.yml:47-55`
turns any `.mp4` URL into `<video><source type="video/mp4">`. *Impact*: `ffprobe` is an unsandboxed
C-codec parser run on an unvalidated file in a worker, for every `video/*` and `audio/*` blob, with no
file-size cap on `/upload` and `client_max_body_size 0` in front of it. *Severity*: **major** for the upload
endpoint generally; for documentation media the answer is that documentation images are images and video
belongs on a separate, separately argued allowlist. *Reachable*: today.

**F11 — Animated GIF/APNG: bounded on the server, unbounded on the client.** *Claim*: frame-count exhaustion
is handled where a variant is generated and nowhere else. *Evidence*: variant generation is pinned to
`loader(page: 0)` (`image_processing_transformer.rb:19-26`), and `ImageAnalyzer::Vips` opens with
`access: :sequential` and reads only header dimensions (`image_analyzer/vips.rb:25`,
`image_analyzer.rb:19-27`). But the article body embeds the **original** blob URL
(`helpCenterArticles/actions.js:164-167` returns `fileUrl` from `/upload`, which is `url_for(file_blob)` —
`upload_controller.rb:48`), never a variant. *Impact*: a 10,000-frame GIF or a high-pixel-count APNG is
delivered byte-for-byte to every portal visitor, bounded only by a size limit that does not exist on this
endpoint. There is also no pixel-dimension limit anywhere, so a decompression-bomb PNG passes storage and
analysis unharmed and only detonates in a variant, or in a reader's browser. *Severity*: **major** —
availability and cost, on a public SEO surface. *Reachable*: today.

**F12 — Nothing in this repository strips EXIF, and a variant does not strip it either.** *Claim*: a screenshot
or photo uploaded for an article keeps its GPS coordinates, device model, serial number, software version,
capture timestamp and any embedded thumbnail, and publishing it publishes all of that. *Evidence*:
`grep -rni exif` over the whole repo excluding `vendor/` and `node_modules/` returns **nothing**. The only EXIF
read anywhere is orientation, for width/height swapping (`image_analyzer/vips.rb:42-47`). And the variant path
does not strip either: `image_processing` saves with
`image.write_to_file(path, **options)` after filtering to saver-valid options
(`image_processing-1.12.2/lib/image_processing/vips.rb:56-64`), and ActiveStorage passes no
`saver:`/`strip:`/`keep:` anywhere — so libvips' own default governs, and that default varies by libvips
version (**unverified on this host**). *Impact*: an author screenshots a dashboard on a phone, or pastes a
customer-supplied photo, and the public portal serves the location it was taken. This compounds 087's
credentials-in-screenshots scope: same file, different payload. *Severity*: **major** for a public
documentation portal. *Reachable*: today, as soon as any image is published.

**F13 — The editor's only media allowlist is in the browser.** *Claim*: `FullEditor.vue`'s allowlist, including
its SVG rejection and its 4 MB image cap, is enforced entirely client-side and has no server counterpart.
*Evidence*: `FullEditor.vue:40-50,371-397` and `FullEditor.spec.js:939-947` versus
`upload_controller.rb:16-45`. The component's own comment — *"Drop and paste bypass the file input's accept
filter, so bucketFor gates every entry point with the same allowlist the picker advertises"*
(`FullEditor.vue:41-42`) — shows the author was reasoning about bypasses within the browser and stopped at the
browser boundary. *Impact*: `curl` is the bypass. *Severity*: **major**. *Reachable*: today.

---

## 4. What the editor upgrade would newly expose

1. **A media insertion UI creates the first real reason to relax the SVG lists.** Today SVG is inert because
   nobody has tried to make a diagram render. The first author who uploads `architecture.svg`, gets a broken
   image with no error, and files a bug is the start of the change described in F2. The lists must be made
   deliberate *before* that ticket exists, with the reason written next to them, the way
   `config/initializers/active_storage.rb:1-4` already writes down why audio was widened.

2. **Paste.** A rich editor pastes from the clipboard, and a clipboard carries `text/html` alongside the image.
   Any pasted-HTML handling that preserves `<img src="data:…">` crosses `sanitized_href`'s data-URI rule
   (`lib/markdown_renderer_url_sanitizer.rb:3-18`), and any pasted-HTML handling that needs `:UNSAFE` to
   round-trip reopens inline `<svg>` — which the corrected `01-current-system.md` §5 already flags as a latent
   trap because `extensions: []` means `tagfilter` would not come with it.

3. **Thumbnails in a media library.** A picker showing uploaded images calls `.representation(...)`. That is
   the first time libvips *transforms* a documentation image rather than just reading its header, which brings
   the full decoder surface in — and it is processed **in the web process, on demand, by
   `ActiveStorage::Representations::RedirectController`** (`:10-13`), not in a worker, because
   `track_variants` is false. It is also the hop that would 500 on an SVG today (F6, F7).

4. **An `Article` attachment association.** There is none (§1.1), so Phase 4's decision 3 ("media ownership
   model") has to create one — and whatever model holds it needs the validation, because
   `UploadController` provably will not do it.

5. **Documentation images are public and permanent in a way message attachments are not.** A documentation
   article is served to anonymous readers on a portal built for SEO. Every blob URL in a published article is a
   permanent, unauthenticated, never-expiring URL (`platform_support/attachments_controller.rb:3-10`), which is
   correct for a public image and is exactly wrong for the EXIF in it (F12).

6. **Super Admin is session-authenticated.** The authoring surface is Devise `:super_admin`, not the token API,
   so a same-origin script in a Super Admin page runs with the session that can impersonate any user. That
   raises the cost of F2 specifically on the authoring surface.

---

## 5. Required controls

Each maps to a mechanism that already exists. Nothing here proposes a new subsystem; the governing rule in
§2 of the charter is satisfied by extending `Documentation::`-owned validation and the ActiveStorage config
that is already hand-edited once.

### 5.1 The allowlist

A documentation article image may be exactly one of:

| Content type | Why |
|---|---|
| `image/png` | screenshots, UI crops, anything with text or sharp edges. In `web_image_content_types`, `variable_content_types`, `content_types_allowed_inline`. |
| `image/jpeg` | photographs. Same three lists. |
| `image/webp` | smaller than both for the same quality; already the house format in every existing allowlist (`avatarable.rb:7`, `FullEditor.vue:43-49`, `platform_support/message.rb:32`). **Not** in `web_image_content_types` at `load_defaults 7.0`, so a WebP variant re-encodes to PNG — acceptable, and worth knowing before somebody blames the thumbnailer. |
| `image/gif` | only because the existing three allowlists all carry it and removing it would be a regression for existing portal articles. Subject to the frame and pixel caps in 5.4. |

Four types. Not `image/avif`, `heic`, `heif`, `tiff`, `bmp`, `vnd.adobe.photoshop` or `vnd.microsoft.icon`:
every one of those is in `variable_content_types` (engine.rb:35-47) and therefore reaches a libvips decoder,
none is a format an author produces deliberately, and `avif`/`heic`/`heif` are not in
`web_image_content_types` either. Not `application/pdf` — F9, and a PDF is a document, not an image. Not
`video/*` or `audio/*` — F10; article video already has its own path (`markdown_embeds.yml:47-55`,
`FullEditor.vue:50`) and needs its own argument, not a seat on the image allowlist.

### 5.2 How the type is determined — never from the filename

Three rules, in order:

1. **Read `blob.content_type` after ActiveStorage has identified it, never `params[:attachment].content_type`
   and never `File.extname`.** The identification already happens: `create_and_upload!` defaults to
   `identify: true` (blob.rb:107) and `Attached::Changes::CreateOne#initialize` re-identifies a direct-upload
   blob from storage (`create_one.rb:12`). The filename contributes to Marcel's decision only as a tiebreaker
   among same-family candidates (`marcel mime_type.rb:29-32,89-93`), which is correct; it must never be the
   decision.
2. **Validate at one shared entry point, and validate the identified type.** Copy
   `custom/app/controllers/api/v1/accounts/platform_support/base_controller.rb:73-90` exactly: resolve the
   signed id, compare `blob.content_type` against a frozen constant, raise a `CustomExceptions::` error whose
   message names the accepted set, check the byte size, return `422`. That controller is the only place in this
   repository that does this correctly, and it already proves the pattern against `ALLOWED_CONTENT_TYPES` on
   the owning model (`platform_support/message.rb:29-34`). Put the documentation constant on whatever model
   Phase 4 decision 3 gives the image to, and put the check on the documentation upload boundary. Do **not**
   add it to `UploadController`, which is shared with conversations and the widget; a documentation editor
   needs its own endpoint or its own parameter, so that the documentation allowlist is not a conversation
   regression.
3. **Never use a `start_with?('image/')` prefix test.** `app/models/attachment.rb:215-217` is the live
   counter-example: it admits `image/svg+xml` by prefix. Exact-match against a frozen array, as all three good
   allowlists do.

Because F4 proves identification is not a proof of well-formedness, add one more check that *is*: **re-encode
on accept.** Call `blob.variant(resize_to_limit: [MAX_W, MAX_H], saver: { strip: true })` and store the result
as the canonical article image. A padded-SVG-named-PNG fails `Vips::Image.new_from_file` and is rejected with a
real error; a polyglot loses everything after the image data; a decompression bomb is caught at decode by a
process that can be given a timeout. This is one existing API call
(`blob/representable.rb:100-106`), it runs through the same libvips that is already gated at deploy
(`deploy.sh:247-263`) and already told `block_untrusted(true)` (`active_storage/vips.rb:41`), and it also
solves 5.3. Re-encode in the `active_storage_analysis` worker (`config/sidekiq.yml:31`), not in the request.

### 5.3 EXIF

Strip it, by re-encoding, and verify the strip rather than assuming it.

`image_processing` passes no metadata option (`image_processing/vips.rb:56-64`), so an unadorned variant inherits
whatever libvips' version-dependent default is (F12). Pass `saver: { strip: true }` explicitly in the variant
transformations, and add one spec that uploads a GPS-bearing JPEG fixture and asserts the stored article image
has no `exif-ifd0-*` / `gps-*` fields. Without that spec this control silently depends on the libvips build on
the host, which is exactly the class of thing `deploy.sh:247-263` exists to stop depending on silently.

Serve the stripped derivative to the portal, not the original. Today the editor embeds the original
(`helpCenterArticles/actions.js:164-167`), which is what makes F11 and F12 reachable at all.

### 5.4 Size, dimension and frame caps

| Cap | Value | Enforce at |
|---|---|---|
| Byte size | 4 MB, matching the number the editor already shows authors (`FullEditor.vue:40`) | the documentation upload boundary, server-side — the client cap is not a cap (F13) |
| Pixel count | a decoded-pixel ceiling (e.g. 50 Mpx) | before the variant; libvips reports dimensions from the header without a full decode (`image_analyzer.rb:19-27`) |
| Frames | 1 — a documentation image is a still | `loader(page: 0)` already does this for the variant (`image_processing_transformer.rb:19-26`); serving the variant rather than the original makes it real (F11) |

### 5.5 Headers the serving route must set

Documentation images must not be served by `ActiveStorage::Blobs::RedirectController`. That route performs no
authorization, its URLs never expire, and the disposition is partly caller-controlled
(`blobs/redirect_controller.rb:12-15`; `platform_support/attachments_controller.rb:3-10` is this repo's own
written-down verdict on it). Serve them from a documentation-owned action built the way the two Platform
Support readers are built — `include ActiveStorage::Streaming`, look the record up through a documentation
scope, call `send_blob_stream(blob)` with **no** disposition argument so `forced_disposition_for_serving` keeps
its authority (`streaming.rb:63-72`; `platform_support/attachments_controller.rb:30-35,48-51` explains that
choice better than I can restate it). Then:

| Header | Value | Why |
|---|---|---|
| `Content-Type` | the identified type, from the blob, from the allowlist in 5.1 | never from `params`, never from the extension |
| `Content-Disposition` | `inline` for the four allowed types; `attachment` for everything else, by `forced_disposition_for_serving`, not by a second copy of the list | one authority, already correct |
| `X-Content-Type-Options` | `nosniff` | Rails default, present (actionpack `railtie.rb:36`); the point is not to lose it. It is the control that keeps F4 and F5 inert. |
| `Content-Security-Policy` | at minimum `default-src 'none'; sandbox`, scoped to this route | the app-wide policy is two directives (`content_security_policy.rb:14-17`); an image response needs no sources at all, and a per-route `default-src 'none'; sandbox` is the control that would make even an inline-served SVG harmless |
| `Cross-Origin-Resource-Policy` | `same-site` (or `cross-origin` only if the portal is served from another host) | cheap, and blob URLs are currently embeddable by anyone |
| `Cache-Control` | `public, max-age=…, immutable` | these are content-addressed derivatives; the existing proxy path already does `http_cache_forever public: true` (`blobs/proxy_controller.rb:18`) |

If the installation runs on S3/GCS (`config/environments/production.rb:43`), none of those Rails headers reach
a presigned URL — only `service_metadata`'s stored `content_type`/`disposition` do (blob.rb:375-383). That is
an argument for proxy-mode serving for documentation media specifically, and it is a question for Phase 4
decision 3 rather than something I can settle from the repository.

### 5.6 The SVG decision, argued

**Recommendation: no SVG as uploaded article media. Mark `image/svg+xml` as permanently excluded, in a comment
next to the ActiveStorage lists, with the reason — and keep it in `content_types_to_serve_as_binary` so that an
SVG that arrives by any other route stays inert.**

What that costs, honestly:

- **Diagrams.** An architecture or flow diagram is the thing SVG is genuinely best at: it is small, it is
  text-searchable, it scales, and it can be diffed in git. A 1600 px PNG export of the same diagram is 10× the
  bytes and blurs on a 3× display.
- **Icons and callouts.** Inline UI icons at arbitrary size, crisp on every display, without a sprite sheet.
- **Crisp screenshots at any zoom.** SVG does not actually help here — a screenshot is raster — but
  *annotations over* a screenshot (arrows, numbered callouts, highlight boxes) are vector, and exporting them
  to PNG bakes them at one resolution.
- **RTL.** A diagram whose labels need mirroring for the Arabic corpus is editable as SVG and is a second
  export as PNG. For a bilingual corpus (`Documentation::Library::LOCALES = %w[en ar]`) that is a real,
  recurring cost, not a theoretical one.

Why it still loses:

1. **The whole of SVG's danger is the one thing an uploaded file cannot be stopped from becoming: a top-level
   document on the app origin.** An SVG referenced from `<img src>` cannot execute script or load external
   references — that is specified, and the Markdown renderer emits nothing but `<img>`
   (`lib/custom_markdown_renderer.rb:61-71`), and `object-src 'none'`
   (`content_security_policy.rb:15`) already blocks `<object>`/`<embed>`. So "SVG in an article body" is, in
   itself, defensible. But the file is simultaneously reachable at its own URL, and authors paste those URLs,
   and agents and super admins click them. One navigation to a same-origin `image/svg+xml` with no `script-src`
   in the CSP is account takeover. The safe context and the unsafe context are the *same file* behind the
   *same URL*, and only a header separates them.
2. **Making it safe means getting four independent things right and keeping them right.** SVG would have to be
   excluded from `content_types_to_serve_as_binary` (to render) while being pinned to a route that forces a
   per-response `Content-Security-Policy: default-src 'none'; sandbox`, and sanitized at upload by an
   XML-aware allowlist that strips `<script>`, `<foreignObject>`, every `on*` attribute, every `xlink:href`/
   `href` that is not a local fragment, every external entity and DTD, `<use>` to a remote document, and
   `<style>` containing `url()` — and re-sanitized whenever that library's own CVEs land. This repository has
   no HTML/XML sanitizer in the article path at all; the render path works by *omitting* raw markup
   (`html_renderer.rb:110-126`), not by cleaning it. Adding SVG means adding the first sanitizer this product
   has ever had, for the single most bypass-prone format there is, to serve diagrams.
3. **This installation would additionally have to answer F6**, because an SVG that is permitted is an SVG that
   reaches `Vips::Image.new_from_file` in a worker (`image_analyzer/vips.rb:25`), and nobody here knows whether
   librsvg is blocked on the host.
4. **The product has already decided this twice.** `SAFE_DATA_IMAGE_PATTERN` lists png, gif, jpeg, webp and
   deliberately omits svg, with a spec (`lib/markdown_renderer_url_sanitizer.rb:4`,
   `spec/lib/base_markdown_renderer_spec.rb:77-83`). The Help Center editor's allowlist omits svg, with a spec
   whose name is *"rejects an image type the picker does not advertise"* (`FullEditor.vue:43-49`,
   `FullEditor.spec.js:939-947`). Phase 5 should ratify those two decisions, not quietly reverse them.

**The safe alternative, which recovers most of what is lost:**

- **Author diagrams as SVG in source control; publish PNG.** The corpus is already Markdown in git
  (`custom/db/documentation/`), so a diagram's `.svg` source can live beside its article and a build step can
  export a 2× PNG. The editable, diffable, searchable source is kept; only the *served* artifact is raster.
  This is also the only option that keeps an EN and an AR diagram in sync, because they are two exports of one
  source.
- **Serve the PNG as a 2× asset with explicit `width`/`height`.** The renderer already supports an author-set
  width via `cw_image_width` with a bounded `\A(\d+)px\z` parse (`lib/custom_markdown_renderer.rb:130-146`),
  so a 2× PNG displayed at 1× is crisp on high-DPI displays and needs no new mechanism.
- **For icons and callouts, use a vetted icon set shipped as application assets**, not as uploaded media.
  `config/initializers/assets.rb:20` already precompiles `*.svg`, and an SVG in the asset pipeline is authored
  by a developer, reviewed in a PR and served from the asset host — a completely different trust class from a
  file an author uploaded this morning.
- **If vector output is later judged essential**, the correct shape is a `<picture>`/`<img>` whose SVG is served
  from a separate origin (an asset host or a dedicated subdomain) with `default-src 'none'; sandbox`, so that
  executing it buys the attacker nothing. That is a hosting decision, not an editor feature, and it should be
  argued on its own rather than smuggled in as a MIME-list edit.

### 5.7 Fail loudly

Two silent failures in the current code would become documentation failures. An SVG upload today succeeds and
then renders as a broken image with no message anywhere — the author learns nothing. And
`app/models/attachment.rb:70-75` swallows `UnrepresentableError` into an empty thumbnail URL with a
`Rails.logger.warn`. A documentation media path should refuse the upload at the boundary with a `422` that
names the accepted types — exactly what
`CustomExceptions::PlatformTickets::AttachmentTypeRejected` already does
(`platform_support/base_controller.rb:76-80`: *"every refusal names the limit or the accepted types, because a
customer whose screenshot was rejected needs to know what would be accepted"*).

---

## 6. Not checked

- **Whether libvips' untrusted set on the production host includes `svgload`** (F6). Not determinable from the
  repository; needs `vips -l` on the host. This is the one open question that could turn F6 from "none" to
  "major".
- **Whether libvips' metadata default on the host keeps or drops EXIF through `write_to_file`** (F12). The
  recommendation is to pass `saver: { strip: true }` explicitly and spec it, so the answer stops mattering.
- **Whether `ffprobe` is installed on the host** (F10). If it is not, both media analyzers log and skip
  (`video_analyzer.rb:149`, `audio_analyzer.rb:69`) and that parser surface is closed by accident rather than
  by decision.
- **Which `ACTIVE_STORAGE_SERVICE` production actually runs** (`config/environments/production.rb:43`). The
  header story in 5.5 differs between disk and S3.
- **Whether the deployed nginx matches `deployment/nginx_chatwoot.conf`.** It is a template with placeholder
  domains; `client_max_body_size 0` and the absence of any `/storage` location are both load-bearing for this
  report and both unverified on the host.
- `?disposition=` header-injection potential through `content_disposition_with` on the Disk service
  (`disk_service.rb:164-170`) — noted, not pursued; it belongs to 083.
