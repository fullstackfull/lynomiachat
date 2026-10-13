---
agent: 083
scope: ActiveStorage authorization and blob exposure for documentation article media
confidence: high
---

Read against `claude/documentation-v2` at baseline `021ea6e3`. Framework citations are to the vendored gem the
`Gemfile.lock` pins (`activestorage (7.2.3.2)`, `Gemfile.lock:62,710`), because the behaviour in question is the
framework's and the repository overrides almost none of it.

I did not boot the application, run a request, or run a spec — §6.1 forbids it. Every HTTP status below is
derived by reading the controller, the concern and `rescue_responses`, and is marked as such. Where a spec
already proves a behaviour without a server I cite the spec instead, which is stronger than my inference.

---

## 1. Attack surface

### 1.1 The routes

ActiveStorage draws its own route table unconditionally — `ActiveStorage.draw_routes` defaults `true`
(`vendor/bundle/ruby/3.4.0/gems/activestorage-7.2.3.2/lib/active_storage.rb:357` region, `mattr_accessor
:draw_routes, default: true`) and `grep -rn "draw_routes\|routes_prefix" config/ app/ custom/ lib/` returns
**nothing**, so all six blob paths exist in this installation at the default `/rails/active_storage` prefix:

| Path | Controller | What it does |
|---|---|---|
| `GET /rails/active_storage/blobs/redirect/:signed_id/*filename` | `ActiveStorage::Blobs::RedirectController` | 302 to a service URL |
| `GET /rails/active_storage/blobs/proxy/:signed_id/*filename` | `ActiveStorage::Blobs::ProxyController` | streams the bytes |
| `GET /rails/active_storage/blobs/:signed_id/*filename` | redirect controller | legacy alias |
| `GET /rails/active_storage/representations/redirect/:signed_blob_id/:variation_key/*filename` | `Representations::RedirectController` | 302 to a variant |
| `GET /rails/active_storage/representations/proxy/…` | `Representations::ProxyController` | streams a variant |
| `GET /rails/active_storage/disk/:encoded_key/*filename` | `ActiveStorage::DiskController` | serves the file off disk |

Source: `vendor/bundle/ruby/3.4.0/gems/activestorage-7.2.3.2/config/routes.rb:5-13`.

The two `direct` helpers that application code actually calls are at the same file, `:33-57`
(`rails_storage_proxy`) and `:59-83` (`rails_storage_redirect`). `url_for(blob)` and `rails_blob_url(blob)` both
resolve through `ActiveStorage.resolve_model_to_route`, whose default is `:rails_storage_redirect`
(`lib/active_storage.rb:359`) and which **this repository never overrides** — `grep -rn
"resolve_model_to_route" config/ app/ custom/ lib/` finds only the two comments that say so
(`custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:5`) and one spec that stubs
it to prove the proxy route is selectable (`spec/models/attachment_spec.rb:262-266`).

### 1.2 Every blob this product holds

Eight attachment declarations, which is the whole inventory:

| # | Declaration | `file:line` | What it holds | Sensitivity |
|---|---|---|---|---|
| 1 | `Attachment#file` | `app/models/attachment.rb:43` | every conversation message attachment | customer conversations, documents, call recordings |
| 2 | `Avatarable#avatar` | `app/models/concerns/avatarable.rb:10` | user, contact, agent-bot, inbox avatars | low, but identity-linked |
| 3 | `Portal#logo` | `app/models/portal.rb:50` | help-centre / documentation portal logo | **intended to be public** |
| 4 | `DataImport#import_file` | `app/models/data_import.rb:64` | the uploaded contact-import CSV | bulk contact PII |
| 5 | `DataImport#failed_records` | `app/models/data_import.rb:65` | the rejected rows of an import | bulk contact PII |
| 6 | `Account#contacts_export` | `app/models/account.rb:108` | the whole contact database as CSV | bulk contact PII |
| 7 | `AutomationRule#files`, `Macro#files` | `app/models/automation_rule.rb:32`, `app/models/macro.rb:27` | files an automation sends | account content |
| 8 | `PlatformSupport::{Message,InternalNote}` files | `custom/app/models/platform_support/message.rb:39`, `internal_note.rb:26` | invoices, screenshots, log excerpts, staff-only notes | cross-tenant, staff-only for notes |

`Article` is **not** on that list. `grep -rn "has_one_attached\|has_many_attached" app/ custom/ enterprise/ lib/`
returns exactly the eight rows above, so there is no media attachment on the documentation content model today.
`01-current-system.md` §9.8 ("no media story at all — not a weak implementation, an absent one") is correct, and
I can add the corpus measurement: `grep -rno "!\[" custom/db/documentation/` returns **0** — zero images in 126
Markdown files — and `grep -rn "http" custom/db/documentation/` returns 14 hits, all of them prose about store
URLs, none an image or an asset. Nothing in the corpus references a blob.

### 1.3 The three places an unattached or foreign blob enters

- `app/controllers/api/v1/accounts/upload_controller.rb:39-49` — `ActiveStorage::Blob.create_and_upload!` with
  **no `record:`**, answering `{ file_url: url_for(file_blob), blob_id: file_blob.signed_id }`. Route
  `config/routes.rb:348`.
- `app/controllers/api/v1/accounts/portals_controller.rb:67-70` — `ActiveStorage::Blob.find_signed(params[:blob_id])`
  then `@portal.logo.attach(blob)`.
- `app/controllers/concerns/attachment_concern.rb:22-29` — the same `find_signed` then attach, for macros
  (`app/controllers/api/v1/accounts/macros_controller.rb:26,38`) and automation rules
  (`automation_rules_controller.rb:25,37`).

### 1.4 One more route that resolves blobs, outside ActiveStorage

`app/controllers/slack_uploads_controller.rb` — `GET /slack_uploads` (`config/routes.rb:36`), on
`ApplicationController`. See finding **F3**; this is the most surprising thing in the surface.

---

## 2. What the existing defence actually does

### 2.1 The blob routes: nothing. Quoted, not summarised.

The framework says so itself, in a comment on the controller this installation serves every blob from:

