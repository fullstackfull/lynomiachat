---
agent: 066
scope: ActiveStorage as this installation actually configures it — services, variants, content-type policy, URL generation, signed-ID expiry, direct uploads, the existing attachment surfaces and how each authorizes a read; then how a documentation article image should be stored and served
confidence: high
---

Template EDITOR. Every repository claim carries `path:LINE`. Gem behaviour is cited against the **vendored**
copy actually installed — `vendor/bundle/ruby/3.4.0/gems/activestorage-7.2.3.2/` — not against memory of Rails.
Two facts are unverified because they live on the production host and not in this repository; both are named as
such in §3.

---

## 1. What exists today

### 1.1 One service definition file, six services, one selected by ENV

`config/storage.yml` defines six services and nothing selects one:

| Key | Adapter | Root / bucket | `storage.yml` |
|---|---|---|---|
| `test` | `Disk` | `tmp/storage` | `:1-3` |
| `local` | `Disk` | `Rails.root.join("storage")` | `:5-7` |
| `amazon` | `S3` | `S3_BUCKET_NAME` + `AWS_*` | `:10-16` |
| `google` | `GCS` | `GCS_BUCKET` | `:18-23` |
| `microsoft` | `AzureBlob` | `AZURE_STORAGE_CONTAINER` | `:25-31` |
| `s3_compatible` | `S3` + `endpoint` | `STORAGE_BUCKET_NAME` | `:33-40` |

`mirror` is present but commented out (`config/storage.yml:42-45`). Every cloud service reads its credentials
from `ENV.fetch(..., '')`, so a misconfigured one yields an empty-string credential rather than a boot failure.

Selection, per environment:

| Environment | `config.active_storage.service` | Evidence |
|---|---|---|
| production | `ENV.fetch('ACTIVE_STORAGE_SERVICE', 'local').to_sym` | `config/environments/production.rb:43` |
| development | `ENV.fetch('ACTIVE_STORAGE_SERVICE', 'local').to_sym` | `config/environments/development.rb:33` |
| test | `:test` | `config/environments/test.rb:38` |
| **staging** | **never set** | `grep -c active_storage config/environments/staging.rb` → `0` |

**The production service is local disk unless an operator set `ACTIVE_STORAGE_SERVICE`.** `.env.example:143`
ships `ACTIVE_STORAGE_SERVICE=local`, and the only other place the variable appears outside `docs/` is
`docs/commerce/e2e/e2e.env.example:14`, also `local`. `.gitignore:59` ignores `/storage`. A prior first-hand
infrastructure pass recorded the same conclusion and added two consequences: `storage/` survives deploys only
because the deploy is a `git pull` in place into an ignored path, and it is covered by no `pg_dump`, so a
database-only restore comes back with every attachment URL broken
(`docs/p7/00-discovery-findings.md:801`, SHO-60).

**Staging has no Active Storage service at all.** `staging.rb` sets neither the service nor a default, and
`config/application.rb` does not set one either, so `ActiveStorage::Blob.service` resolves against a `nil`
service name. Any attachment read or write in `RAILS_ENV=staging` fails. This is not a documentation problem but
it is a deployment-shaped one, and it bites exactly when a documentation author is asked to "check it on
staging".

### 1.2 Variant processor: vips, by framework default, never written down

`config.active_storage.variant_processor` appears nowhere in `config/`, `app/`, `custom/` or `lib/`. It is set
by `config.load_defaults 7.0` (`config/application.rb:39`), whose `"7.0"` block assigns
`active_storage.variant_processor = :vips`
(`vendor/.../railties-7.2.3.2/lib/rails/application/configuration.rb`, the `"7.0"` branch, `variant_processor`
line). Without that default the engine would fall back to `:mini_magick`
(`activestorage-7.2.3.2/lib/active_storage/engine.rb:93`).

So the processor is vips, and it is vips by inheritance rather than by decision. `image_processing (1.12.2)`
(`Gemfile.lock:440-442`) and `ruby-vips (2.3.0)` (`Gemfile.lock:843`) are both installed; `mini_magick (4.12.0)`
is present only as an `image_processing` dependency.

`config.active_storage.previewers = []` (`config/application.rb:71`) with the comment *"Disable PDF/video
preview generation as we don't use them"*. Consequence, and it matters for §4: `Blob#previewable?` is always
false (`activestorage-7.2.3.2/app/models/active_storage/blob/representable.rb:138`), so
`blob.representation(...)` can only ever take the `variant` branch
(`representable.rb:151-160`) and `UnrepresentableError` is raised for any non-image rather than being silently
previewed.

### 1.3 The libvips precondition is a boot gate, not a degradation

`deployment/deploy.sh:247-263` is stage 4b. Read literally:

- Rails 7.2.3.2 carries a fix for CVE-2026-66066 that makes Active Storage **raise on `require`** unless
  `Vips.respond_to?(:block_untrusted)` — which needs libvips ≥ 8.13 and ruby-vips ≥ 2.2.1
  (`deploy.sh:250-253`). The gem code is `activestorage-7.2.3.2/lib/active_storage/vips.rb:33-38`, which raises
  *"libvips's unfuzzed operations are not safe to use with untrusted content, and Active Storage cannot disable
  them"*, then `Vips.block_untrusted(true)` at `vips.rb:40`.
- The lockfile moved ruby-vips from 2.1.4 to 2.3.0; **the libvips half is a system package the deploy script
  cannot install** (`deploy.sh:253`).
- Every Rails process aborts, web and worker alike, so an old libvips turns the stage-7 restart into an outage
  with no rollback of its own (`deploy.sh:255-258`). The check runs after the backup and before any schema
  change, deliberately, so a failure costs one unused dump (`deploy.sh:258-259`).
- The failure message names the remedy: `apt-get install --only-upgrade libvips42` (`deploy.sh:263`).

`deployment/setup_20.04.sh:852,889` installs `libvips` unpinned via `apt-get install libvips -y`, and
`:231` lists `libvips` among base packages. Ubuntu 20.04's `libvips42` is 8.9.x — **below the 8.13 floor** — so a
host provisioned by that script and never upgraded is exactly the host stage 4b exists to stop.

`VIPS_BLOCK_UNTRUSTED=1` is shipped in `.env.example:149` and baked into the container at
`docker/Dockerfile:134`, with the note *"Requires libvips >= 8.13 (ignored on older versions)"*. On 7.2.3.2 that
variable is belt-and-braces: `vips.rb:40` calls `block_untrusted(true)` unconditionally.

**Unverified**: the libvips version on the production host. I cannot read it from the repository. What would be
needed is the stage-4b line from the last deploy log, which prints `libvips X.Y.Z, ruby-vips 2.3.0`
(`deploy.sh:261-262`).

### 1.4 Content-type policy: three lists, one of them locally amended

