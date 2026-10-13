# R2 — the documentation media contract, frozen

Freezes the twelve items the owner named, on ruling R2 (`08-orchestrator-rulings.md`) and agent 066's Option D.
ActiveStorage is the storage and serving mechanism: **no DAM, no second asset pipeline, no parallel media
system.** Nothing here is implemented yet — this is the contract the implementation is held to.

Every fact below is either a `file:line` I read, a no-exclusion search I classified, or a value I printed at
runtime. Where I could not close a question it says **BLOCKED** and names what would close it. Absence claims
follow `00-program.md` §2.3.

---

## 0. Four facts that changed the design, none of them in ruling R2

### 0.1 The delivery predicate is NOT "published" — a super admin is served unpublished articles on the public route

`app/controllers/public/api/v1/portals/articles_controller.rb:83-86`:

```ruby
def set_article
  scope = previewing_as_super_admin? ? @portal.articles : @portal.articles.published
  @article = scope.find_by!(slug: permitted_params[:article_slug])
end
```

`previewing_as_super_admin?` is `respond_to?(:current_super_admin) && current_super_admin.present?` (`:88-91`),
exposed as a `helper_method`. This is a designed feature, not an oversight: the comment at `:80-82` calls it
"the whole point of a preview", a purpose-built draft banner renders in **all three** layout variants
(`show.html.erb:6`, `show.html+plain.erb:6`, `show.html+documentation.erb:6`), and the Super Admin preview
button routes straight into it (`custom/app/controllers/super_admin/articles_controller.rb:22-25`).

**So a media predicate of "published only" would render the one surface whose entire purpose is pre-publication
review with broken images.** The predicate is frozen as **published OR the requester is a signed-in super
admin**, matching `set_article` exactly rather than inventing a second rule.

An inconsistency this contract does **not** inherit: `show_markdown` (`:29-33`) is
`return head :not_found unless @article&.published?`, so it refuses a draft **even to a super admin**, while
`show` serves it. The two public surfaces already disagree. Media follows `show`, and the disagreement is
recorded as **R2-O1** rather than silently copied or silently fixed.

### 0.2 There are TWO platform portals, so "attached to the platform Portal" was ambiguous

`Documentation::Library::SLUGS` is `[DOCS_SLUG, CHANGELOG_SLUG]` (`custom/app/services/documentation/library.rb:9-11`)
and `ContentSeeder.changelog` (`content_seeder.rb:16-18`) runs a **second** seeder over `CHANGELOG_ROOT` bound to
`changelog_portal!`. Both are `Portal.platform.active`.

Frozen: **the `media:` key namespace is per-portal.** A key resolves only against the portal currently
rendering. The docs corpus and the changelog corpus each seed their own media, and an identical file used by
both is stored twice — two blobs, one per portal. Deduplication across portals is explicitly rejected: it would
make one corpus's purge able to break the other's article, and the corpus is the source of truth, not the blob
table.

### 0.3 There is a THIRD renderer, and alt text is a public SEO field because of it

`ChatwootMarkdownRenderer#render_markdown_to_plain_text` (`lib/chatwoot_markdown_renderer.rb:21-23`) sits eight
lines below `render_article` and has two production consumers:

| Consumer | file:line | Surface |
|---|---|---|
| `PortalHelper#render_category_content` | `app/helpers/portal_helper.rb:97` | public category description |
| the public search payload | `app/views/public/api/v1/models/_search_article.json.jbuilder:1` | **public `articles.json` `content` field** |

`CommonMarker#to_plaintext` **emits an image's alt text and discards its URL**. Two consequences, both frozen:

1. **Alt text is a public, user-visible SEO/snippet field**, not only an accessibility attribute. "Required at
   the seed boundary" is therefore load-bearing twice over, and an empty alt silently degrades the public
   search snippet.
2. **A `media:` key never leaks into a snippet** through this path, because the URL is discarded. That is the
   one piece of good news in this section and it is why the plain-text path needs **no** resolver.

