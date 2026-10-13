---
agent: 087
scope: Content provenance and secret leakage in the public documentation corpus, including screenshots containing credentials
confidence: high
---

The corpus itself is clean. I scanned all 126 Markdown files under `custom/db/documentation/`, both
`manifest.yml` files and the 2 files under `custom/db/changelog/`, for every class of value the brief names,
and found **no secret, no credential, no real identifier and no internal address**. That result is reported in
full in §3.1, because "I checked and found nothing" is only worth something if the reader can see what was
checked.

The leak is not in the corpus. It is in the publishing path. The public `/docs` portal renders a **named
staff byline and avatar on every article and every category page**, taken from `articles.author_id`, which the
seeder fills with `SuperAdmin.first`. The product's own written policy forbids exactly this and was
implemented in the JSON-LD only; the visible page body publishes what the policy withholds. That is finding
F1 and it is live today.

The second half is forward-looking. This program adds screenshots to a corpus that currently contains **zero
images**, and it will do so with no EXIF stripping anywhere in the application, no filename convention, no
media review step, no CI gate over the corpus, and an open `data:image/...` channel that lets an author embed
a screenshot inside the Markdown itself — invisible to any upload-time or blob-level control, and permanent in
git. §4 and §5 specify the controls.

---

## 1. Attack surface

### 1.1 The corpus, and what is public

`custom/db/documentation/` is 126 `.md` files (63 EN + 63 AR) plus `manifest.yml`; `custom/db/changelog/` is 2
`.md` files plus `manifest.yml`. Every one of the 128 articles is published world-readable:
`Documentation::ContentSeeder` forces `status: :published` on every run (`content_seeder.rb:101`), and
`Documentation::Library.articles` serves `Article.published` from the platform portals (`library.rb:42-44`) at
`/docs` and `/docs/:slug` (`custom/app/controllers/documentation_controller.rb:8-26`). There is no draft state
that survives a sync and no per-article access control. **Anything committed to a corpus file is published by
the next `rails documentation:content`.**

### 1.2 The publishing path that adds data the files do not contain

The corpus is not the only input to a published page. The render path injects database-resident values that no
corpus grep can see:

| Step | Evidence |
|---|---|
| Docs portal is seeded with `layout: 'documentation'` | `custom/app/services/documentation/portal_seeder.rb:65` |
| That layout selects the `:documentation` view variant | `app/controllers/public/api/v1/portals/base_controller.rb:26-30` |
| The article page renders the documentation header partial | `app/views/public/api/v1/portals/articles/show.html+documentation.erb:13-14` |
| The header publishes the author's avatar and name | `app/views/public/api/v1/portals/documentation_layout/articles/_header.html.erb:15-22` |
| The avatar partial puts the name in `alt` and `title` | `app/views/public/api/v1/portals/documentation_layout/_user_avatar.html.erb:12,15,17` |
| The category page publishes every author's avatar and name | `app/views/public/api/v1/portals/documentation_layout/categories/_header.html.erb:5-10` |
| The author set comes from the category's articles | `app/controllers/public/api/v1/portals/categories_controller.rb:34` |
| Names are joined into a visible "by …" label | `app/helpers/portal_helper.rb:119-128` |

`available_name` resolves to `display_name` or `name` (`app/models/concerns/user_attribute_helpers.rb:4-6`) —
a person's real name in every ordinary configuration. `avatar_url` returns an ActiveStorage representation URL
(`app/models/concerns/avatarable.rb:15-19`), and when a user has uploaded no avatar the application fetches one
from Gravatar keyed on their email address (`avatarable.rb:12,21-27`), so the published image may be a staff
member's personal Gravatar photo.

### 1.3 The image channel

`ChatwootMarkdownRenderer#render_article` renders article CommonMark through `CustomMarkdownRenderer`
(`lib/chatwoot_markdown_renderer.rb:13-19`). `CustomMarkdownRenderer#image` passes the image URL through
`sanitized_href` (`lib/custom_markdown_renderer.rb:61-71`), and that method's allowlist explicitly permits data
URIs for images:

```ruby
DANGEROUS_URL_PATTERN  = /\A(?:javascript:|vbscript:|file:|data:)/i
SAFE_DATA_IMAGE_PATTERN = %r{\Adata:image/(?:png|gif|jpeg|webp)}i
```

(`lib/markdown_renderer_url_sanitizer.rb:3-4`, used at `:14-19`)

So `![alt](data:image/png;base64,…)` in a corpus file renders as a live inline image on a public page. See F4.

### 1.4 Authoring, and what it records