| List | Effective value | Set at |
|---|---|---|
| `variable_content_types` | engine default: png, gif, jpeg, tiff, bmp, photoshop, x-icon, **webp, avif, heic, heif** | `engine.rb:35-47`; **no local override** |
| `web_image_content_types` | engine default: **png, jpeg, gif only** | `engine.rb:49-53`; the `"7.2"` defaults block would have added webp, but this app is on `load_defaults 7.0` |
| `content_types_to_serve_as_binary` | engine default: `text/html`, **`image/svg+xml`**, `application/postscript`, flash, `text/xml`, `application/xml`, `application/xhtml+xml`, `application/mathml+xml`, `text/cache-manifest` | `engine.rb:55-65`; **no local override** |
| `content_types_allowed_inline` | engine default (webp, avif, png, gif, jpeg, tiff, bmp, psd, x-icon, pdf) **`+= 7 audio types`** | `engine.rb:67-78` plus `config/initializers/active_storage.rb:5-13` |

The one local amendment is additive and documented: seven audio types (`audio/webm`, `ogg`, `mpeg`, `mp4`,
`x-m4a`, `wav`, `x-wav`) are appended to `content_types_allowed_inline` so the in-app `<audio>` player can
stream call recordings instead of downloading them (`config/initializers/active_storage.rb:1-13`). Nothing in
the repository touches `content_types_to_serve_as_binary` or `variable_content_types`.

Serving is decided by `Blob#service_metadata` (`activestorage-7.2.3.2/app/models/active_storage/blob.rb:375-382`):
`forcibly_serve_as_binary?` → `application/octet-stream` + `disposition: attachment`; else `!allowed_inline?` →
real type + `attachment`; else real type and the caller's disposition.

Two consequences carry straight into §4:

1. **SVG cannot be rendered inline by any Active Storage route.** `image/svg+xml` is in
   `content_types_to_serve_as_binary`, so an SVG blob is served as `application/octet-stream` with
   `Content-Disposition: attachment`. An `<img src>` pointing at it renders nothing. The same rule is what closes
   stored-XSS from an HTML or SVG upload against the app origin, and it was recorded as holding
   (`docs/p7/00b-discovery-informational.md:539`). **Do not propose SVG documentation diagrams served through
   Active Storage.**
2. **WebP and AVIF are variable but not "web images".** Both are in `variable_content_types` and in
   `content_types_allowed_inline`, so the *original* serves inline fine. But `default_variant_format`
   (`representable.rb:180-190`) returns the blob's own extension only `if web_image?`, and `web_image?` reads
   `web_image_content_types` (`blob.rb:371-373`) — png/jpeg/gif. So **any variant of a WebP or AVIF blob is
   transcoded to PNG**, usually several times larger than the WebP it came from. Any responsive-image plan for
   the documentation portal has to either serve originals, or set
   `config.active_storage.web_image_content_types` explicitly.

### 1.5 URL generation and signed-ID expiry

Routes come from the Active Storage engine, unmodified: `ActiveStorage.routes_prefix` is
`/rails/active_storage` and `draw_routes` is on, because neither is set locally
(`engine.rb:97-98`; `grep` for `routes_prefix|draw_routes` in `config/ app/ custom/ lib/` is empty). So all of
these exist (`activestorage-7.2.3.2/config/routes.rb:5-15`):

```
/blobs/redirect/:signed_id/*filename              → rails_service_blob        (302 to a service URL)
/blobs/proxy/:signed_id/*filename                 → rails_service_blob_proxy  (streams the bytes)
/representations/redirect/:signed_blob_id/:variation_key/*filename
/representations/proxy/:signed_blob_id/:variation_key/*filename
/disk/:encoded_key/*filename                      → rails_disk_service
```

and the polymorphic helpers `rails_blob_path/url`, `rails_representation_path/url`,
`rails_storage_proxy_path/url` and `rails_storage_redirect_path/url` (`routes.rb:18-31,33-57,59-81`).

`ActiveStorage.resolve_model_to_route` is **never set** (grep empty), so it stays `:rails_storage_redirect`
and `url_for(blob)` / `rails_blob_path(blob)` / `url_for(variant)` all resolve to the **redirect** family.

**Expiry — this is the fact everything else hangs off.** The engine wires two separate knobs
(`engine.rb:119-120`):

```ruby
ActiveStorage.service_urls_expire_in = app.config.active_storage.service_urls_expire_in || 5.minutes
ActiveStorage.urls_expire_in         = app.config.active_storage.urls_expire_in
```

Neither is set in this repository (grep empty). Therefore:

- `service_urls_expire_in` = **5 minutes** — the lifetime of the *final* URL (the S3 presigned URL, or the
  `/rails/active_storage/disk/...` token).
- `urls_expire_in` = **nil** — the signed id in a `rails_blob_*` / `rails_storage_proxy_*` URL **never expires**.
  `rails_storage_redirect` and `rails_storage_proxy` both read it as the default for `expires_in`
  (`routes.rb:34,60`), and `nil` means a permanent signature.

A `/rails/active_storage/blobs/redirect/<signed_id>/<filename>` URL is therefore a **permanent, unauthenticated
bearer token for one blob**. Every Active Storage controller is public:
`ActiveStorage::BaseController < ActionController::Base` with no authentication
(`app/controllers/active_storage/base_controller.rb:1-10`), and `SetBlob#set_blob` does a bare
`ActiveStorage::Blob.find_signed!` with no scope (`app/controllers/concerns/active_storage/set_blob.rb:11-19`).
The gem's own headers say so: *"All Active Storage controllers are publicly accessible by default. The generated
URLs are hard to guess, but permanent by design."*
(`app/controllers/active_storage/blobs/redirect_controller.rb:5-8`, and identically in both proxy controllers.)

**Caching differs sharply between the two families**, and this is decisive for a documentation portal:

| Route | Response | Cache headers | Rails hits per image view |
|---|---|---|---|
| redirect | `302` to `blob.url` | `expires_in ActiveStorage.service_urls_expire_in` → `Cache-Control: max-age=300, private` (`blobs/redirect_controller.rb:13`) | 2 (redirect + disk), then 2 again after 5 minutes |
| proxy | `200` with the bytes | `http_cache_forever public: true` → `expires_in 100.years, public: true` + ETag (`blobs/proxy_controller.rb:18`; `actionpack-7.2.3.2/lib/action_controller/metal/conditional_get.rb:317-323`) | 1, ever |

On a local-disk install the redirect's second hop is `ActiveStorage::DiskController#show`
(`app/controllers/active_storage/disk_controller.rb:28-38`), which serves via `Rack::Files` and adds no long
`Cache-Control`. So **every documentation image on the redirect route costs two Rails requests per reader per
five minutes and is never cached by a browser or a CDN.** `deployment/nginx_chatwoot.conf` has a single
`location /` that proxies everything to Puma with no static or cache handling (`:33-50`), and `ASSET_CDN_HOST`
only sets `config.action_controller.asset_host` for the asset pipeline
(`config/environments/production.rb:37`) — it does not touch Active Storage.