### 0.4 The live CSP is enforcing and has no `img-src`

`config/initializers/content_security_policy.rb:15-18` installs exactly `object_src :none` and `base_uri :self`
— deliberately stage one, with `script-src`/`style-src`/`frame-ancestors` documented as future work in the same
file. So there is **no `img-src` to constrain where a documentation image may load from**, which is an
independent reason to prefer **same-origin app-owned delivery** over anything that redirects to a storage host:
the only protection against a foreign image origin today is the renderer's own URL handling.

---

## 1. The twelve frozen items

| # | Item | Frozen decision |
|---|---|---|
| 1 | **Ownership** | `has_many_attached :documentation_media` on **`Portal`**, per-portal namespace (§0.2). Portal rather than Article for the four reasons in `P2-RULINGS-IMPLEMENTATION.md` R2-F1 — **not** for the reason ruling R2 gave, which is false and withdrawn there |
| 2 | **Authorization** | No tenant path at all (item 12). Read authorization is the **delivery predicate** of item 3, not a policy: media is as readable as the article that references it |
| 3 | **Public published delivery** | An **app-owned, same-origin** route that resolves a `media:` key for a portal + article, applies the §0.1 predicate, and streams the blob. **Never** a `rails_blob_*` redirect URL and **never** a signed id in a public page. Cache `public, max-age` only when the article is published; `private, no-store` on a super-admin draft preview. **BLOCKED on one owner read** — see §3 |
| 4 | **Unpublished media behaviour** | Published article → cacheable to anyone. Unpublished article → served **only** to a signed-in super admin, uncacheable, per §0.1. A key belonging to no article in the rendering portal → 404, never a redirect |
| 5 | **Upload type/size limits** | Enforced at the **seed boundary**, the earliest shared entry point: content type in `{png, jpeg, gif, webp}`, a byte cap, raster only. **No SVG** — and the mechanism that already forces SVG to `octet-stream` + `attachment` is also the stored-XSS defence (083 F11), so it is not to be relaxed |
| 6 | **Image lifecycle** | Seeded from the repository, idempotent per §2. Originals only, **no variants** — variant generation is what makes the whole product's boot depend on libvips (066 R2), and `config.active_storage.previewers = []` is already set (`config/application.rb:71`) |
| 7 | **Alt text / caption model** | **Alt required**, enforced at the seed boundary; an empty alt fails the seed rather than publishing an inaccessible image and an empty public snippet (§0.3). A decorative image declares itself explicitly. Captions are **out of scope for R2** and belong to R3's editor, because nothing in the markdown source model represents one today |
| 8 | **Replacement / removal semantics** | Same key, changed bytes → new blob attached, old one purged **after** the new attachment succeeds. Key removed from the corpus → blob purged on the next seed. Purge is never implicit in an article rewrite |
| 9 | **Orphan cleanup** | Owned by the seeder, not a background job: after a run, any `documentation_media` attachment on the portal whose key no longer appears in that portal's corpus is purged, and the run reports the count. **Nothing cleans unattached blobs in this app today**, which is why ownership (item 1) is what makes cleanup possible at all |
| 10 | **Stable references from article content** | `![alt](media:<section>/<key>/<name>.png)` in the Markdown. **Never a URL, never a signed id, never a blob id** — an ActiveStorage signed id is a verifier over the blob primary key keyed from `secret_key_base`, so a committed URL is valid in exactly one database |
| 11 | **Draft / publish behaviour** | Media seeds with the article regardless of status; **visibility** is item 4's predicate. A draft's media is never cacheable and never public |
| 12 | **No tenant authoring path** | Frozen as a **standing rule, not an observation**: any new `Portal`/`Article`/`Category` policy action lands a `false` override in `custom/app/policies/custom/*` **in the same commit**, and the prepend-order assertion at `spec/requests/custom/tenant_help_center_removal_spec.rb:144` is extended to cover it. The reason is in §2.3 below |

### 1.1 Why item 12 is a rule and not a finding