```ruby
# WARNING: All Active Storage controllers are publicly accessible by default. The
# generated URLs are hard to guess, but permanent by design. If your files
# require a higher level of protection consider implementing
# {Authenticated Controllers}[...].
class ActiveStorage::Blobs::RedirectController < ActiveStorage::BaseController
  include ActiveStorage::SetBlob

  def show
    expires_in ActiveStorage.service_urls_expire_in
    redirect_to @blob.url(disposition: params[:disposition]), allow_other_host: true
  end
end
```
(`…/activestorage-7.2.3.2/app/controllers/active_storage/blobs/redirect_controller.rb:5-16`)

The base class carries no authentication and no policy hook:

```ruby
class ActiveStorage::BaseController < ActionController::Base
  include ActiveStorage::SetCurrent

  protect_from_forgery with: :exception

  self.etag_with_template_digest = false
end
```
(`…/app/controllers/active_storage/base_controller.rb:4-10`) — `protect_from_forgery` governs non-GET verbs
only, and every blob route is a GET.

And the lookup is unscoped:

```ruby
def set_blob
  @blob = blob_scope.find_signed!(params[:signed_blob_id] || params[:signed_id])
rescue ActiveSupport::MessageVerifier::InvalidSignature
  head :not_found
end

def blob_scope
  ActiveStorage::Blob
end
```
(`…/app/controllers/concerns/active_storage/set_blob.rb:11-19`)

`blob_scope` is the bare class. **There is no override of it, or of any ActiveStorage controller, anywhere in
this repository**: `grep -rn "ActiveStorage::Blobs\|ActiveStorage::Representations\|ActiveStorage::DiskController\|ActiveStorage::BaseController" app/ custom/ lib/ config/`
returns nothing. The only ActiveStorage prepends in the installation are three unrelated ones —
a direct-upload metadata filter, a byte-range limit, and a block on the bare direct-upload route
(`config/initializers/active_storage.rb:15-25,27-46,52-64`, applied at `:66-76`). **None of them touches read
authorization.**

So the complete authorization predicate for a blob read in this installation is: *hold a valid HMAC signature
over this blob's integer primary key.* No session, no token, no account, no role, no parent record, no expiry.

### 2.2 `active_storage.urls_expire_in` — the actual value is its absence

The brief asks for the value or its absence. **It is absent, and I can show it three ways.**

1. The framework default is an unassigned accessor: `mattr_accessor :urls_expire_in`, with no `default:`, on
   `…/activestorage-7.2.3.2/lib/active_storage.rb:357` — compare the line above it,
   `mattr_accessor :service_urls_expire_in, default: 5.minutes`.
2. The engine copies the app config over it verbatim with no fallback —
   `ActiveStorage.urls_expire_in = app.config.active_storage.urls_expire_in`
   (`…/lib/active_storage/engine.rb:120`) — note the contrast with the line immediately above, which does
   `|| 5.minutes`.
3. No `load_defaults` block ever sets it: `grep -n "urls_expire_in" vendor/…/railties-7.2.3.2/lib/rails/application/configuration.rb`
   returns **nothing**, and this app is on `config.load_defaults 7.0` (`config/application.rb:39`) with no
   `new_framework_defaults` initializer present (`ls config/initializers/ | grep -i framework` is empty).

And the application never sets it: the only non-vendor hits for `urls_expire_in` in the whole tree are two
comments that state the finding (`custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:5`
and `app/views/super_admin/platform_support/_attachments.html.erb:4`).

Consequence, at `…/config/routes.rb:60`:

```ruby
direct :rails_storage_redirect do |model, options|
  expires_in = options.delete(:expires_in) { ActiveStorage.urls_expire_in }
```

`expires_in` is `nil`, which `signed_id` passes to the verifier as "no expiry". **Every signed blob ID this
product has ever emitted is valid forever.** The 5-minute number that does exist
(`service_urls_expire_in`) applies only to the *second* hop — the disk/S3 URL the redirect controller sends you
to — and is re-mintable on demand by replaying the first hop.

### 2.3 What an unauthenticated request to a blob URL returns

Derived from code, not executed. I state the mechanism so the claim is checkable rather than trusted:

| Request | Response | Mechanism |
|---|---|---|
| `GET /rails/active_storage/blobs/redirect/<valid signed_id>/<filename>`, no cookie, no token | **302** to the service URL, then **200** with the bytes | no auth in `BaseController`; `redirect_controller.rb:14` |
| …response caching on that 302 | `Cache-Control: max-age=300, private` | `expires_in ActiveStorage.service_urls_expire_in` with no `public: true` (`redirect_controller.rb:13`) |
| `GET …/blobs/proxy/<valid signed_id>/<filename>`, unauthenticated | **200** with the bytes, `Cache-Control: public, max-age=…` far future | `proxy_controller.rb:14-24`, `http_cache_forever public: true` |
| tampered or re-signed `signed_id` | **404**, empty body | `rescue ActiveSupport::MessageVerifier::InvalidSignature; head :not_found` (`set_blob.rb:13-14`) |
| valid signature whose blob row no longer exists | **404** | `find_signed!` → `find(id)` → `ActiveRecord::RecordNotFound` (`…/activerecord-7.2.3.2/lib/active_record/signed_id.rb:72-76`), mapped by `rescue_responses` |
| the disk URL more than 5 minutes later | **404**, empty body | `decode_verified_key` returns nil → `head :not_found` (`disk_controller.rb:12-17,48-51`) |
| rate limiting on any of the above | only the global `req/ip` **3000/minute** | `config/initializers/rack_attack.rb:71`; no blob-specific throttle exists |

There is no FORCE_SSL subtlety worth noting beyond `config.force_ssl` being env-driven and default **false**
(`config/environments/production.rb:46`).

**Is the route public?** Yes, in the strongest sense: it is not merely unauthenticated, it is served by a
controller hierarchy that has no authentication to skip. The portal already relies on this — see §2.5.

### 2.4 The one storage service, and why it is already singular

`config/environments/production.rb:43` resolves `ACTIVE_STORAGE_SERVICE`, defaulting to `:local`, and
`.env.example:143` ships that default. `config/storage.yml:5-7` maps `local` to a Disk service rooted at
`Rails.root.join("storage")`, outside `public/`, so `config.public_file_server` (`production.rb:23`) cannot
reach it. Five services are pre-wired (`storage.yml:1-40`) and **none declares `public: true`**, so
`Blob#url` always takes the `private_url` branch with a 5-minute expiry
(`…/lib/active_storage/service/disk_service.rb:156-158,164-173`). `active_storage_blobs.service_name` is
per-row (`db/schema.rb:107`) but nothing in the repository ever passes `service:` to an attach or a create, so
in practice every blob in the installation lives in one service.