`SuperAdmin::ArticlesController` is the only authoring surface (`custom/app/controllers/super_admin/articles_controller.rb`).
`publish` and `unpublish` call `requested_resource.update!(status:)` directly (`:10-18`). `new_resource` sets
`author: current_super_admin` (`:35-37`). `ArticleDashboard::FORM_ATTRIBUTES` does **not** include `author`
(`custom/app/dashboards/article_dashboard.rb:36`), so the author cannot be corrected through the form.

### 1.5 Media storage, as configured

`config/storage.yml` declares no service with `public: true`. `config/application.rb:71` disables previewers.
`config/initializers/active_storage.rb:15-24` strips three *internal* ActiveStorage metadata keys from direct
uploads and nothing else. A repository-wide grep for `exif`, `strip_metadata`, `image_processing` and `vips`
across `config/`, `app/`, `lib/` and `custom/` returns **nothing**: no image metadata is removed anywhere.

---

## 2. What the existing defence actually does

Three defences exist in this area. Two work and are narrower than they look; one is stated but not
implemented where it matters.

**The audit log's secret scrubber works, and never sees an article.** `Custom::AuditLog` scrubs credentials
out of `audited_changes` before every save:

```ruby
before_save :drop_secret_changes
…
def drop_secret_changes
  return unless audited_changes.is_a?(Hash)

  self.audited_changes = AuditTrail::Secrets.scrub(audited_changes)
end
```

(`custom/app/models/custom/audit_log.rb:18,53-57`)

Its header states the rule plainly: *"no credential reaches `audited_changes`"* (`:10-13`). That is a real
control. But `custom/app/models/custom/audit/` holds 14 capture modules — account, account_user, agent_bot,
automation_rule, conversation, custom_filter, inbox, inbox_member, macro, team, team_member, user, webhook,
plus the shared `capture.rb` — and **there is no `article.rb`**. `Article` carries no `audited` declaration,
and `SuperAdmin::ApplicationController` adds no capture. A documentation article's creation, edit, publish or
unpublish writes no audit row at all. See F3.

**The JSON-LD author policy works, inside the JSON-LD.** `DocumentationHelper` states the policy in the
comment above the schema builder:

> `author` is the PORTAL, never the agent who wrote it. A documentation page is published by Lynomia, and
> putting a staff member's name into public structured data would publish an employee's identity to the whole
> internet for no reader's benefit.

(`custom/app/helpers/documentation_helper.rb:80-82`)

And it does what it says — `'author' => { '@type' => 'Organization', 'name' => portal.display_title(...) }`
(`:92`). The same rule is written down as a decision at `docs/product-refinement/03-documentation-seo.md:72-74`.
Note its exact words: *"public structured data"*. The policy was scoped to the `<script type="application/ld+json">`
block and implemented only there. The visible HTML body of the very same page publishes the staff member's
name and photograph. See F1.

**The URL sanitizer works, and deliberately admits data-URI images.** `sanitized_href` blanks
`javascript:`, `vbscript:`, `file:` and `data:` URLs — except `data:image/png|gif|jpeg|webp`, which it passes
through by design (`lib/markdown_renderer_url_sanitizer.rb:3-4,14-19`). That is a defence against script URLs,
not a defence against image content. It is the reason F4 exists.

**There is no fourth defence.** No CI workflow references `custom/db/documentation`, `documentation:content`
or `seo_audit` (checked across all 16 files in `.github/workflows/`). There is no gitleaks, trufflehog or
detect-secrets configuration in the repository or in `.github/`. There is no README or CONTRIBUTING beside the
corpus. The only data-level gate that exists is `lynomia:docs:seo_audit`, and it audits indexability, not
content safety (`lib/tasks/documentation_seo_audit.rake:1-11`).

---

## 3. Findings

### 3.1 The corpus audit: what I checked, and what I found

Reported first because it is the brief's first question, and because the negative result is the finding.

**Nothing in either tree.** Each of these returned zero matches across all 126 documentation files, both
manifests and both changelog files:

| Class | Pattern | Result |
|---|---|---|
| Meta user/system tokens | `EAA[A-Za-z0-9_-]{10,}` | none |
| JWTs | `eyJ[A-Za-z0-9_-]{5,}` | none |
| Hex secrets | `[0-9a-f]{16,}` | none |
| UUIDs | RFC 4122 shape | none |
| Vendor key prefixes | `sk_ pk_ ck_ cs_ ghp_ gho_ xox[baprs]- AKIA ASIA shpat_ shpss_ shpca_ AIza ya29. glpat- npm_` | none |
| Private keys / certs | `BEGIN … PRIVATE KEY`, `BEGIN CERTIFICATE` | none |
| Email addresses | `[\w.%+-]+@[\w.-]+\.[A-Za-z]{2,}` | none |
| IPv4 literals | dotted-quad | none |
| WABA / phone-number / business IDs | `[0-9]{9,}` | none that is an ID (see below) |
| Order / invoice / ticket numbers | `#[0-9]{3,}` | none |
| Database names, `DATABASE_URL`, Redis, Sidekiq | keyword | none |
| Admin / super-admin / internal paths | `/super_admin /admin /sidekiq /rails/ /internal` | none |
| Images of any kind | `![`, `<img`, `.png .jpg .jpeg .webp .gif .svg` | **none — the corpus is text-only** |

**Everything the broader sweeps did surface, classified.** These are the hits a naive scan reports. Every one
is a documented example placeholder, a public API value, or prose about a secret rather than a secret.

| Value | Where | Verdict |
|---|---|---|
| `+966551112233`, `00966551112233`, `966551112233`, `0551112233` | `en/contacts/import-contacts.md:66-70`; `ar/contacts/import-contacts.md:65-69` | **placeholder.** A phone-normalisation table. Digits run `55-111-2233`. |
| `+965 5111 2233` | `en/contacts/import-contacts.md:101`; `ar/…:99` | **placeholder**, same pattern. |
| `+96522201234`, `0551112233` | `en/contacts/contacts.md:45,48`; `ar/contacts/contacts.md:42,44` | **placeholder.** `2220-1234` is a repeat-then-sequence pattern, used to explain the `+`-and-country-code rule. |
| `AHMED al-sabah` → `Ahmed Al-sabah` | `en/conversations/canned-responses.md:64`; `ar/…:59-60` | **placeholder**, demonstrating name titleisation. Note it is a Kuwaiti ruling-family surname; see F6. |
| `Hello Fatima, orders inside Kuwait…` | `en/conversations/canned-responses.md:82` | **placeholder** persona in a canned-response example. |
| `Noura` | `en/getting-started/your-first-conversation.md:90` | **placeholder** persona in a narrative scenario. |
| `Al Manar Furnishings` | `en/getting-started/set-up-your-account.md:65` | **fictional business** in a worked example. Not a tenant of this installation. |
| "a clinic in Kuwait", "a clinic in Riyadh" | `en/workspace/set-up-an-inbox.md:64`; `en/whatsapp/connect-whatsapp.md:70`; `en/getting-started/invite-your-team.md:65` | **generic persona**, no name. |
| `#support-watch` | `en/integrations/integrations.md:67`; `ar/…:63` | **placeholder** Slack channel in a worked example. Not a real Lynomia channel — the example is a customer's own workspace. |
| `LYN-000123` | `en/troubleshooting/contact-lynomia-support.md:34`; `ar/…:33` | **placeholder** ticket reference, zero-padded, illustrating the format. |
| `http://localhost`, `http://192.168.x.x`, `http://10.x.x.x`, `.local` | `en/troubleshooting/commerce-store-address-refused.md:24`; `ar/…:23`; `en/integrations/webhooks.md:120` | **documentation of an SSRF control**, not an internal address. Octets are masked `x.x`. |
| `https://shop.example.com`, `https://www.shop.example.com` | `en/troubleshooting/commerce-store-address-refused.md:33`; `ar/…:31` | **RFC 2606 reserved** example domain. |
| `your-store.myshopify.com` | `en/commerce/connect-shopify.md:81`; `ar/…:77` | **placeholder**. |
| `/wp-admin`, `/wp-json` | WooCommerce articles | **the customer's own WordPress**, not Lynomia infrastructure. |
| `ACTIONS_DISABLED`, `AUTH_INVALID`, `ORDER_CHANGED`, … (15 total) | commerce + troubleshooting articles | **public `Commerce::Error` codes**, machine-readable API values. Correct to publish. |
| `whatsapp_business_messaging`, `whatsapp_business_management`, `write_orders`, `read_only_key` | WhatsApp + commerce articles | **public OAuth scope / permission names**. Correct to publish. |
| Phrases naming secrets — "access token", "webhook secret", "consumer secret", "API key" | ~40 lines across both locales | **prose about credentials**, zero values. `en/automation/agent-bots.md:37`, `en/integrations/webhooks.md:34,80`, `en/commerce/connect-woocommerce.md:43`, `en/whatsapp/connect-whatsapp.md:31,45` are representative. |