`custom/app/policies/custom/portal_policy.rb:25-34` is an **enumerated deny list, not default-deny**. A new
action with no matching override falls through to upstream and is permitted. So the moment an upstream merge
adds, say, `PortalPolicy#media?`, that action is granted to every tenant administrator **and every existing
spec keeps passing**. "The policy already denies it" is a fact about today, not a guarantee. The rule above is
the guarantee.

### 1.2 What keeps permanent signed-id URLs off the public documentation pages today

`Article#public_author` (`app/models/article.rb:173-175`) — `author unless platform_owned?` — returns nil for
every platform documentation article, and **eight** render sites select through it
(`documentation_layout/articles/_header.html.erb:16`, `concerns/portal_home_data.rb:62`,
`categories_controller.rb:38`, `portals/_authors.html.erb:3`, `portals/articles/index.html.erb:19`,
`models/_article.json.jbuilder:30`, and the two plain variants). Author avatars are the one existing
ActiveStorage **representation** on these pages, and a representation URL carries a permanent signed id.

Recorded here because a change to `public_author` republishes eight render sites at once and would put a
permanent signed id on a public documentation page. It is the real protection; the freeze names it so the next
reader does not have to rediscover it.

---

## 2. Implementation shape

1. **Corpus**: `custom/db/documentation/media/<section>/<key>/<name>.png`, beside the Markdown, reviewed in diffs.
2. **Seed**: `Documentation::ContentSeeder` uploads each referenced file, idempotently, by comparing the
   candidate's checksum against the **portal's own existing attachments** — which `active_storage_attachments`
   already indexes by `(record_type, record_id, name, blob_id)`. **Not** a global `Blob.find_by(checksum:)`:
   `active_storage_blobs` carries only `index_active_storage_blobs_on_key`, so a global lookup scans every
   attachment the product has ever stored (measured; `P2-RULINGS-IMPLEMENTATION.md` R2-F2).
3. **Resolve**: at render time, per call, in the article render path only. **Never** by setting
   `config.active_storage.resolve_model_to_route` — it is unset today, so the framework default
   `:rails_storage_redirect` applies, and flipping it would move avatars, portal logos, chat attachments, macro
   and automation files and exports to the proxy route all at once.
4. **Emit**: `width`/`height` from `blob.metadata` plus `loading="lazy"` and `decoding="async"`, following
   `app/models/attachment.rb:129-130`.
5. **Route**: must not be shadowed by the two literal path suffixes already claimed on the article route —
   `.png` for the tracking pixel (`config/routes.rb:516`) and `.md` for `show_markdown` (`:517-518`).

### 2.1 The `data:image/*` closure belongs to R2, and this arbitrates four conflicting proposals

`lib/markdown_renderer_url_sanitizer.rb:4` permits `data:image/{png,gif,jpeg,webp}`. Agent 087 called it F4,
"must be closed before Phase 5 writes a single image"; it is also K6. The inventory handed back **four
different owners for the same two-line change** — R2, before-R3, the R9 content gate, and one slice that read
the same sanitizer as purely protective and proposed no closure at all.

**Arbitration: it closes in R2, scoped to the article renderer only.** Three reasons. The owner's accepted "no
universal sanitizer" ruling eliminates every global variant. A `data:` image bypasses **every** control item 5
freezes, by construction, and is permanent once committed to git — so it cannot outlive the contract that
replaces it. And §0.4 is decisive: with no `img-src` in the enforcing CSP, nothing else constrains where an
article image may come from.

---

## 3. RESOLVED — production storage, measured by the owner

```
service=:local
class=ActiveStorage::Service::DiskService
urls_expire_in=nil
resolve_model_to_route=:rails_storage_redirect
```

`config/storage.yml:5-7` gives the `local` service root as `Rails.root.join("storage")`. So production media
would be plain files under the application directory on one host.

**Three rules this adds to the contract.**