### 2.5 The documentation portal already publishes a blob, publicly, through this exact route

This is the single most useful fact for the media decision, and it is not in `01-current-system.md`:

```erb
<% if portal.logo.present? %>
  <img src="<%= url_for(portal.logo) %>" class="w-8 h-8 rounded-full" draggable="false" />
```
(`app/views/public/api/v1/portals/documentation_layout/_topbar.html.erb:11-12`; the classic layout does the same
at `app/views/public/api/v1/portals/_header.html.erb:5-6,106-107`)

That page is served by `Public::Api::V1::PortalsController` → `Public::Api::V1::Portals::BaseController` →
`PublicController`, which is `ActionController::Base` with authentication nowhere in it
(`app/controllers/public_controller.rb:3-5`). So a non-expiring signed-id blob URL is **already** rendered into
an anonymous HTML page on the documentation portal and already fetched by anonymous browsers. The public-read
half of the requirement needs no new mechanism; it is live.

The gap is the other direction: nothing can *set* that logo on a platform portal.
`custom/app/dashboards/portal_dashboard.rb:10-23` has no logo field, and the tenant API route
(`config/routes.rb:329`, plus `process_attached_logo` at `portals_controller.rb:22,32`) is closed by
`Custom::PortalPolicy#logo? = false` and by `create?`/`update? = false`
(`custom/app/policies/custom/portal_policy.rb:25-31`).

### 2.6 A documentation image in Markdown renders as a plain `<img>`, with no help needed

`CustomMarkdownRenderer#image` hand-builds the tag:

```ruby
def image(node)
  src = sanitized_href(node.url)
  ...
    out(%(<img src="#{src}"))
```
(`lib/custom_markdown_renderer.rb:61-66`)

and `sanitized_href` blanks only four schemes, with `data:image/{png,gif,jpeg,webp}` explicitly allowed back
(`lib/markdown_renderer_url_sanitizer.rb:3-4,14-19`). An `https://…/rails/active_storage/blobs/redirect/…` URL
passes untouched. So the end-to-end public path for a documentation image works today with no code change at
all — which is precisely why the exposure question has to be answered before anybody uses it.

### 2.7 The two surfaces that do it right — the precedent, confirmed

`docs/platform-support/13-integration-record.md` points at it; I read the code and it holds.

**Tenant**: `custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:40-68`.
Authorization is a parent lookup, not a check on the blob — one relation, two subselects:
`ActiveStorage::Attachment.where(name: 'platform_support_message_files', record_type: 'PlatformSupport::Message',
record_id: PlatformSupport::Message.where(platform_support_ticket_id: ticket_scope.select(:id)).select(:id))`
(`:57-67`). An internal note's attachment 404s as a *consequence* of the relation, not as a special case
(`:18-23`). Disposition comes from the blob, by passing none (`:50`, and the reasoning at `:30-35`).

**Staff**: `custom/app/controllers/super_admin/platform_support_controller.rb:63-70`, behind
`authenticate_super_admin!` plus `require_support_agent!` (`:38,77-84`), with the owned names and parent types
as constants (`:35-36`) so the route cannot be turned into a reader for another subsystem's blobs.

**Neither hands out a URL.** `app/views/super_admin/platform_support/_attachments.html.erb:13` links the
authorized route by attachment id, and its header (`:4-7`) states why. The rule is enforced as a test, not a
convention: `spec/requests/platform_support/security/attachments_spec.rb:205-212` greps every Platform Support
view for `rails_blob|rails_storage_proxy|signed_id|service_url` and asserts the list is empty, and `:218-225`
asserts exactly two routes reach a blob. The identical-404 requirement is asserted too
(`:160-176`). `docs/platform-support/13-integration-record.md` §5 records that gate as green.

That spec file's own header (`:3-8`) is the finding this report generalises: *"Every other blob in this
installation is served by ActiveStorage's own signed-id redirect, with no policy check, and blob URLs here never
expire — so a leaked signed id is a permanent, account-less bearer token."*

---

## 3. Findings

Severity is about this product's exposure, not about CVSS. "Reachable today" means on the current tree;
"editor-upgrade only" means the code path does not exist until documentation media does.

### F1 — Signed blob IDs never expire

**Claim.** Every blob URL this product emits is a permanent bearer token.
**Evidence.** §2.2: `urls_expire_in` unassigned in the gem (`lib/active_storage.rb:357`), copied with no
fallback (`engine.rb:120`), never set by `load_defaults` (`railties .../configuration.rb`, no match), never set
by the app (`grep` over `config/ app/ custom/ lib/` finds only comments).
**Impact.** A URL in a browser history, a forwarded email, a pasted screenshot, a proxy log or a referrer grants
the file forever, to anyone, with no account scope and no way to revoke short of purging the blob or rotating
`SECRET_KEY_BASE` (which breaks every other blob URL at once — see F10).
**Severity: major.** Reachable today. Structural: it is the root cause of F2, F3, F5, F7.

### F2 — The blob routes perform no authorization, and nothing in this repository adds any

**Claim.** `/rails/active_storage/**` is unauthenticated and unscoped for reads.
**Evidence.** §2.1, §2.3. `BaseController` has no auth (`base_controller.rb:4-10`); `blob_scope` is the bare
class (`set_blob.rb:17-19`); no override exists in `app/ custom/ lib/ config/`; the only app-level ActiveStorage
prepends concern direct upload and byte ranges (`config/initializers/active_storage.rb:15-76`).
**Impact.** For blobs 1, 2, 4, 5, 6, 7 of §1.2, the only protection is that the URL is hard to guess. That is
protection against enumeration, not against disclosure, and it degrades monotonically: every URL emitted is one
more permanent key in circulation.
**Severity: major.** Reachable today.

### F3 — `GET /slack_uploads?blob_key=…` is an unauthenticated, unscoped blob-key → signed-URL oracle