**Concepts named, values never shown.** The corpus repeatedly tells a reader they will be asked for a *Phone
Number ID*, a *WhatsApp Business Account ID*, a *permanent access token* and a *webhook verify token*
(`en/whatsapp/connect-whatsapp.md:16,31,45`; `en/getting-started/connect-your-first-channel.md:65`) and never
once shows an example value for any of them. That is the correct pattern and the reason this audit came back
empty. **It should be written down as the rule it evidently already is** — today it is a habit, not a
requirement, and §5 makes it one.

**One disclosure that cannot be redacted.** `X-Chatwoot-Signature`, `X-Chatwoot-Timestamp` and
`X-Chatwoot-Delivery` appear at `en/integrations/webhooks.md:90-92` and `ar/integrations/webhooks.md:86-88`.
These are the real wire header names (`lib/webhooks/trigger.rb:56-60`), so an integrator cannot verify a
signature without them. They disclose the upstream product this installation is built on, in an otherwise
white-labelled public corpus. **Keep them** — a documented header that does not match the wire is worse than
the disclosure — and record the decision so a future branding sweep does not "fix" them and break every
customer's signature check.

---

### F1 — The public documentation portal publishes a named staff byline and avatar on every article, defeating the product's own written policy

**Claim.** Every page under `/docs` renders the article author's real name and avatar image in the page body.
The author is `SuperAdmin.first` for all 124 seeded articles, so one staff member's identity is published
across the entire corpus — and on every category page — as a consequence of row order, not of an editorial
decision.

**Evidence.** The chain is unbroken and every link is cited in §1.2. In short:
`portal_seeder.rb:65` → `base_controller.rb:26-30` → `articles/show.html+documentation.erb:13-14` →
`documentation_layout/articles/_header.html.erb:15-22`, which renders

```erb
<% if article.author.present? %>
    <%= render '…/user_avatar', user: article.author, size: :lg, … %>
      <p class="text-sm font-medium text-n-slate-12"><%= article.author.available_name %></p>
```

and `_user_avatar.html.erb:15` emits `<img src="<%= user.avatar_url %>" alt="<%= name %>" title="<%= name %>" …>`.
Category pages do the same for every distinct author in the category
(`documentation_layout/categories/_header.html.erb:5-10`, `categories_controller.rb:34`,
`portal_helper.rb:119-128`).

The author value comes from the seeder, which defaults it to row order and then pins it permanently:

```ruby
@author = author || SuperAdmin.first || raise(ArgumentError, 'A super admin is required to author documentation')
…
article.author ||= author
```

(`content_seeder.rb:22,79`)

Because `||=` preserves an existing author, the first sync's `SuperAdmin.first` becomes that article's
permanent public byline. No corpus file can change it; `ArticleDashboard::FORM_ATTRIBUTES` omits `author`
(`article_dashboard.rb:36`), so the Super Admin form cannot either.

And the product states this must not happen. `custom/app/helpers/documentation_helper.rb:80-82` and the
decision record at `docs/product-refinement/03-documentation-seo.md:72-74` both say putting a staff member's
name on a public documentation page *"would publish an employee's identity to the whole internet for no
reader's benefit"*. The JSON-LD honours it (`documentation_helper.rb:92`). The HTML two files away does not.

**Impact.** A named individual, with a photograph, is publicly and durably associated with 124 articles they
did not write. Where the super admin has uploaded no avatar, the image is fetched from Gravatar using their
email address (`avatarable.rb:12,21-27`), so the published photo may be a personal one from an unrelated
service. The byline is also simply false as provenance — see F2. Search engines index it; `og:type` is
`article` and the page is explicitly indexable (`documentation_layout/articles/_meta_head.html.erb:35`).

**Severity: major.** Not a blocker only because the published values are a name and an avatar rather than a
credential. It is reachable today, on the live `/docs`, for every one of the 124 published articles.

**Reachable today.**

---

### F2 — No per-article authorship exists anywhere, and the one value a reader sees is wrong

**Claim.** An auditor asking "who wrote this article, when, and from what source?" cannot answer it from any
record this system keeps. The only answer a reader is *given* — the public byline — is false.

**Evidence.** Four places could carry provenance. None does.