- **3.1 Freeze against ActiveStorage abstractions, never DiskService internals.** The implementation uses
  `attachment.blob`, `blob.download` / `blob.open`, `blob.content_type`, `blob.byte_size`, `blob.checksum`,
  `blob.metadata`. It must **never** touch `ActiveStorage::Blob.service.path_for`, `service.root`, a
  `storage/` path, or anything else that only exists on `DiskService`. Moving to S3 or any object store must
  then be an ENV change with **no change to the documentation content model** — the `media:` key, the corpus
  layout and the resolver are all backend-independent by construction.
- **3.2 No raw filesystem path is ever exposed.** Not in a URL, not in a page, not in an API response, not in
  a log line, not in an error message. The app-owned route takes a portal, an article and a key; the filesystem
  is behind `blob`.
- **3.3 `urls_expire_in=nil` is a measured runtime fact and nothing more.** It is **not** the source of the
  authorization semantics. Those come from the traced controller behaviour: every ActiveStorage controller
  inherits `ActiveStorage::BaseController`, whose only concerns are `SetCurrent` and `protect_from_forgery`
  (`activestorage-7.2.3.2/app/controllers/active_storage/base_controller.rb:4-10`) — **no authentication, no
  policy call, and no application override adds any**. That, not the expiry setting, is why delivery is
  app-owned.

**No storage migration in R2.** The backend stays `:local`.

---

## 3A. Backup and restore — the operational gap, traced rather than assumed

**A PostgreSQL backup alone is insufficient.** An ActiveStorage attachment is two things: rows in
`active_storage_blobs` / `active_storage_attachments`, and an object in the service. Restoring only the database
yields rows whose bytes are gone — every `media:` key resolves to a blob record whose file is missing, so every
documentation image 404s while the article still renders. Restoring only the files yields orphans nothing
references. **The two must be backed up and restored consistently, as one unit.**

### 3A.1 What the repository actually implements

Searched with no exclusion filter and every hit classified, per `00-program.md` §2.3:

| Place | What is there |
|---|---|
| `deployment/deploy.sh:126-130` | stage 2 is **`pg_dump` only** — one `.dump` into `BACKUP_DIR` (`/var/backups/lynomia`, `:33`), retained `KEEP_BACKUPS=14` (`:36`, pruned at `:450`). **No `storage/`, no rsync, no tar, no object copy** |
| `deployment/ROLLBACK.md`, `deployment/INCIDENT.md` | **zero mentions** of storage, ActiveStorage, attachment or blob. The rollback runbook does not cover media at all |
| `deployment/setup_18.04.sh`, `setup_20.04.sh` | install no backup tooling. One prose line, `setup_20.04.sh:977`, "Always backup your database before proceeding" |
| `config/schedule.yml`, `config/sidekiq.yml` | nothing backs anything up. **A claim I made here was wrong and is corrected in §3A.3**: `sidekiq.yml:31-32` name queues that nothing enqueues to |
| `deployment/*.service`, `*.target` | no mount, no snapshot, no `ReadWritePaths` for storage |
| `.gitignore:59` | `/storage` — so it is not in the repository either |
| **`docker-compose.production.yaml:8,61`** | **does** mount `storage_data:/app/storage` as a named Docker volume. Not nothing, and worth recording: on a Docker topology the bytes live in a Docker volume rather than a host directory. Production is the **systemd** topology (`deploy.sh` + `chatwoot*.service` + `/var/backups/lynomia`), so the host-directory case is the live one and the compose file matters only if the topology changes |

**Claim, scoped exactly as the evidence supports it: the repository implements no backup of `storage/`.**

**What this evidence cannot settle, and I will not claim either way:** a backup outside the repository — a
hypervisor or volume snapshot, a filesystem-level agent, a hand-written cron on the host. None of that is
visible from repository evidence. The owner's point 5 was right to warn against inferring absence from the
`pg_dump`, and the honest boundary is that the repository implements none while the host may.

### 3A.3 CORRECTION — `purge_later` does not run on the queue I said it did