Representation URLs are safe against transformation injection: the `variation_key` is signed with
`purpose: :variation` (`app/models/active_storage/variation.rb:41-43`) and
`Representations::BaseController#set_representation` resolves it through the verifier, answering `404` on an
invalid signature (`app/controllers/active_storage/representations/base_controller.rb:13-17`). The variant is
materialised on demand by `.processed` in that same method.

The repository's own `rails_blob_*` / `url_for(blob)` call sites:

| Call site | Helper | Audience |
|---|---|---|
| `app/models/attachment.rb:58` (`file_url`) | `url_for(file)` | message attachment, dashboard + widget |
| `app/models/attachment.rb:71` (`thumb_url`) | `url_for(file.representation(resize_to_fill: [250, nil]))` | message attachment thumbnail |
| `app/models/attachment.rb:121` (`inline_audio_url`) | `url_for(file)` | `<audio>` player |
| `app/models/attachment.rb:63-64` (`download_url`) | `blob.url` directly, after setting `ActiveStorage::Current.url_options` from `Rails.application.routes.default_url_options` | external providers, where a 302 does not survive |
| `app/models/concerns/avatarable.rb:16` | `url_for(avatar.representation(resize_to_fill: [250, nil]))` | avatars everywhere, **including the public portal** |
| `app/models/portal.rb:110,112` | `url_for(logo)` and `logo.blob.signed_id` | portal logo payload |
| `app/controllers/api/v1/accounts/upload_controller.rb:48` | `url_for(file_blob)` + `file_blob.signed_id` | **the help-center article image path** — see §1.7 |
| `app/jobs/account/contacts_export_job.rb:97` | `rails_blob_url(@account.contacts_export)` | emailed CSV export link |
| `app/mailers/administrator_notifications/account_notification_mailer.rb:30` | `rails_blob_url(resource.failed_records)` | emailed import-failure CSV |
| `app/mailboxes/mailbox_helper.rb:89` | `url_helpers.url_for(blob)` | inbound-email attachment, written into message text |
| `administrate-field-active_storage-1.0.3/lib/administrate/field/active_storage.rb:62,66,70,74` | `rails_representation_path(..., only_path: true)` and `rails_blob_path(..., only_path: true)` | Super Admin forms |

**`rails_blob_path` in `custom/`: there are none, deliberately.** The only matches in `custom/` are two
prohibitions, both written as headers:

> *"A blob on this surface is reached only through here: never a `rails_blob_path`, never a signed id rendered
> into a page. Blob URLs do not expire in this installation, so a leaked signed id would be a permanent one."*
> — `custom/app/controllers/super_admin/platform_support_controller.rb:59-61`

> *"Every other blob in this installation is served by ActiveStorage's own signed-id redirect, which performs no
> policy check at all, and blob URLs here never expire … A signed blob URL is therefore a permanent bearer
> token."*
> — `custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:3-10`

The ban is enforced by a spec, not only by a comment: `spec/requests/platform_support/security/attachments_spec.rb:205-214`
strips comments from every Platform Support view and mailer template and asserts no file emits
`rails_blob|rails_storage_proxy|signed_id|service_url`; `:218-227` asserts exactly two routes reach a Platform
Support blob. **So the house pattern in `custom/` is the opposite of `rails_blob_path`: an authorized controller
action that streams.** Any documentation-media design must state explicitly which of the two patterns it is
choosing and why, because the repository already has a precedent for each.

### 1.6 Direct uploads: the bare route is blocked, two scoped subclasses remain

`config/initializers/active_storage.rb:47-63` adds `ActiveStorageBareDirectUploadGuard`, a `before_action` that
answers `403` when `instance_of?(ActiveStorage::DirectUploadsController)` — i.e. the bare
`POST /rails/active_storage/direct_uploads`. Subclasses `super` through it and are exempt by the `instance_of?`
check. The stated reason: *"leaving it open allows anonymous blob creation"* (`:48-50`). Wired in
`to_prepare` at `:71-73`; proven by `spec/requests/active_storage/direct_uploads_spec.rb:18-26`, which asserts
`403` **and** no change to `ActiveStorage::Blob.count`.

Two authenticated subclasses remain:

| Route | Controller | Gate |
|---|---|---|
| `POST /api/v1/accounts/:account_id/conversations/:conversation_id/direct_uploads` (`config/routes.rb:129`) | `app/controllers/api/v1/accounts/conversations/direct_uploads_controller.rb` | devise-token or access token, `current_account`, `api_and_webhooks_enabled?`, conversation must resolve (`:10-21,29-37`) |
| `POST /api/v1/widget/direct_uploads` (`config/routes.rb:381`) | `app/controllers/api/v1/widget/direct_uploads_controller.rb` | website token + contact must resolve (`:3-11`) |

Direct upload is **off by default**: `DIRECT_UPLOADS_ENABLED` is `false` in `config/installation_config.yml:99-103`,
blank in `.env.example:300`, and exposed to the frontend by `app/controllers/dashboard_controller.rb:24` and
`app/controllers/widgets_controller.rb:21`. `MAXIMUM_FILE_UPLOAD_SIZE` is `40` MB
(`config/installation_config.yml:104-108`).

Two further local patches:

- `ActiveStorageDirectUploadMetadataFilter` (`:15-25`) strips `identified`, `analyzed` and `composed` from
  client-supplied blob metadata, so a client cannot assert that its upload was already analysed and skip
  server-side content-type identification.
- `ActiveStorageProxyRangeLimit` (`:27-45`), prepended into `ActiveStorage::Streaming` at `:75`, rejects a
  `Range` header asking for more than one range or more than 100 MB with `416`. It applies to **every** consumer
  of `ActiveStorage::Streaming` — the two proxy controllers and both Platform Support download actions.

### 1.7 The ten attachment surfaces, and how each authorizes a read

`has_one_attached` / `has_many_attached`, exhaustively:

| # | Surface | Declaration | How a read is authorized |
|---|---|---|---|
| 1 | message attachment | `app/models/attachment.rb:43` (`file`) | **Nothing.** `file_url` is `url_for(file)` (`:58`) — a permanent public redirect URL, serialized to the dashboard and the widget |
| 2 | avatars (User, Contact, AgentBot, Account, Inbox, …) | `app/models/concerns/avatarable.rb:10` | **Nothing.** `avatar_url` (`:16`) is a permanent public representation URL, rendered into the **public portal** at `app/views/public/api/v1/portals/documentation_layout/_user_avatar.html.erb:15` |
| 3 | portal logo | `app/models/portal.rb:50` | **Nothing.** `url_for(portal.logo)` is rendered into the public documentation topbar at `app/views/public/api/v1/portals/documentation_layout/_topbar.html.erb:12` |
| 4 | automation-rule files | `app/models/automation_rule.rb:32` | account-scoped controller; blobs arrive as signed ids (`spec/controllers/api/v1/accounts/automation_rules_controller_spec.rb:165`) |
| 5 | macro files | `app/models/macro.rb:27` | same |
| 6 | contact-import CSV | `app/models/data_import.rb:64` (`import_file`) | **the strongest existing pattern** — see below |
| 7 | import failed-records CSV | `app/models/data_import.rb:65` | `rails_blob_url` emailed to the admin (`account_notification_mailer.rb:30`) — a permanent public URL in an email |
| 8 | contacts export CSV | `app/models/account.rb:108` | `rails_blob_url` emailed (`contacts_export_job.rb:97`) — same |
| 9 | Platform Support **message** files | `custom/app/models/platform_support/message.rb:39` | **authorized controller, no URL ever emitted** — see below |
| 10 | Platform Support **internal note** files | `custom/app/models/platform_support/internal_note.rb:26` | staff-only authorized controller; 404s on the tenant route as a structural consequence |