| Carrier | What it holds | Evidence |
|---|---|---|
| Front matter | `title`, `description`, `position`, `tags`, `seo_description`, `seo_title` (28 files), `release_date` (2 files). **No `author`. No source. No date.** | Enumerated across all 128 articles; the schema is `content_seeder.rb:94-113` |
| `articles.meta` | `doc_key`, `title`, `description`, `tags`, `version`, `release_date` — SEO and routing only | `content_seeder.rb:106-113` |
| `Custom::AuditLog` | nothing. `Article` has no capture module and no `audited` declaration | §2; `custom/app/models/custom/audit/` holds 14 modules, none for Article |
| `articles.author_id` | `SuperAdmin.first` for every seeded article | `content_seeder.rb:22,79` |

Git history is therefore the only provenance that exists, and what it records is not human authorship. Twenty
commits touch `custom/db/documentation/`. Their authors:

- **13 commits** by `Claude <noreply@anthropic.com>`
- **7 commits** by `Lynomia <import@premiercare.com.kw>`

Per file, the last-touching commit is `Claude` for 63 of the 126 files and `Lynomia` for the other 63 — and
the split does not follow locale (32 EN / 31 AR for one, 31 EN / 32 AR for the other), so it carries no
meaning. Every `Claude` commit carries `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` and a
`Claude-Session:` URL trailer. File dates cluster on three days: 67 files 2026-10-05, 41 on 2026-10-06, 18 on
2026-10-12.

So the honest reading of the record is: **the majority of this corpus was machine-generated, and the remainder
is attributed to a generic organisational identity.** No human reviewer is named for any article.

**Impact.** Three different systems give three different answers to "who wrote this", and all three are wrong
or empty: the public page names a super admin who did not write it, git names a model and a generic identity,
and the audit log is silent. For a corpus that makes normative claims about Meta's APIs, billing behaviour and
error semantics, there is no way to establish who asserted a given sentence, when, or against what source —
which is precisely what a reader needs when an article turns out to be wrong, and what this program's own
evidence rules demand of its agents (`00-program.md` §6.2).

**Severity: major**, as a governance defect rather than a disclosure one.

**Reachable today.**

---

### F3 — A documentation article can be created, edited, published or unpublished with no audit record

**Claim.** The Super Admin authoring surface writes nothing to the audit trail.

**Evidence.** `Article` carries no `audited` declaration and has no module in `custom/app/models/custom/audit/`
(14 modules, none for Article). `config/initializers/audited.rb:3-5` routes the gem at `Custom::AuditLog`, so a
missing declaration means a missing trail, not a default one. `SuperAdmin::ApplicationController`
(`app/controllers/super_admin/application_controller.rb`) adds no capture. `publish` and `unpublish` are bare
status writes:

```ruby
def publish
  requested_resource.update!(status: :published)
```

(`custom/app/controllers/super_admin/articles_controller.rb:10-11`, and `:15-16` for `unpublish`)

The only trace of any change is `articles.updated_at`, which is also what the public page prints as "last
updated" (`documentation_layout/articles/_header.html.erb:2,25`) and what the sitemap uses as `lastmod`
(`app/views/public/api/v1/portals/sitemap.xml.erb:11,17`).

**Impact.** Publishing to a world-readable surface is an unlogged action. If an article appears at `/docs` with
a credential in it, nothing records who published it or when it was changed. This matters more after the
editor upgrade, which adds uploads: a media publish would be equally unlogged.

**Severity: major.** Note that `15-content-quality-audit.md` already records article revision history as
deferred — but that deferral was about *restore and a diff UI*, not about whether the write is recorded at all.

**Reachable today.**

---

### F4 — A screenshot can be embedded as a `data:image` URI, bypassing every media control the program is about to build

**Claim.** An author can put a full screenshot inside a corpus Markdown file as a base64 data URI, and it will
render as a live image on a public page without touching ActiveStorage.

**Evidence.** `CustomMarkdownRenderer#image` sanitises the URL through `sanitized_href`
(`lib/custom_markdown_renderer.rb:61-71`), and `sanitized_href` explicitly allows image data URIs:

```ruby
SAFE_DATA_IMAGE_PATTERN = %r{\Adata:image/(?:png|gif|jpeg|webp)}i
…
return '' if url.match?(DANGEROUS_URL_PATTERN) && !url.match?(SAFE_DATA_IMAGE_PATTERN)
```

(`lib/markdown_renderer_url_sanitizer.rb:4,16`)

So `![Account Health](data:image/png;base64,iVBOR…)` in a corpus file is published verbatim by
`rails documentation:content` and rendered as `<img src="data:image/png;base64,…">`.