**Claim.** An anonymous request converts any blob *key* in the installation into a signed, non-expiring blob
URL — for any account, any parent type, including an unattached blob.

**Evidence.**
```ruby
class SlackUploadsController < ApplicationController
  include Rails.application.routes.url_helpers
  before_action :set_blob, only: [:show]

  def show
    if @blob
      redirect_to blob_url
```
(`app/controllers/slack_uploads_controller.rb:1-11`), with
`@blob = ActiveStorage::Blob.find_by(key: params[:blob_key])` (`:15-17`) and
`url_for(@blob.representation(...))` or `url_for(@blob)` (`:19-26`). The route is `resource :slack_uploads,
only: [:show]` at `config/routes.rb:36`. `ApplicationController` has `set_current_user` but **no
`authenticate_user!`** (`app/controllers/application_controller.rb:1-13`).

The unauthenticated reachability is not my inference — the existing spec proves it. It creates a blob attached
to nothing, calls `get :show` with no sign-in, and asserts the redirect:
```ruby
blob = ActiveStorage::Blob.create_and_upload! io: file, filename: 'avatar.png'

it 'redirects to the blob service URL' do
  get :show, params: { blob_key: blob.key }
```
(`spec/controllers/slack_uploads_controller_spec.rb:7-12`)

**Impact.** The blob key is a 28-character secure token (`has_secure_token :key, length: 28`,
`…/app/models/active_storage/blob.rb:23-25`) and ActiveStorage's own comment on it reads *"This key is not
intended to be revealed directly to the user. Always refer to blobs using the signed_id or a verified form of
the key."* (`blob.rb:190-195`). It is therefore treated across the framework as semi-secret, not as a
capability: it appears in disk paths, in service-side object names, in storage-provider access logs, in backup
listings, and in anything that enumerates the bucket. This endpoint promotes it to a full capability for any
blob in the installation, cross-tenant, with no authentication. **This is the concrete answer to the brief's
"is there any path where one blob reference grants access to a sibling blob": yes, and it is not the article URL
— it is this.**
**Severity: major.** Reachable today. Not a documentation finding, but a documentation media design that reuses
`url_for(blob)` inherits the same namespace this endpoint hands out.

### F4 — `Blob.find_signed` + `attach`, with no ownership check, is the repository-wide attach pattern