I wrote above that `config/sidekiq.yml:31-32` carry the `active_storage_analysis` and `active_storage_purge`
queues "so `purge_later` really is processed". **The conclusion holds and the reason was wrong.** Agent 1
caught it; I verified the chain myself:

| Step | Evidence |
|---|---|
| The job asks the config for its queue | `activestorage-7.2.3.2/app/jobs/active_storage/purge_job.rb:5` — `queue_as { ActiveStorage.queues[:purge] }` |
| `load_defaults "6.0"` sets the named queues | `railties-7.2.3.2/lib/rails/application/configuration.rb:174`, inside `when "6.0"` which begins at `:157` |
| `load_defaults "6.1"` then sets both to **nil** | same file `:205`, inside `when "6.1"` which begins at `:180` |
| This app loads 7.0, which chains down through 6.1 | `config/application.rb:39` — `config.load_defaults 7.0`; `when "7.0"` begins at `:218` |
| No application override | a no-exclusion search for `active_storage.queues`, `queues[:purge]` and `queues[:analysis]` across `config/ app/ custom/ lib/` returns nothing |

So `ActiveStorage.queues[:purge]` is **nil**, `queue_as { nil }` falls through to ActiveJob's default, and the
job runs on **`default`**. `purge_later` is therefore processed — because `default` is processed — but
**`config/sidekiq.yml:31-32` are dead queue names**, and anyone watching them for purge throughput would be
watching an empty queue.

Kept visible rather than edited away, per the program's rule on withdrawn claims.

### 3A.2 The smallest safe addition — designed, NOT applied

Not applied, and not to be applied without separate approval. Recorded so the decision is costed:

1. **Back the files up in the same stage as the database, so the two cannot drift.** `deploy.sh` stage 2
   already computes `STAMP` and `PREVIOUS_SHA` and already checks free space on `BACKUP_DIR`'s filesystem
   (`:71-81`). One `tar` of `$APP_DIR/storage` into `$BACKUP_DIR/$STAMP-pre-deploy-$PREVIOUS_SHA-storage.tar.zst`,
   immediately after the dump, inherits the same stamp, the same retention prune and the same ERR trap.
2. **Order matters for consistency: files first, then the database.** A file present with no row is an orphan
   the seeder reclaims; a row present with no file is a broken published page. So capture files *before* the
   dump if they are captured in one stage, and state that in `ROLLBACK.md`.
3. **The free-space check must grow with it.** `:78-79` demands 2 GB for a dump; a media corpus makes that
   figure wrong, and the check must measure `du -s storage` rather than assume.
4. **`ROLLBACK.md` gains a media section**: restoring the dump without the matching storage archive leaves
   every documentation image broken, and the two archives share a stamp precisely so an operator can pair them.
5. **The alternative that removes the problem rather than managing it** is moving the service to S3 or an
   S3-compatible store, which is ENV-only (`config/storage.yml:10-16,33-40`) and is what §3.1 keeps possible.
   That is a bigger operational decision than R2 and is explicitly **not** proposed here.

Until one of those is approved, **R2-O4 is confirmed as an open operational gap**, not a solved problem, and
this contract says so rather than implying the media is safe.

---

## 4. Open, recorded rather than decided

| # | Open item |
|---|---|
| **R2-O1** | `show_markdown` refuses a draft to a super admin while `show` serves one. Media follows `show`. Whether `show_markdown` should change is a product question, not a media one |
| **R2-O2** | Captions have no representation in the Markdown source model. Deferred to R3 with the editor, not invented here |
| **R2-O3** | Responsive variants need `config.active_storage.web_image_content_types` set explicitly, which is product-wide and affects avatars and message thumbnails. Out of scope; originals only |
| **R2-O4** | **CONFIRMED.** Production storage is local disk (`:local` / `DiskService`, root `Rails.root.join("storage")`), in a `.gitignore`d directory, and the repository implements no backup of it (§3A). A media corpus multiplies what a host rebuild or a database-only restore loses. The smallest safe addition is designed in §3A.2 and **not applied** |