**Impact.** This is the control-evasion path that matters for this program specifically. A data-URI screenshot
has no blob, so it is invisible to filename conventions, upload-time validation, blob authorization, an
EXIF-stripping step and any media review queue — every mechanism §5 proposes. It is also committed to git, so
a token visible in the image is permanent in history and survives deletion of the article. And because the
Markdown is the source of truth, a reviewer reading a diff sees only an unreadable base64 blob where a
screenshot's content should be.

**Severity: major.** The allowance is deliberate and correct for its original purpose (agent reply composition);
it is wrong for a world-readable corpus that is about to accept images.

**Reachable today**, and it defeats controls that do not yet exist, so it must be closed *before* the media
work rather than after.

---

### F5 — No image metadata is stripped anywhere in the application

**Claim.** Nothing removes EXIF, GPS, device, software or author metadata from an uploaded image.

**Evidence.** A grep for `exif`, `strip_metadata`, `image_processing` and `vips` across `config/`, `app/`,
`lib/` and `custom/` returns nothing. `config/initializers/active_storage.rb:15-24` removes only three
*internal* ActiveStorage keys (`identified`, `analyzed`, `composed`) from direct-upload metadata — bookkeeping,
not image metadata. `config/application.rb:71` sets `config.active_storage.previewers = []`.
`config/storage.yml` declares no service with `public: true`, so blobs are served through signed URLs, which is
the one good thing here.

**Impact.** A screenshot captured on a staff laptop or phone can carry the capture device, the software, a
timestamp and — for a phone screenshot or a photographed screen — GPS coordinates. A variant generated through
`resize_to_fill` will usually drop most of it as a side effect of re-encoding, but ActiveStorage also serves
the **original** blob, and side effects are not controls. There is no basis today for telling an author "your
metadata is removed", because it is not.

**Severity: major** once images exist; **minor today**, because the corpus contains zero images.

**Only after the editor upgrade.**

---

### F6 — Two naming choices in the corpus are worth changing, neither a leak

**Claim.** `AHMED al-sabah` (`en/conversations/canned-responses.md:64`; `ar/…:59-60`) uses the surname of
Kuwait's ruling family as a capitalisation example, and `#support-watch` (`en/integrations/integrations.md:67`)
reads as an internal channel name even though its context is a customer's own Slack workspace.

**Evidence.** Cited above; both verified as placeholders in §3.1.

**Impact.** Neither discloses anything. The first is a poor choice for a public document in this market; the
second invites a reader — or a future auditor running the same grep I ran — to conclude an internal channel
name was published, costing a re-investigation each time.

**Severity: minor.** Fix when the files are next touched; do not spend a change on them alone.

**Reachable today.**

---

## 4. What the editor upgrade would newly expose

The corpus is text-only today (§3.1), and that is the single fact that makes this audit come back clean. The
program ends that. Everything below follows from images becoming publishable.

**The WhatsApp setup screen is the worst case, and it is one the corpus actively directs authors toward.**
`en/whatsapp/connect-whatsapp.md:31` tells a reader that manual setup asks for a *Phone Number ID, WhatsApp
Business Account ID, a permanent access token*, and `:65-66` describes **Account Health** as reporting *"display
phone number, display name and its review status, phone number status, quality rating, business messaging
limit, throughput, and the business account's name and id"*. A screenshot of either screen, taken against any
real installation, contains in one frame: a permanent system-user access token (`EAA…`, and a permanent one
does not expire), a WABA ID, a phone number ID, a business portfolio name, the display phone number, and the
installation's own hostname in the address bar. A screenshot of a conversation adds a customer's phone number,
their name and the body of their messages. A screenshot of Super Admin adds internal paths — the prior
program's own evidence set shows `/monitoring/sidekiq` and `/widget?website_token=`
(`docs/product-refinement/12-visual-evidence.md`).

**Four control gaps turn that from a hazard into a leak.**

1. **No author-facing rule exists.** There is no README beside the corpus, no CONTRIBUTING, and no guidance in
   the authoring UI. `manifest.yml`'s header comment is the closest thing and no author reads it.
2. **No mechanical check exists.** No CI workflow touches `custom/db/documentation` (all 16 checked), and there
   is no gitleaks/trufflehog/detect-secrets configuration anywhere.
3. **No review step exists.** Publishing is an unlogged status write by any super admin (F3), and the seeder
   force-publishes everything on every run (`content_seeder.rb:101`), so there is no state in which an image is
   present but not yet public.
4. **No metadata stripping exists** (F5), and the data-URI channel bypasses whatever is built (F4).