**Claim.** A signed blob ID is accepted as an attachable from anywhere, with no check that the caller's account
created the blob or that it is unattached — and there is nothing to check against.
**Evidence.** `app/controllers/api/v1/accounts/portals_controller.rb:67-70` and
`app/controllers/concerns/attachment_concern.rb:22-29` both do `ActiveStorage::Blob.find_signed(...)` then
`attach`. `active_storage_blobs` has **no account, owner or uploader column at all** — `key, filename,
content_type, metadata, byte_size, checksum, created_at, service_name` and nothing else
(`db/schema.rb:99-109`). The only ownership link in the schema is
`active_storage_attachments.record_type/record_id` (`db/schema.rb:89-97`), which an unattached blob does not
have.
**Impact.** Blob laundering in both directions. Inbound: a signed ID obtained from a surface the caller may read
(e.g. a message attachment's `data_url`, which *is* a signed-ID URL — `app/models/attachment.rb:57-59,128`) can
be re-attached to a record on a more exposed surface. Outbound: a blob uploaded for one purpose is reachable
through another record's URL forever.
**Severity: major.** Reachable today **for macros and automation rules**
(`macros_controller.rb:26,38`, `automation_rules_controller.rb:25,37`). The portal-logo instance is **not**
reachable on Lynomia, because `Custom::PortalPolicy` refuses `create?`, `update?` and `logo?`
(`custom/app/policies/custom/portal_policy.rb:25-31`) and `check_authorization` runs unconditionally
(`portals_controller.rb:5`). I flag it anyway because it is the pattern a documentation media editor would be
copied from, and the policy that closes it is Lynomia overlay, not upstream.

### F5 — `/api/v1/accounts/:account_id/upload` mints an orphan, permanently public blob and returns both the URL and the signed ID

**Claim.** The shared upload endpoint creates a blob that nothing owns, nothing scopes, nothing expires and
nothing ever deletes.
**Evidence.** `ActiveStorage::Blob.create_and_upload!(io:, filename:, content_type:)` with **no `record:`**
(`app/controllers/api/v1/accounts/upload_controller.rb:39-45`), answered as
`render json: { file_url: url_for(file_blob), blob_id: file_blob.signed_id }` (`:47-49`). Route at
`config/routes.rb:348`. No cleanup exists: `grep -rn "unattached\|purge_later\|PurgeJob" app/ custom/ lib/
config/schedule.yml` returns **nothing**, so no `ActiveStorage::Blob.unattached` sweep and no scheduled purge
job is configured anywhere.
**Impact.** `docs/platform-support/13-integration-record.md` §6.1 names the consequence ("free file hosting with
non-expiring blob URLs") as the reason the Platform Support desk did not exempt this endpoint from the billing
guard. Stated as code: an authenticated member of any account can store arbitrary bytes, of any type the
endpoint accepts, at a URL readable by the entire internet forever, with no row linking it to them. There is
also a throttle of 60/hour per account on the route (`config/initializers/rack_attack.rb:272`), which bounds the
rate and not the retention.
**Severity: major.** Reachable today. **This endpoint must not be the documentation media upload path** — see
§5.1.

### F6 — Exports and import-failure files are emailed as permanent blob URLs

**Claim.** The whole contact database leaves the product as a non-expiring, unauthenticated URL inside an email.
**Evidence.**
```ruby
def account_contact_export_url
  Rails.application.routes.url_helpers.rails_blob_url(@account.contacts_export)
end
```
(`app/jobs/account/contacts_export_job.rb:96-98`, mailed at `:90-94`), and the same for the rejected rows of a
contact import:
```ruby
action_url = if resource.failed_records.attached?
               Rails.application.routes.url_helpers.rails_blob_url(resource.failed_records)
```
(`app/mailers/administrator_notifications/account_notification_mailer.rb:29-31`). The export's columns are
`%w[id name email phone_number labels]` (`contacts_export_job.rb:99-101`), written as CSV and attached at
`:83-87`; the failed-records CSV at `app/jobs/data_import_job.rb:116-122`.
**Impact.** Forwarding that one email forwards the account's contact database — names, emails, phone numbers —
to anyone, forever, with no account scope, no session and no revocation. Email is forwarded, archived in third
parties, and indexed by mail search. This is the highest-value blob in the product on the weakest protection in
the product.
**Severity: blocker.** Reachable today. Outside documentation scope, but it is the clearest demonstration of why
the documentation media design must not reach for `rails_blob_url`, and the orchestrator should route it to
whoever owns contact import/export (Agent 031).

### F7 — Private blobs are protected by obscurity only, Platform Support excepted

**Claim.** Of the eight attachments in §1.2, exactly one subsystem authorizes a read.
**Evidence.** The per-row protection, read out:

| Blob | How its URL is emitted | What authorizes the read |
|---|---|---|
| message attachment | `url_for(file)` into `data_url` (`app/models/attachment.rb:57-59`), serialized at `app/views/api/v1/models/_attachment.json.jbuilder:6` and pushed over ActionCable via `push_event_data` (`attachment.rb:50-54,124-137`) | **nothing** — F2 |
| message thumbnail | `url_for(file.representation(resize_to_fill: [250, nil]))` (`attachment.rb:67-76`) | **nothing** |
| avatar | `url_for(avatar.representation(...))` (`app/models/concerns/avatarable.rb:15-19`) | **nothing** |
| portal logo | `url_for(portal.logo)` into a public page (`_topbar.html.erb:12`) and `file_base_data` (`app/models/portal.rb:104-116`, which also emits `blob_id: logo.blob.signed_id`) | **nothing — and that is correct here**, it is meant to be public |
| import CSV | not emitted | nothing emits it; a blob with no URL in circulation is protected only by that |
| import failed records | `rails_blob_url` in an email (F6) | **nothing** |
| contacts export | `rails_blob_url` in an email (F6) | **nothing** |
| automation / macro files | `url_for` paths via the same `Attachment` model when sent | **nothing** |
| Platform Support message files | **no URL is ever emitted** (`spec/requests/platform_support/security/attachments_spec.rb:205-212`) | parent lookup through `PlatformSupport::TicketPolicy::Scope` (`attachments_controller.rb:57-67`) |
| Platform Support note files | no URL emitted | acting-agent guard + owned-type allow-list (`platform_support_controller.rb:35-36,63-70`) |

**Impact.** The product's security posture for files is "the URL is long". That is defensible for an avatar and
indefensible for a contact export, and nothing in the code distinguishes them.
**Severity: major.** Reachable today.

### F8 — A documentation blob URL cannot be enumerated or guessed, but the guarantee rests entirely on `SECRET_KEY_BASE`

**Claim.** Guessing is infeasible; the signature is the only thing making it so, and that same secret protects
everything else.
**Evidence.** `signed_id` is generated by `ActiveStorage.verifier`, which is
`app.message_verifier("ActiveStorage")` (`…/lib/active_storage/engine.rb:137-139`) — an
`ActiveSupport::MessageVerifier`, SHA256 digest, keyed through `Rails.application.key_generator` from
`secret_key_base`. The payload is only the integer primary key: `find_signed!` verifies then calls `find(id)`
(`…/activerecord-7.2.3.2/lib/active_record/signed_id.rb:72-76`). A bad signature yields a bare `head :not_found`
with no body (`set_blob.rb:13-14`), so the route is not an oracle for existence either. This installation reads
`secret_key_base` only from the environment — `config/secrets.yml:14-26`, a file whose own header
(`:3-12`) records that nothing reads it and that its formerly-committed dev/test keys were inert and have been
removed.
**Verdict and the part that matters.** The blob *id* inside the signature is sequential and trivially
predictable; only the HMAC stands between an attacker and `for id in 1..N: sign(id)`. So:
- **Enumeration today: not feasible.** Only the global 3000/min IP throttle guards the route
  (`rack_attack.rb:71`), but there is nothing to brute-force — forging one signature is the whole problem.
- **Enumeration after a `SECRET_KEY_BASE` disclosure: total.** One leaked secret yields *every blob in the
  installation*, not a session or a subset, because there is no per-blob scope (F2) and no expiry (F1) to limit
  the blast radius. The same secret also keys Devise — `config.secret_key` is left commented out, so Devise
  falls back to `secret_key_base` as its own header states (`config/initializers/devise.rb:7-9`) — so blob
  confidentiality is already coupled to session confidentiality with no isolation between them.
- **And the rotation is not available as a remedy.** Because `urls_expire_in` is nil, rotating
  `SECRET_KEY_BASE` invalidates *every signed ID ever emitted at once*. For a documentation article whose
  Markdown holds signed-ID image URLs, that means every image in the corpus breaks simultaneously on a key
  rotation, with no migration path, because the URLs are free text in `articles.content` and nothing knows where
  they are. **This single consequence is the decisive argument against embedding signed IDs in article content**
  — see §5.
**Severity: minor today; blocker conditional on key compromise; major as a design constraint on media.**

### F9 — A documentation blob URL leaks no uploader, but it does leak the filename twice, and nothing strips EXIF

**Claim.** Three separate answers to the brief's three questions.

**(a) Uploader: no leak, structurally.** `active_storage_blobs` has no uploader, author or account column
(`db/schema.rb:99-109`), and the signed ID encodes only the row id (F8). There is nothing to leak. For a
documentation image attached to an `Article`, the author would be `articles.author_id` — already public in the
portal byline and already defaulting to `SuperAdmin.first` via the seeder
(`01-current-system.md` §3; `content_seeder.rb:22`), so the blob adds nothing new.
**Severity: none.** Noted so nobody re-litigates it.

**(b) Filename: leaked twice over, in cleartext.** The filename is the last path segment of the URL
(`…/config/routes.rb:5`: `/blobs/redirect/:signed_id/*filename`) and is repeated in `Content-Disposition`. For a
documentation image it is additionally published in **raw Markdown**, because the portal serves the article
source unrendered:
```ruby
def show_markdown
  return head :not_found unless @article&.published?

  render plain: @article.content.to_s, content_type: 'text/markdown; charset=utf-8'
end
```
(`app/controllers/public/api/v1/portals/articles_controller.rb:29-33`). So `internal-roadmap-q3-FINAL.png` or
`acme-corp-escalation.png` is public text, indexable, with no rendering step to hide it behind.
**Severity: major**, because the authoring surface has no filename discipline and screenshots are named by
whoever took them. Editor-upgrade only.

**(c) Image metadata: nothing strips it.** `grep -rn -i "exif\|strip_metadata\|sanitize_image" app/ custom/
lib/ config/` returns **nothing**; the only hit for image tooling is `gem 'image_processing'`
(`Gemfile:59`), used for the single fixed `resize_to_fill: [250, nil]` transform
(`attachment.rb:71`, `avatarable.rb:16`). A documentation `<img>` would point at the **original** blob, not a
variant, so camera model, software, timestamps and GPS survive into a public page.
**Severity: major.** Editor-upgrade only. Overlaps Agent 087 (provenance); flagged here because the carrier is
the blob.

### F10 — Purging a documentation blob silently breaks a published article, and nothing can tell an operator a blob is still in use

**Claim.** The relationship between article content and blob is a string, so it cannot be checked, counted or
protected.
**Evidence.** After a purge the blob row is gone and `find_signed!` reaches `find(id)`, which raises
`ActiveRecord::RecordNotFound` (`…/active_record/signed_id.rb:72-76`) → **404** (§2.3). The rendered page keeps
`<img src="…">` (`lib/custom_markdown_renderer.rb:61-71`) and the browser shows a broken image with no
server-side signal. There is no foreign key, no join table and no index between `articles.content` and
`active_storage_blobs`; `articles.content` is free text and the seeder rewrites it wholesale from file on every
run (`01-current-system.md` §3: `title`, `description`, `content`, `category`, `position`, `meta` all
overwritten, `content_seeder.rb:94-104`).
**Impact.** Two distinct failures. (1) A manual purge, or the destroy of any parent record,
silently breaks live public pages. (2) In the other direction, an image URL authored in Super Admin is
**erased** by the next `rails documentation:content` run, because the seeder overwrites `content` from the
Markdown file — so a media design that lives only in the database loses its media on the next sync. For an
attachment on `Article`, `has_one_attached`'s default `dependent: :purge_later` would purge on article destroy,
which the seeder never does (it "deletes nothing", §3 of the same document), so the realistic purge is a manual
one and the realistic loss is (2).
**Severity: major** — it is an availability and a content-integrity defect, not a disclosure one. Editor-upgrade
only, and it is a Phase 4 contract question (§8.3 "media ownership model"), not a patch.

### F11 — SVG cannot be served inline through any blob route, and the mechanism that prevents it is also the stored-XSS defence

**Claim.** An `<img src>` at an SVG blob renders nothing, and the obvious fix is dangerous.
**Evidence.** Rails' default `content_types_to_serve_as_binary` contains `text/html` and `image/svg+xml`
(`…/lib/active_storage/engine.rb:55-65`). `config/initializers/active_storage.rb:5-13` appends **seven audio
types to `content_types_allowed_inline`** and never touches the binary list. `Blob::Servable` then forces both
the type and the disposition:
```ruby
def content_type_for_serving
  forcibly_serve_as_binary? ? ActiveStorage.binary_content_type : content_type
end

def forced_disposition_for_serving
  if forcibly_serve_as_binary? || !allowed_inline?
    :attachment
  end
end
```
(`…/app/models/active_storage/blob/servable.rb:4-12`). So an SVG blob is served as
`application/octet-stream` with `Content-Disposition: attachment`.
**Impact.** A documentation diagram uploaded as SVG is silently broken for every reader. The dangerous part is
the fix: `text/html` sits in the same list, and that list is the only thing stopping an uploaded HTML file from
executing on the app's own origin — the installation serves blobs from the app host, since
`ACTIVE_STORAGE_SERVICE` defaults to the local Disk service (`production.rb:43`, `.env.example:143`) and
`default_url_options.host` is `FRONTEND_URL` (`production.rb:105`). Adding `image/svg+xml` to
`content_types_allowed_inline` to "fix diagrams" would also be a same-origin script-execution hole, because an
SVG can carry `<script>`.
**Severity: major as a media-design constraint, and the defence is currently correct.** Editor-upgrade only.
Overlaps Agent 084; recorded here because it is a property of the blob-serving path, not of the sanitizer.

### F12 — Nothing requires a documentation image to be a blob at all

**Claim.** An author can point an article image at any third-party host today, or inline it as base64, and
nothing objects.
**Evidence.** `sanitized_href` blanks `javascript:`, `vbscript:`, `file:` and `data:` — **except** that
`data:image/{png,gif,jpeg,webp}` is explicitly re-permitted:
```ruby
DANGEROUS_URL_PATTERN = /\A(?:javascript:|vbscript:|file:|data:)/i
SAFE_DATA_IMAGE_PATTERN = %r{\Adata:image/(?:png|gif|jpeg|webp)}i
...
return '' if url.match?(DANGEROUS_URL_PATTERN) && !url.match?(SAFE_DATA_IMAGE_PATTERN)
```
(`lib/markdown_renderer_url_sanitizer.rb:3-4,14-19`). Any `https://` host passes unconditionally. And there is
no `img-src` to stop it: the CSP is `object-src 'none'; base-uri 'self'` and nothing else
(`config/initializers/content_security_policy.rb:14-17`).
**Impact.** A public Lynomia documentation page can make every reader's browser issue a request to a
third-party host the author chose — an IP and user-agent log of the product's readership, outside the product,
with no record. The `data:` branch additionally allows unbounded inline image payloads in `articles.content`.
**Severity: major.** **Reachable today** — an operator can type it into the 28-row textarea now
(`custom/app/dashboards/article_dashboard.rb:19`), and the editor upgrade only makes it easier.
**Contradiction to arbitrate:** `01-current-system.md` (as revised 2026-10-13) states that "`javascript:`,
`vbscript:`, `file:` and `data:` URLs are blanked". The `data:` half is wrong for the four image subtypes named
above, by the code quoted here. Small, but it is load-bearing for the media decision, since `data:` images are a
media channel that bypasses ActiveStorage entirely.

### F13 — `meta['feature_image']` is an unvalidated absolute URL, dashboard-only

**Claim.** The one existing documentation media field is a free-text URL with no validation.
**Evidence.** `custom/app/fields/article_meta_field.rb:13` (`STRING_KEYS` includes `feature_image`), `:21`
(label "Feature image URL"), `:30` (hint "Absolute URL of the image shown with the release"), permitted at
`:33-35`. Rendered as `<img :src="card.feature_image">` in
`app/javascript/dashboard/components-next/changelog-card/StackedChangelogCard.vue:59-75`. It is **not** on the
public portal: `og:image` there comes from the `OG_IMAGE_CDN_URL` service
(`app/helpers/portal_helper.rb:3-18`), consumed at
`app/views/public/api/v1/portals/articles/_meta_head.html.erb:16-20` and the documentation variant at
`documentation_layout/articles/_meta_head.html.erb:58-60`.
**Severity: minor.** Reachable today, dashboard-only. Worth naming because it is the precedent a media field
would be modelled on, and it is the wrong precedent.

---

## 4. What the editor upgrade would newly expose

Today the corpus has zero images (§1.2) and `Article` has no attachment, so almost nothing in §3 is live for
documentation. The upgrade changes five things at once.

1. **The first documentation blobs.** Whatever route serves them becomes load-bearing for an anonymous public
   page. If that route is `rails_storage_redirect`, then from that moment the generic blob route **cannot ever
   be restricted**, because restricting it is exactly what would protect blobs 1, 2, 4–7 of §1.2. The two
   requirements collide on one route. This is the heart of the brief's question and §5.2 answers it.
2. **A reason to call `find_signed` on author input.** The repository's only attach pattern (F4) accepts a
   signed ID from the request with no ownership check. A documentation editor built on that pattern would accept
   a signed ID from *any* blob — including a message attachment an operator can see in the dashboard — and
   republish it on a public portal page. That is cross-tenant disclosure through a documentation article, and it
   is the direct analogue of the Platform Support tenant-leak question
   (`docs/platform-support/13-integration-record.md` §4, and §2.7 above).
3. **Filenames and EXIF in public text.** F9(b) and F9(c). Screenshots are the documentation author's primary
   media, and a screenshot is the single most likely file to carry both a revealing filename and a credential in
   the frame (Agent 087's scope).
4. **SVG and pasted HTML.** F11, plus the latent `:UNSAFE` trap `01-current-system.md` §5 records. A diagram
   workflow that reaches for inline SVG meets the same list that keeps uploaded HTML inert.
5. **Media the sync erases.** F10(2). Any image an author attaches in Super Admin is wiped by the next
   `rails documentation:content` run, because the seeder overwrites `content` from file. A media model and the
   source-of-truth decision (§8.1 of the charter) are the same decision, not two.

---

## 5. Required controls

Minimum set. Each maps to a mechanism that already exists in this repository; none is a new subsystem, per §2 of
the charter.

### 5.1 Can one service and one URL scheme serve both? — the direct answer

**One storage service: yes, and it already is one.** §2.4: one service resolved for the whole installation
(`production.rb:43`), one Disk root (`storage.yml:5-7`), no service declares `public: true`, nothing passes
`service:` anywhere. A second, public bucket is **optional** and buys CDN caching, not authorization. It is a
performance decision for Agent 080, not a security one, and splitting services does not help: a second service
would still be read through the same unscoped, unexpiring route.

**One URL scheme: no — not without widening access to the private blobs.** The reason is precise and is not a
matter of degree. The public route's entire authorization predicate is *"hold a valid signature over this blob
id"* (§2.1). That predicate is **byte-for-byte identical** for a documentation screenshot and for a contacts
export, because:

- the signature covers only the integer primary key (`active_record/signed_id.rb:72-76`),
- there is no record scoping (`set_blob.rb:17-19` returns the bare class),
- there is no expiry (F1),
- and the blob row carries nothing to discriminate on — no account, no owner, no purpose
  (`db/schema.rb:99-109`).

So the route cannot be taught to say yes to one and no to the other. Publishing documentation media through it
makes "anonymous read of any blob whose signature you hold" a **public contract of the documentation portal**,
which forecloses ever tightening it. The requirements are not merely different; they are in direct conflict on
the same route.

**Therefore: one service, two routes.** Public documentation media on a dedicated route scoped to "a blob
attached to a published platform-portal article"; everything else left on, or moved behind, a parent-lookup
route of the Platform Support shape. That is the same conclusion the Platform Support work reached, generalised
from one module to the installation.

### 5.2 The minimum safe design

**C1. An article image is an attachment on `Article`, not an orphan blob.** `has_many_attached` with a named
constant on the model, mirroring `custom/app/models/platform_support/message.rb:39`
(`FILES_ATTACHMENT_NAME`). This is the one control that makes every other control expressible, because it
creates the parent row to authorize against — the blob table has nothing (F4). It also gives the blob a
lifecycle (`dependent: :purge_later`), which answers the orphan problem (F5).
**Mechanism: `has_many_attached`, already used in eight places.**
**Explicitly not** `/api/v1/accounts/:account_id/upload` (F5): it is account-scoped, and platform documentation
portals have `account_id = NULL` by design (`app/models/portal.rb:42-46,57-58`, and `01-current-system.md` §10) — so
it is the wrong tenancy as well as the wrong lifecycle.

**C2. One new public read route, scoped by the relation that already exists.** The scope is a one-liner,
because `Documentation::Library` already expresses it:
`ActiveStorage::Attachment.where(name: <the constant>, record_type: 'Article', record_id:
Documentation::Library.articles.select(:id))` — and `Library.articles` is
`Article.published.where(portal: Portal.platform.active.where(slug: SLUGS))`
(`custom/app/services/documentation/library.rb:37-43`). Three properties fall out for free:
unpublishing an article revokes its images; a tenant help-centre article's media is not reachable; and a
draft's media is not public.
- Serve with `ActiveStorage::Streaming#send_blob_stream` and **pass no disposition**, exactly as
  `custom/app/controllers/api/v1/accounts/platform_support/attachments_controller.rb:50` does, so
  `Blob#forced_disposition_for_serving` keeps `text/html` and SVG as downloads (F11) with no second allow-list
  to drift.
- Base it on `PublicController` (`app/controllers/public_controller.rb:3-5`), the portal's own base class — not
  `ApplicationController`, which is what makes F3 what it is.
- 404 identically for every miss, as `spec/requests/platform_support/security/attachments_spec.rb:160-176`
  already asserts for the other two routes.
- This is the one route in the product where `http_cache_forever public: true` is right
  (`…/blobs/proxy_controller.rb:18`), which is the CDN/CWV answer Agent 080 needs.
**Mechanism: `ActiveStorage::Streaming` + `Documentation::Library`, both existing.**

**C3. The URL written into article content is the attachment-id path, never a signed ID.** Three reasons, each
independently sufficient:
- a signed ID survives unpublishing, so it leaks a withdrawn article's media (F1 + C2);
- it is published in cleartext at `show_markdown` (`articles_controller.rb:29-33`), so it is a permanent bearer
  token sitting in a public text file;
- every one of them breaks simultaneously on a `SECRET_KEY_BASE` rotation (F8), with no way to find them,
  because `articles.content` is free text.
An attachment-id path has none of those properties: it is revoked by unpublishing, it carries no secret, and it
survives key rotation.
**Mechanism: `app/views/super_admin/platform_support/_attachments.html.erb:13` is this pattern already.**

**C4. Enforce the media rule at one shared entry point.** Per CLAUDE.md ("enforce eligibility at the earliest
shared entry point… do not repeat backup guards downstream"). The earliest shared point for article content is
the write: a validation that an article's image URLs resolve to the C2 route or to an allow-listed host. That
closes F12 and F9(b) at the only place both the seeder and Super Admin pass through. It is **not** a second
sanitizer in the render path — `01-current-system.md` §5 and Agent 081 own that path, and a second one would be
exactly the duplication §2 of the charter forbids.

**C5. Do not add `image/svg+xml` to `content_types_allowed_inline`.** F11. `text/html` is in the same
`content_types_to_serve_as_binary` list and that list is the only thing keeping an uploaded HTML file inert on
the app's own origin. If SVG diagrams are wanted, rasterize at upload or render sanitized inline markup through
a structured component (Agents 071/084) — never as a blob served inline.

**C6. Strip image metadata on upload.** F9(c). `image_processing` is already a dependency (`Gemfile:59`) and the
variant pipeline already runs vips, so this is a transform on an existing path, not a new one. Owner: Agent 087.

**C7. Name the filename as content, not as plumbing.** F9(b). The filename is public twice over; the editor
should generate or constrain it rather than accept whatever the author's screenshot tool produced.

### 5.3 Three live defects the media decision must not inherit

None is documentation work. All three are reasons a documentation media design that reaches for `url_for(blob)`
would be building on sand, so Phase 4 should record them and the orchestrator should route them.

| # | Defect | Severity | Suggested owner |
|---|---|---|---|
| F6 | contacts export + import failures emailed as permanent public URLs | **blocker** | Agent 031 (contacts/import) |
| F3 | `/slack_uploads` is an unauthenticated, unscoped blob-key → signed-URL oracle | **major** | Agent 086 (Super Admin authz) or a dedicated owner |
| F5 | `/api/v1/accounts/:id/upload` creates orphan, permanently public blobs that nothing purges | **major** | Agent 030 (composer/attachments) |

---

## 6. Severity summary

| ID | Finding | Severity | Reachable |
|---|---|---|---|
| F1 | signed blob IDs never expire (`urls_expire_in` is nil) | major | today |
| F2 | blob routes have no authorization and no override exists | major | today |
| F3 | `/slack_uploads` unauthenticated blob-key → URL oracle | major | today |
| F4 | `find_signed` + `attach` with no ownership check | major | today (macros, automation rules) |
| F5 | `/upload` mints orphan permanently-public blobs; no purge | major | today |
| F6 | contact export / import failures emailed as permanent URLs | **blocker** | today |
| F7 | private blobs protected by obscurity only, Platform Support excepted | major | today |
| F8 | not enumerable, but wholly dependent on `SECRET_KEY_BASE`; rotation breaks every URL | minor / blocker-on-compromise | today |
| F9a | uploader leak | **none** | — |
| F9b | filename leaked in URL and in public raw Markdown | major | editor upgrade |
| F9c | no EXIF stripping anywhere | major | editor upgrade |
| F10 | purge breaks a published article; seeder erases DB-only media | major | editor upgrade |
| F11 | SVG cannot serve inline; the fix is a same-origin XSS hole | major (design) | editor upgrade |
| F12 | nothing requires a documentation image to be a blob; no `img-src` CSP; `data:image/*` allowed | major | today |
| F13 | `meta['feature_image']` unvalidated absolute URL | minor | today, dashboard-only |

## 7. Not checked

- **No HTTP status was observed.** Every status in §2.3 is read off the controller and `rescue_responses`. The
  statuses asserted by existing specs (F3's unauthenticated redirect, the Platform Support 404s) are the ones I
  would trust without a server; the rest want one request each to confirm.
- **The production value of `ACTIVE_STORAGE_SERVICE`.** `.env.example:143` and both environment files default to
  `local`, and `docs/p7/00-discovery-findings.md:801` records Disk in production, but I did not read a
  production `.env` and §3 forbids it. If production is on S3 or S3-compatible, F1 and F2 are unchanged (the
  outer signed ID is the app's, not the provider's) but the second hop and the CDN story differ.
- **Whether any blob URL has already leaked.** That is a log question, not a code question.
- **`blob.metadata` contents.** The column exists (`db/schema.rb:103`) and the direct-upload path strips three
  internal keys (`config/initializers/active_storage.rb:15-25`), but I did not enumerate what analysis writes
  into it. It is not emitted on the blob route; it would be emitted by any serializer that exposes `metadata`.
- **The variant/representation route as a distinct exposure.** `track_variants` is `true` under
  `load_defaults 7.0` (`railties .../configuration.rb:201-202`) and the representation route takes a signed blob
  ID plus a separately-signed variation key (`…/config/routes.rb:9-11`), so swapping a foreign blob id into a
  representation URL fails the signature. I read the routes and the controllers but did not trace
  `ActiveStorage::Variation.encode` end to end; the claim "a representation URL is no weaker than its blob URL"
  is an inference, not a proof.