**`Article` is not in this list.** There is no attachment on `Article`, `Category` or anything documentation-owned
other than the `Portal#logo` the Help Center already had. The charter's §9.8 — *"No media story at all. Not a weak
implementation — an absent one"* (`docs/documentation-v2/01-current-system.md`, §9 item 8) — is confirmed at the
model level. Independently: **zero** corpus files contain Markdown image syntax or an `<img>` tag
(`rg -l '!\[' custom/db/documentation/` → 0 files; same for `<img`). The prior programme recorded that as
deliberate (`docs/global-documentation/FINAL-CHECKPOINT.md:27,83` item 77(a): *"No screenshots … adding them
means owning their staleness"*).

**Surface 6 — the contact-import CSV — is the one surface that does scoped, expiring signed ids**, and it is the
pattern to copy where a signed id is genuinely the right answer
(`app/controllers/concerns/contact_import_file.rb`):

- `BLOB_TTL = 1.hour`, with the reason in the comment: *"short enough that a signed id copied out of a response
  is not a key to that file for ever"* (`:15-17`)
- `import_blob_signed_id` → `import_blob&.signed_id(expires_in: BLOB_TTL)` (`:39-41`) — **the only
  `expires_in:` on a signed id anywhere in the repository**
- the blob is stamped at creation with `metadata: { 'contact_import_account_id' => Current.account.id }`
  (`:20,76-81`) and `stored_blob` refuses any blob whose stamp does not match the caller's account (`:63-71`),
  with the reason stated: *"the upload endpoint hands them out for every attachment in the product, so what
  arrives here is not necessarily a CSV this account's import dialog stored"*

**Surfaces 9 and 10 — Platform Support — are the only authorized blob reads in the repository**, and both were
built precisely because of the expiry fact in §1.5:

- tenant: `custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:48-67`. One relation
  — `ActiveStorage::Attachment.where(name: 'platform_support_message_files', record_type:
  'PlatformSupport::Message', record_id: readable_message_ids)` — where `readable_message_ids` narrows through
  `PlatformSupport::TicketPolicy::Scope`. Then `send_blob_stream(attachment.blob)` with **no disposition
  argument**, so `Blob#forced_disposition_for_serving` decides: a `text/html` upload downloads, the allowed
  image/PDF/audio types display (`:30-35`). Every miss is an identical `404`, never `403` (`:25-28`).
- staff: `custom/app/controllers/super_admin/platform_support_controller.rb:63-69`. `find_by(id:, name:
  ATTACHMENT_NAMES, record_type: ATTACHMENT_PARENT_TYPES)`, so the route cannot be turned into a reader for
  another subsystem's blobs (`:32-35`), then
  `send_blob_stream(record.blob, disposition: ActiveStorage.content_types_allowed_inline.include?(...) ? 'inline' : 'attachment')`.
- write side: `custom/app/controllers/api/v1/accounts/platform_support/base_controller.rb:62-90` takes signed
  ids in and checks **type and size before anything is written** — `ALLOWED_CONTENT_TYPES = png, jpeg, gif,
  webp, pdf, text/plain, text/csv`, `MAX_FILE_BYTES = 10.megabytes`, `MAX_FILES = 5`
  (`custom/app/models/platform_support/message.rb:32-34`), each refusal naming the limit or the accepted types.

### 1.8 The existing article-image path — which is the thing to assess, not to invent

A Help Center article image today works like this, end to end:

1. `FullEditor.vue` (`app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue`) gates the picker,
   drop and paste on `ALLOWED_IMAGE_TYPES = png, jpeg, jpg, gif, webp` (`:43-49`) and
   `MAXIMUM_FILE_UPLOAD_SIZE = 4` MB (`:40`) — **both client-side only**.
2. `uploadFileToStorage` → `$store.dispatch('articles/attachImage', ...)` (`:426-433`).
3. `attachImage` → `uploadFile(file, ...)` returning `fileUrl`
   (`app/javascript/dashboard/store/modules/helpCenterArticles/actions.js:164-167`).
4. `uploadFile` → `POST /api/v1/accounts/:account_id/upload` with the file as `attachment`
   (`app/javascript/dashboard/helper/uploadHelper.js:27-55`); `uploadExternalImage` posts an `external_url`
   instead (`:65-81`).
5. `Api::V1::Accounts::UploadController#create` → `ActiveStorage::Blob.create_and_upload!(io:, filename:,
   content_type:)` (`:39-45`) and renders `{ file_url: url_for(file_blob), blob_id: file_blob.signed_id }`
   (`:47-49`). Route: `config/routes.rb:348`.
6. The editor writes `![alt](<file_url>)` into `articles.content`, optionally with `?cw_image_width=NNNpx`
   from the drag-resize view.
7. On render, `CustomMarkdownRenderer#image` (`lib/custom_markdown_renderer.rb:61-72`) emits the `<img>`.

Five properties of that path matter for §4:

- **The blob is never attached to anything.** `create_and_upload!` with no `attach` — so it is an orphan
  `ActiveStorage::Blob` with no `record`, no owner, and no account scope. `ActiveStorage::Blob.unattached` is
  never called anywhere in the repository (`rg 'unattached'` over `app lib custom` → nothing), and there is no
  purge job: every `.purge` call site is an avatar or a portal logo being replaced
  (`super_admin/users_controller.rb:51`, `agent_bots_controller.rb:47`,
  `api/v1/accounts/portals_controller.rb:49`, and three others). **Orphan article-image blobs accumulate
  forever.** That is tolerable at 124 articles with zero images; it is a storage-growth decision at corpus
  scale.
- **`create_from_file` validates nothing.** No content type check, no size check (`upload_controller.rb:16-19`).
  The 4 MB and the five image types are enforced only in Vue. The `external_url` branch does go through
  `SafeFetch`, which has size and content-type errors (`:21-37`). This is agent 082/083/084 territory; it is
  listed here because it is the endpoint any documentation-media feature would be tempted to reuse.
- **It is account-scoped by authentication.** `Api::V1::Accounts::BaseController` requires an account
  membership. **A Super Admin documentation author is not an account user, so there is no upload endpoint they
  can call.** This is the single concrete missing piece, and it is the one the prior programme already named:
  *"In-editor image upload | needs the Vue editor mounted in an Administrate form"*
  (`docs/global-documentation/07-super-admin-management.md:113`), with the workaround
  *"covered by referencing an uploaded asset's URL"* (`:61-63`).
- **`file_url` embeds a signed id.** `ActiveStorage.verifier` is
  `app.message_verifier("ActiveStorage")` (`engine.rb:137-139`), keyed from `secret_key_base`, and the payload
  is the blob's **primary key**. See Finding F1 — this is the blocker.
- **The renderer already accepts base64.** `MarkdownRendererUrlSanitizer::SAFE_DATA_IMAGE_PATTERN` allows
  `data:image/(png|gif|jpeg|webp)` through (`lib/markdown_renderer_url_sanitizer.rb:4,14-19`), so an author can
  inline an image into Markdown today with no Active Storage at all. That works, and it is the worst option:
  no caching, no variant, ~33% size inflation inside `articles.content`, and a row the seeder rewrites on every
  run.

### 1.9 What `CustomMarkdownRenderer#image` actually emits

`lib/custom_markdown_renderer.rb:61-72`:

```ruby
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

- `src` passes `sanitized_href`, which blanks `javascript:`, `vbscript:`, `file:` and `data:` except safe
  `data:image/*` (`markdown_renderer_url_sanitizer.rb:3-4,14-19`). Any http(s) or root-relative URL passes
  unchanged.
- `alt` is always emitted and always escaped, but **may be empty**. There is no alt-text requirement anywhere.
- `?cw_image_width=NNNpx` becomes an inline `style`, clamped to 1–2000 px
  (`:130-132` → `extract_px_param` at `:141-147`). The same convention is implemented for messages in
  `lib/base_markdown_renderer.rb:4,20-25` and client-side in
  `app/javascript/shared/helpers/MessageFormatter.js:9,30`.
- **No `width`/`height` attributes, no `loading`, no `decoding`, no `srcset`.** `height: auto` without an
  intrinsic aspect ratio means every image in a documentation article is a layout shift, and every image loads
  eagerly. The body wrapper is Tailwind `prose` (`app/views/public/api/v1/portals/articles/_content.html.erb:6-18`),
  which styles `img` but supplies no dimensions either.

---

## 2. Constraints the existing system imposes

An editor or media upgrade must not break these. Each is a fact, not a preference.

| # | Constraint | Source |
|---|---|---|
| C1 | **A signed id is environment-specific.** It is `message_verifier("ActiveStorage")` over the blob's primary key, keyed from `secret_key_base`. The same string in two installations names a different blob or no blob. | `engine.rb:137-139` |
| C2 | **A signed id never expires** unless `expires_in:` is passed at the call site. `urls_expire_in` is nil. | `engine.rb:120` |
| C3 | **Every built-in Active Storage route is unauthenticated.** Anyone holding the URL reads the bytes. | `base_controller.rb:1-10`, `set_blob.rb:11-19` |
| C4 | **SVG cannot be served inline.** Forced to `application/octet-stream` + `attachment`. | `engine.rb:55-65`, `blob.rb:375-382` |
| C5 | **A variant of a WebP/AVIF blob becomes PNG.** `web_image_content_types` is png/jpeg/gif on `load_defaults 7.0`. | `engine.rb:49-53`, `representable.rb:180-190` |
| C6 | **Non-images have no representation.** `previewers = []`, so `representation` raises `UnrepresentableError` rather than previewing. | `config/application.rb:71`, `representable.rb:138,151-160` |
| C7 | **Variant generation requires libvips ≥ 8.13 on the host**, or Rails does not boot at all. Stage 4b is the gate; the system package is not the deploy's to install. | `deploy.sh:247-263`, `vips.rb:33-40` |
| C8 | **The content seeder overwrites `content`, `title`, `description`, `category`, `position`, `meta` and `status` from the file on every run, in no transaction, and deletes nothing.** Any media reference that lives only in the database is lost or orphaned by the next `rails documentation:content`. | `docs/documentation-v2/01-current-system.md` §3 |
| C9 | **`custom/` forbids `rails_blob_path`, signed ids in views and `service_url`, enforced by spec** on every Platform Support view. A documentation feature in `custom/` that emits blob URLs must say why it is not that surface. | `platform_support_controller.rb:59-61`, `attachments_controller.rb:3-10`, `spec/requests/platform_support/security/attachments_spec.rb:205-214` |
| C10 | **The bare direct-upload route is `403`, asserted by spec.** A new upload surface must be a subclass of `ActiveStorage::DirectUploadsController` or a plain controller, never a re-opening of the bare route. | `config/initializers/active_storage.rb:47-63`, `spec/requests/active_storage/direct_uploads_spec.rb:18-26` |
| C11 | **Production storage is local disk on one host, in a `.gitignore`d directory, outside every documented backup.** Media added to it is media that a database-only restore loses. | `production.rb:43`, `storage.yml:5-7`, `.gitignore:59`, `docs/p7/00-discovery-findings.md:801` |
| C12 | **Staging has no Active Storage service configured at all.** | `config/environments/staging.rb` |
| C13 | **No CDN and no static/cache layer in front of Rails.** One nginx `location /` proxying to Puma. | `deployment/nginx_chatwoot.conf:33-50` |
| C14 | **The raw-Markdown export route serves `articles.content` verbatim.** Any non-URL media reference syntax appears unresolved to that consumer. | `app/controllers/public/api/v1/portals/articles_controller.rb:29-33` |
| C15 | **`/rails/active_storage` is not disallowed in `robots.txt`**, so blob URLs are crawlable — but the path carries an opaque signed id, not a descriptive filename segment ahead of `*filename`. | `app/controllers/robots_controller.rb:17-28` |

---

## 3. Findings

**F1 — blocker. An Active Storage signed-id URL cannot be written into the file-canonical Markdown corpus.**
The corpus is Markdown in git, seeded into many environments (`custom/db/documentation/**`, charter §2). A
`file_url` from `upload_controller.rb:48` is `/rails/active_storage/blobs/redirect/<signed_id>/<filename>`, and
`<signed_id>` is `message_verifier("ActiveStorage")` over the blob's **primary key**, keyed from
`secret_key_base` (`engine.rb:137-139`). Commit that URL into a `.md` file and it is valid in exactly one
database with exactly one `secret_key_base`. In staging, in a fresh install, after a restore from a different
dump, or after a blob-table reload, the same Markdown yields `404` or — worse, if ids happen to collide — a
*different* image. This is the central reason the existing help-center image path (§1.8) cannot simply be
pointed at the documentation corpus, and it must be decided before anything is built. Owner: Agent 000,
charter §8 decision 3, and it interacts with decision 1.

**F2 — major. `Article` has no attachment and the corpus has no images.** Zero `has_one_attached` /
`has_many_attached` on `Article` (§1.7); zero `![` and zero `<img` across all 126 corpus files. The media story
is absent, not weak, exactly as `01-current-system.md` §9.8 states. Everything in §4 is net-new surface.

**F3 — major. The redirect family is the wrong serving route for a public documentation portal, and it is the
only one in use.** `resolve_model_to_route` is unset, so `url_for(blob)` is the redirect route: `302` with
`Cache-Control: max-age=300, private`, then a second Rails request to `DiskController` with no long cache
(`blobs/redirect_controller.rb:13`, `disk_controller.rb:28-38`). Two Rails requests per image per reader per
five minutes, uncacheable by browser or CDN, with no CDN in front (C13). The proxy family answers `200` with
`Cache-Control: max-age=3153600000, public` and an ETag (`blobs/proxy_controller.rb:18`). For a screenshot-heavy
corpus this is the difference between one cached fetch and an unbounded stream of origin hits. **The fix is
per-call `rails_storage_proxy_path`, not flipping `resolve_model_to_route` globally** — that global would move
every avatar, message attachment and audio URL in the product onto the proxy at once, which is a product-wide
change nobody asked for.

**F4 — major. There is no upload endpoint a Super Admin documentation author can call.**
`POST /api/v1/accounts/:account_id/upload` is behind `Api::V1::Accounts::BaseController` and requires an account
membership; `SuperAdmin` is an STI subclass of `User` with no account. The existing article editor's whole image
path (§1.8) is therefore unreachable from `/super_admin/articles`. The prior programme recorded this as deferred
rather than solved (`docs/global-documentation/07-super-admin-management.md:61-63,113`).

**F5 — major. `Api::V1::Accounts::UploadController#create_from_file` validates neither content type nor size.**
`upload_controller.rb:16-19` → `create_and_upload!` with the client's own `original_filename` and
`content_type`. The 4 MB cap and the five-type allowlist exist only in `FullEditor.vue:40,43-49`. The same
endpoint also mints an orphan blob with a permanent public URL. Any documentation-media endpoint must do what
`platform_support/base_controller.rb:62-90` does — type and size checked before the write, each refusal naming
the limit — and must not reuse this one as-is.

**F6 — major. Orphan blobs are never reclaimed.** The article-image path attaches the blob to nothing
(§1.8), `ActiveStorage::Blob.unattached` is never called, and there is no purge job. At 124 image-free articles
this is invisible; at a corpus several times larger with screenshots, every replaced or deleted image leaves its
bytes on a local disk that no backup covers (C11). Attaching documentation media to a record — any record —
converts this from an unbounded leak into `dependent:`-managed lifecycle.

**F7 — major. SVG is unusable through Active Storage, and that is a security feature, not a bug.**
`image/svg+xml` sits in `content_types_to_serve_as_binary` (`engine.rb:55-65`) and nothing overrides it, so
`service_metadata` forces `application/octet-stream` + `attachment` (`blob.rb:375-382`). Documentation diagrams
must be raster, or inline SVG in the article HTML — and inline SVG lands squarely in the unresolved
sanitization question (`01-current-system.md` §5: *"No `sanitize` call appears in that path"*), owned by agents
065/081/084. **Do not relax `content_types_to_serve_as_binary` to get SVG diagrams.** That list is what
`docs/p7/00b-discovery-informational.md:539` credits with closing stored-XSS from uploads on an installation
whose blobs are served from the app's own origin.

**F8 — major. Variants of WebP and AVIF are transcoded to PNG.** `web_image_content_types` is png/jpeg/gif
under `load_defaults 7.0` (`engine.rb:49-53`; the `"7.2"` defaults block that adds webp is not reached), and
`default_variant_format` returns `:png` for anything not in that list (`representable.rb:180-190`). A WebP
screenshot that variants to PNG typically grows several-fold — the opposite of the intent. Either serve
originals at their natural size, or set `config.active_storage.web_image_content_types` explicitly before
relying on variants. Note this would also change avatar and message-thumbnail output
(`avatarable.rb:16`, `attachment.rb:71`), so it is not a documentation-local change.

**F9 — minor, but it is the public-portal precedent.** The documentation portal **already serves Active Storage
images to anonymous readers**: `url_for(portal.logo)` in
`app/views/public/api/v1/portals/documentation_layout/_topbar.html.erb:12` and `user.avatar_url` in
`.../_user_avatar.html.erb:15`. So "a permanent public blob URL on the public docs portal" is not a new
exposure class — for content that is public by definition it is the established pattern. What is new at corpus
scale is the volume (F3) and the environment-portability problem (F1).

**F10 — minor. The `<img>` the renderer emits is not production-grade for a documentation portal.** No
`width`/`height`, no `loading="lazy"`, no `decoding="async"`, no `srcset`, and `alt` may be empty
(`lib/custom_markdown_renderer.rb:61-72`). Blob metadata already holds `width` and `height` once the analyzer
has run — `attachment.rb:129-130` reads `file.metadata[:width]` / `[:height]` for exactly this purpose — so the
dimensions are available to whatever resolves a media reference. Hand this to agents 068 and 080.

**F11 — minor. `config/sidekiq.yml:31-32` lists `active_storage_analysis` and `active_storage_purge`, which
nothing feeds.** `load_defaults 7.0` runs the `"6.1"` defaults block, which sets
`active_storage.queues.analysis = nil` and `queues.purge = nil`, overriding the `"6.0"` assignment. With a nil
queue, `ActiveStorage::AnalyzeJob` (`app/jobs/active_storage/analyze_job.rb:5`, `queue_as { ActiveStorage.queues[:analysis] }`)
runs on `default`, which **is** in the queue list (`config/sidekiq.yml:21`). So analysis does happen — width and
height do get extracted — but the two named queues are dead entries, and an operator reading the file would
believe analysis is isolated when it is competing with everything else on `default`. Worth a line in the final
report; not a blocker.

**F12 — unverified, and it needs an operator, not an agent.** (a) The production value of
`ACTIVE_STORAGE_SERVICE`. The repository default is `local` (`production.rb:43`, `.env.example:143`) and a prior
pass concluded local disk (`docs/p7/00-discovery-findings.md:801`), but the authoritative source is the
production `.env`. (b) The libvips version on the production host (§1.3). Both are a single line of operator
output each; §1.3 names the command the deploy already runs. Until (a) is known, any media sizing estimate is
provisional, because local disk on one un-backed-up host and an S3 bucket are different propositions.

---

## 4. Options — how a documentation article image should be stored and served

### 4.1 The question, stated precisely

A documentation article image has four properties no existing surface has all of:

1. It is **public** — the portal is crawlable and unauthenticated. No authorization is needed on the read, which
   is why the Platform Support pattern (C9) is the wrong model here despite being the house pattern in `custom/`.
2. It belongs to an article whose **text is canonical in git** (charter §2, C8). Media that lives only in the
   database is overwritten, orphaned or lost by the next `rails documentation:content`.
3. It must survive being **seeded into a different environment** — staging, a fresh install, a restore. That is
   F1, and it is what rules out committing a signed-id URL.
4. It will be **fetched by many anonymous readers**, so caching is a product requirement, not a nicety (F3, C13).

### 4.2 The four real options

**Option A — commit the image URL (status quo mechanism, extended to Super Admin).** Add a platform-scoped
upload endpoint (F4), have the author paste the returned `file_url` into the Markdown, commit the Markdown.
*For*: nothing new to build beyond the endpoint; reuses `upload_controller.rb` exactly. *Against*: **fails F1
outright** — the committed URL is valid in one database only. Also inherits F3 (redirect route), F5 (no
validation), F6 (orphan blob). **Reject.** It is worth naming because it is what
`docs/global-documentation/07-super-admin-management.md:61-63` recommends as the current workaround, and that
recommendation does not survive the corpus becoming multi-environment.

**Option B — images as repository files served statically from `public/`.** Drop the images into a
`public/`-rooted directory, reference them in Markdown by a stable root-relative path. *For*: environment-portable
by construction (F1 solved); `config.public_file_server.headers` already sets
`Cache-Control: public, max-age=31536000` in production (`production.rb:23-26`) with `RAILS_SERVE_STATIC_FILES`
defaulting true, so F3 is solved with no code; no blob rows, no orphans (F6 solved); no vips dependency on the
request path (C7 irrelevant). *Against*: it **routes around the charter's own "Media → ActiveStorage" row**
(charter §2) and would need that row amended rather than ignored; no variants or responsive sizes; `public/` is
not where this repository keeps content; and it puts binaries in git with no deduplication. **Viable, and
honestly the cheapest correct answer — but it needs Agent 000 to amend the charter table, not an agent to
assume it.**

**Option C — images as blobs attached to the `Article`, authored in Super Admin, DB-canonical.** Add
`has_many_attached` to `Article`, upload through a new Super Admin endpoint, reference by attachment name.
*For*: real ownership, so `dependent:` lifecycle solves F6; variants available; fits the charter table. *Against*:
**puts media on the one record the content seeder rewrites wholesale on every run** (C8). The seeder would have
to learn not to touch attachments, and a Markdown file that cannot name its own images means the repo is no
longer the source of truth for an article's content — which collides head-on with charter §8 decision 1. **Reject
as the primary model**; keep it as the operator convenience in option D's second half.

**Option D — recommended. Repository-canonical media files, seeded into Active Storage, referenced by a stable
key, served through the proxy route.**

1. **Store the bytes in the repository**, beside the Markdown they belong to — e.g.
   `custom/db/documentation/media/<section>/<key>/<name>.png`. The repository stays the source of truth
   (charter §8 decision 1 unchanged), and a reviewer sees an image change in a diff.
2. **Reference them in Markdown by a stable, environment-independent key**, not a URL — e.g.
   `![Connecting a WhatsApp number](media:whatsapp/connect-number/step-2.png)`. The same file seeds identically
   into any environment (F1 solved). The key is also what makes a missing image a *detectable* error at seed
   time rather than a silent `404` for a reader.
3. **Have the existing `Documentation::ContentSeeder` upload each media file as an Active Storage blob,
   idempotently by checksum, attached to the platform `Portal`** (which already carries `has_one_attached :logo`,
   `app/models/portal.rb:50`, and which `Documentation::PortalSeeder` deliberately does *not* overwrite —
   `01-current-system.md` §3). Attaching to the `Portal` rather than the `Article` means re-seeding an article
   never detaches its media, and `dependent:` lifecycle answers F6. The checksum column Active Storage already
   has makes the upload a no-op on an unchanged file, so the seeder stays idempotent as its own header promises.
4. **Resolve the key to a URL at render time**, in the article render path, to
   `rails_storage_proxy_path(blob)` — `200`, `Cache-Control: public, max-age≈100 years`, one Rails request ever
   (F3 solved, `blobs/proxy_controller.rb:18`). Per-call, **not** by setting `resolve_model_to_route` globally.
   At the same point, emit `width`/`height` from `blob.metadata` and `loading="lazy"`/`decoding="async"`, which
   is where F10 gets fixed; `attachment.rb:129-130` is the precedent for reading those metadata keys.
5. **Enforce at the seed boundary** — the earliest shared entry point, per the repo's own guideline: content type
   in `{png, jpeg, gif, webp}` (webp allowed because the *original* serves inline, `engine.rb:67-78`; see the
   variant caveat below), a size cap, and **alt text required**. A `media:` reference with an empty alt should
   fail the seed, not render an inaccessible image. This mirrors
   `platform_support/base_controller.rb:62-90` — refuse before the write, and name the limit in the refusal.
6. **Raster only.** No SVG (F7, C4). A diagram that must be vector is either rendered to PNG at authoring time
   or is inline SVG in the article body — and the latter is blocked behind the unresolved sanitization question
   and belongs to agents 065/081/084, not here.
7. **Serve originals at natural size; do not rely on variants yet.** F8 means a WebP variant becomes a larger
   PNG, and C7 means variant generation is the thing that gates the whole deploy on a system package. If
   responsive sizes are later wanted, the prerequisite is setting
   `config.active_storage.web_image_content_types` explicitly — and that is a product-wide change affecting
   avatars and message thumbnails, so it is Agent 000's call, not a documentation-local one.
8. **Operator-uploaded media, if wanted, layers on later into the same key namespace.** A Super Admin upload
   endpoint (F4) that writes into the same `media:` keys, with the same validations, so the seeder and the
   operator are not two writers of the same thing — charter §8 decision 1's rule, applied to media.

### 4.3 Already available versus must be added

**Already available, no work:**

| Capability | Where |
|---|---|
| Active Storage installed, migrated, three tables with the uniqueness indexes | `db/schema.rb:89-115` |
| Six storage services pre-wired; switching to S3/GCS/Azure/S3-compatible is ENV only | `config/storage.yml` |
| vips variant processor, `image_processing` + `ruby-vips 2.3.0` installed | `config/application.rb:39`, `Gemfile.lock:440-442,843` |
| libvips floor enforced before any schema change, with a named remedy | `deployment/deploy.sh:247-263` |
| Proxy routes with a 100-year public cache, already mounted | `activestorage/config/routes.rb:6,10`, `blobs/proxy_controller.rb:18` |
| Signed representation keys — transformations cannot be injected | `variation.rb:41-43`, `representations/base_controller.rb:13-17` |
| SVG/HTML/XML forced to `octet-stream` + `attachment` | `engine.rb:55-65`, `blob.rb:375-382` |
| Bare direct-upload route blocked, asserted by spec | `config/initializers/active_storage.rb:47-63`, `spec/requests/active_storage/direct_uploads_spec.rb:18-26` |
| Range-request abuse capped at 1 range / 100 MB on every streaming path | `config/initializers/active_storage.rb:27-45,75` |
| Client metadata-spoofing filter on direct uploads | `config/initializers/active_storage.rb:15-25,67-69` |
| `Portal#logo` attachment + public rendering on the documentation layout | `app/models/portal.rb:50`, `documentation_layout/_topbar.html.erb:12` |
| Markdown `image` renderer with `src` sanitization and a width convention | `lib/custom_markdown_renderer.rb:61-72`, `lib/markdown_renderer_url_sanitizer.rb` |
| `prose` typography on the article body | `app/views/public/api/v1/portals/articles/_content.html.erb:6-18` |
| Width/height in blob metadata once analysed | `app/models/attachment.rb:129-130` |
| `administrate-field-active_storage` already a dependency, already used on two dashboards | `Gemfile:98`, `app/dashboards/user_dashboard.rb:14`, `app/dashboards/agent_bot_dashboard.rb:13` |
| A scoped, expiring, account-stamped signed-id pattern to copy where one is genuinely needed | `app/controllers/concerns/contact_import_file.rb:15-20,39-41,63-81` |
| A validate-before-write pattern to copy | `custom/.../platform_support/base_controller.rb:62-90` |
| An authorized-blob-download pattern to copy if a *private* media surface ever appears | `custom/.../platform_support/attachments_controller.rb:48-67` |
| `/rails/active_storage` crawlable — not disallowed in robots.txt | `app/controllers/robots_controller.rb:17-28` |

**Must be added:**

| # | Thing | Why |
|---|---|---|
| 1 | A media directory in the corpus, and manifest/front-matter rules for it | F2 — there is nothing today |
| 2 | A stable `media:` reference syntax, and its resolver in the article render path | F1 — a committed signed-id URL is environment-bound |
| 3 | Media seeding inside `Documentation::ContentSeeder`, idempotent by checksum | C8 — the seeder is the only writer the corpus has |
| 4 | A `has_many_attached` media association on the platform `Portal` | F6 — ownership is what makes lifecycle possible |
| 5 | Proxy-route URL generation at the resolver, per-call | F3 — the redirect route is uncacheable |
| 6 | `width`/`height`/`loading`/`decoding` on the emitted `<img>` | F10 — CLS and eager loading on a public portal |
| 7 | Required alt text, enforced at seed time | F10, accessibility; agent 072's area for RTL |
| 8 | Content-type and size validation at the seed boundary | F5 — the existing upload endpoint validates nothing |
| 9 | A platform-scoped Super Admin upload endpoint — **only if** operator-uploaded media is wanted | F4 — Super Admin cannot reach the account-scoped one |
| 10 | A decision on `web_image_content_types` — **only if** variants are wanted | F8 — product-wide, Agent 000's call |
| 11 | Staging's `active_storage.service` | C12 — attachments cannot work in staging at all |
| 12 | Backup coverage for `storage/`, or a move to S3 | C11 — media on an un-backed-up local disk |

---

## 5. Risks

| # | Risk | Severity | Mitigation / owner |
|---|---|---|---|
| R1 | **Production storage is local disk on one host, in a `.gitignore`d directory, covered by no documented backup.** Adding a screenshot corpus multiplies what is lost on a host rebuild or a database-only restore. | blocker for a media-heavy corpus | C11, F12(a). Either confirm S3 is in force, or move to it (ENV only — `storage.yml:10-16,33-40`), or add `storage/` to the backup. Agent 000 + operator |
| R2 | **An old libvips makes `require "active_storage"` raise, aborting every Rails process.** Any feature that newly depends on variants makes the whole product's boot depend on a system package the deploy cannot install. | blocker if variants are adopted | C7, F12(b). Option D step 7 avoids variants for now. `deploy.sh:247-263` already gates it; keep that gate |
| R3 | **A committed signed-id URL silently becomes the wrong image, not a visible error**, if blob ids happen to line up across environments. | blocker | F1. Option D steps 2–4. Never commit a signed id. This is a contract item, not a convention |
| R4 | **Relaxing `content_types_to_serve_as_binary` to get SVG diagrams would reopen stored XSS** against the app origin, because blobs are served from the app's own origin on a local-disk install. | blocker if attempted | F7, C4. Explicitly out of scope. Hand the "inline SVG in article HTML" question to agents 065/081/084 — it is a sanitizer question, not a storage one |
| R5 | **Orphan blobs with permanent public URLs accumulate with no reclamation path.** | major | F6. Attaching to the `Portal` (option D step 3) plus `dependent:`. Separately, the existing orphans from the help-center editor path are a cleanup item nobody owns |
| R6 | **The redirect route at corpus scale is an origin-load problem with no CDN in front.** A 20-image article is 40 Rails requests per cold reader, repeated every five minutes. | major | F3, C13. Option D step 4. Do **not** fix it by flipping `resolve_model_to_route` globally |
| R7 | **Two writers of the same media** — the seeder and a Super Admin uploader — would overwrite each other exactly as the content seeder already overwrites operator article edits. | major | C8. Option D step 8: one key namespace, one writer, the rule stated before the uploader is built. Charter §8 decision 1 |
| R8 | **`administrate-field-active_storage` emits `rails_blob_path`** (`active_storage.rb:62,66,70,74`). Mounting it on the article form to get a file picker would put permanent signed-id URLs into the Super Admin HTML — tolerable there, but it is the habit C9 exists to prevent, and it would then be one copy-paste away from a public view. | minor | Use it for the *form* if convenient; never let its URL output reach a public template or the corpus |
| R9 | **Images referenced by a `media:` key appear unresolved in the raw-Markdown export** (`hc/:slug/articles/:slug.md`). | minor | C14. Either resolve keys in `show_markdown` too, or document the export as source-form. Agent 000 to decide; name it in the contract either way |
| R10 | **Image SEO is weak even when the image is crawlable**: the URL's descriptive segment sits after an opaque signed id, the sitemap has no `image:image` entries (`app/views/public/api/v1/portals/sitemap.xml.erb:13-26`), and `og:image` resolves to nothing unless `OG_IMAGE_CDN_URL` is configured (`app/helpers/portal_helper.rb:3-18`). | minor | C15, F9. Hand to agents 074, 075 and 080 |
| R11 | **Staging cannot serve any attachment**, so a media feature is untestable on the one environment an author would be asked to check. | minor, becomes major the moment anyone tries | C12. One line in `staging.rb` |