**Two further exposures specific to the upgrade.** Mounting a rich editor adds pasted HTML and uploads to a
render path with no proven sanitizer (`01-current-system.md` §5; agents 065/081/084 own that). And the author
byline problem compounds: `ArticleAuthorField#to_s` already renders `name · email`
(`custom/app/fields/article_author_field.rb:14`). That is Super-Admin-only today, but it establishes that the
author object in scope of a documentation template carries an email address. One shared partial between the
authoring and public surfaces turns F1 from a name-and-photo disclosure into an email disclosure.

---

## 5. Required controls

Minimum set. Each maps to a mechanism that already exists, per the charter's EXTEND rule. Ordered by what has
to be true before Phase 5 writes a single image.

### C1 — Stop publishing the staff byline (fixes F1)

**The decision to make, not an implementation choice:** the written policy already says documentation is
published by the organisation, not by a person (`documentation_helper.rb:80-82`;
`docs/product-refinement/03-documentation-seo.md:72-74`). Extend that policy from "structured data" to "the
public page", and make the documentation variant's header render the organisation and the date instead of
`article.author`. `_header.html.erb:30-36` already contains the exact no-author branch to fall back to, so this
is a condition change in one partial, plus the equivalent in
`documentation_layout/categories/_header.html.erb:5-12`. **Do not** fix this by clearing `articles.author_id` —
the column is `NOT NULL` by association (`app/models/article.rb`, `belongs_to :author`) and the seeder raises
without an author (`content_seeder.rb:22`).

Scope the change to the `documentation` variant only. The classic Help Center layout serves tenant portals
where a named byline is a tenant's own choice, and `app/views/public/api/v1/portals/_authors.html.erb` and
`articles/index.html.erb` belong to that surface.

### C2 — Record provenance in the file, because the file is the source of truth (fixes F2)

Add three optional front-matter keys and carry them in `meta`, which is the carrier the charter §8.4 already
names and which `meta_for` already builds (`content_seeder.rb:106-113`): `source` (the file, Meta URL or human
the article was written from), `reviewed_by` (the human who checked it — the thing no record holds today), and
`reviewed_on`. They cost one line each in `meta_for` and no migration. `version` is already supported and
unused by every documentation article.

This is also the honest fix for the machine-authorship finding: if 13 of 20 corpus commits are
model-authored, the record should say which articles a human has actually reviewed, per article, rather than
leaving a reader to infer it from git.

Provenance belongs in `meta`, not in a public byline. C1 removes the person from the page; C2 puts the
accountable human in the record. Those are different questions and should not share a field.

### C3 — Audit the article (fixes F3)

Add `custom/app/models/custom/audit/article.rb` following the 14 modules already in that directory — the
pattern is established (`custom/app/models/custom/audit/macro.rb` is the closest shape), `Custom::AuditLog`
already scrubs credentials on write (`audit_log.rb:18,53-57`), and `on: [:create, :update]` with an `only:`
list covering `status`, `content`, `title` and `meta` answers "who published this, and when". A platform
article has no account, so `associated` is correctly absent — which is the arrangement
`Billing::PlanAudit` and `PlatformSupport::AuditWriter` already use and which `Custom::AuditLog`'s own header
documents (`audit_log.rb:21-25`).

### C4 — Close the data-URI image channel (fixes F4)

`SAFE_DATA_IMAGE_PATTERN` exists for agent message composition
(`lib/markdown_renderer_url_sanitizer.rb:4`). `BaseMarkdownRenderer` serves messages and
`CustomMarkdownRenderer` serves articles (`lib/chatwoot_markdown_renderer.rb:6-19`) — they are already separate
classes with separate `image` methods, so the article renderer can refuse data URIs without affecting the
message renderer. **A documentation image must resolve to a blob**, because every other control in this list
depends on there being one.

### C5 — The redaction rule, where an author will actually meet it

The rule itself — **what must never be captured**:

| Never in a published image | Why |
|---|---|
| Any access token, API key, webhook verify token, app secret or consumer secret, in whole or in part | A permanent system-user token does not expire; a partial token confirms a prefix |
| WABA ID, phone number ID, business portfolio name or ID, app ID | Real asset identifiers for a real business |
| Any real phone number, customer name, contact record or message body | Third-party personal data |
| The installation's own hostname, or any internal path — `/super_admin`, `/monitoring`, Sidekiq, Administrate chrome | Internal surface disclosure |
| Any real order number, invoice or ticket reference | Customer business data |
| A real staff name, avatar or email in UI chrome | The same rule as C1 |

**How an author is required to redact: by capturing synthetic data, not by covering real data.** Blur and
black-box are rejected: a blurred token is often recoverable, a box drawn in an image editor can be a separate
layer, and neither leaves a verifiable trace. The required method is the one this repository has already used
and documented — stand up a seeded environment and screenshot that.
`docs/product-refinement/12-visual-evidence.md` records the precedent in detail: `RAILS_ENV=test` on port
3100, a seeded super admin and synthetic fixtures, Playwright at 1440×1000, signed in through the real Devise
form. **Extend that protocol; do not invent a second one.** It also already documents the two environment
artefacts an author must expect (an unbranded `INSTALLATION_NAME`, and the `/widget?website_token=` 404),
which is exactly the kind of note that stops a capture being read as a product defect.

Where the rule lives, so an author follows it — three places, because one is not enough:

1. **`custom/db/documentation/README.md`**, beside the corpus, as the normative rule. This is the file a writer
   opens the directory and sees, and there is no such file today. It states the table above, the capture
   protocol, the filename convention (C6), and the alt-text requirement.
2. **The Super Admin authoring form**, as a short hint on the media field when one exists — the point of use.
   `custom/app/fields/` and `custom/app/views/fields/` already hold two custom fields for this dashboard, so
   there is a place for it.
3. **The Phase 5 writer brief**, so the twenty implementation agents are bound by it the way Phase 1 agents are
   bound by `00-program.md` §6.

### C6 — What can be verified mechanically, and what cannot

The brief asks this directly, and the honest answer is split.

**Mechanically enforceable:**

| Check | Mechanism to extend |
|---|---|
| No `data:` image in any corpus file | A file-level grep; CI, plus C4 at render time |
| Filename convention — every image matches `^[a-z0-9-]+\.(png\|webp)$` under a per-section media directory | File-level, CI |
| EXIF/GPS/device metadata absent from every committed image | `exiftool`/`vips` in CI; **and** a strip-on-upload step, since C4 forces images through a blob |
| Alt text present on every image | Parse the Markdown; `CustomMarkdownRenderer#image` already renders `alt` from children (`custom_markdown_renderer.rb:66`) |
| No token-shaped string, email, IPv4 or long digit run in any corpus file | The scan in §3.1, run as a gate rather than once by an agent |
| No absolute URL pointing at this installation's own host | File-level, CI |

**Not mechanically enforceable, and must not be claimed as such:** whether the *pixels* contain a credential.
OCR is the tempting answer and it is not a control — it misses rotated, low-contrast, partially occluded and
ligature-rendered text, and a token that OCR fails to read is still a token a human can read. **OCR is useful
as a pre-commit warning and must never be the gate.** The gate for image content is a human review step: one
named reviewer who is not the author confirms each image was captured against synthetic data, recorded in the
`reviewed_by` field C2 adds.

**Where the automated gate runs.** No CI workflow touches the corpus today, and `lynomia:docs:seo_audit` is the
established pattern for a corpus gate: read-only, exits 1 on an ERROR so it can gate a deploy, warnings do not
fail it (`lib/tasks/documentation_seo_audit.rake:1-11`). The file-level checks above are facts about **files**,
not about seeded data, so unlike the SEO audit they belong in **CI on the pull request** — before the content
is committed, which is the only point at which a leaked token is still recoverable. A sibling
`lynomia:docs:media_audit` task can cover the blob-side checks (metadata, alt text) on the server, in the same
namespace and with the same exit-code contract.

---

## 6. What I did not check

- **Whether the published `SuperAdmin.first` is a real person on the live installation.** I did not and must
  not touch production data. F1 holds regardless: whoever that row is, their name and avatar are published.
  The *severity* depends on who it is, and an operator can answer that in one query.
- **Whether any image already exists in an ActiveStorage blob attached to a documentation article.** I read
  configuration and the corpus, not the database. The corpus references no image, and no authoring surface can
  attach one (`article_dashboard.rb:36`), so the expected answer is none.
- **Whether `vips` strips EXIF on variant generation in this deployment.** Irrelevant to F5's conclusion: the
  original blob is servable and nothing strips metadata on upload, so variant behaviour is not a control
  either way.
- **The sanitizer question.** `01-current-system.md` §5 is right that it is the program's most important
  security question, and agents 065, 081 and 084 own it. F4 is about an image URL the sanitizer *deliberately
  allows*, which is a separate finding from whether raw HTML is escaped.
- **Git history as a disclosure surface.** `import@premiercare.com.kw` and `Claude-Session:` URLs are in commit
  metadata. Commit history is not served at `/docs` and is not in my scope; I note it only so the orchestrator
  knows it was seen and deliberately not treated as a corpus finding.
