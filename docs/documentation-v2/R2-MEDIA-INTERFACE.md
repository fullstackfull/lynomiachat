# R2 — the documentation media INTERFACE (the code-level half)

Agent 1, wave 1. This is the interface **only**: nothing here is implemented, the media directory is not
created, and the sanitizer is not touched. It is the half of R2 that Agent 2 codes the editor's
image-insertion UI against and Agent 3 writes `media:` references against, before any of it exists.

The **contract** is `R2-MEDIA-CONTRACT.md` and is frozen. Where this document is more specific it is because
the contract left the code shape open; where it *corrects* the contract it says so explicitly in §0 rather
than diverging quietly. Nothing here contradicts the contract's twelve frozen items.

Gem citations are to the versions `Gemfile.lock` pins: `actionpack`/`activejob`/`activestorage`/`railties`
**7.2.3.2** (`Gemfile.lock:24,51,62,734`), `commonmarker` **0.23.12** (`:174`).

**Postgres is down in this container** (`pg_isready` → `/var/run/postgresql:5432 - no response`), so nothing
below rests on a database probe. Every fact is a `file:line` I read or a no-database Ruby probe whose exact
output is quoted. Facts I could not settle are marked **UNVERIFIED** with the one thing that would settle them.

---

## 0. Nine things I measured this wave that shape the interface

Five of these were not in ruling R2 or in the contract, and two correct the contract.

### 0.1 The corpus contains zero images today, so this interface has no legacy to be compatible with

No-exclusion search over both corpora:

```
git grep -n '!\[' -- custom/db/documentation custom/db/changelog   # 0 hits
git grep -n 'data:'  -- custom/db/documentation custom/db/changelog # 1 hit
```

The single `data:` hit is `custom/db/documentation/en/commerce/connect-zid.md:13` — the English prose
"no order data: they say which customer changed", not a URL. 128 Markdown files
(`find custom/db/documentation custom/db/changelog -name '*.md' | wc -l` → `128`).

**Consequence**: the grammar below is a greenfield grammar. There is no existing reference to migrate and no
back-compatibility shape to honour. Every rejection rule in §1 can be strict from the first commit.

### 0.2 `media:` survives CommonMark parsing and `escape_href` byte-identical — measured

Probe (no Rails, no database), rendering `![alt](<key>)` through a `CommonMarker::HtmlRenderer` subclass that
applies the production sanitizer's two constants and then the gem's own `escape_href`:

```
IN  "media:whatsapp/connect-number/step-2.png"
OUT RAW="media:whatsapp/connect-number/step-2.png" ESCAPED="media:whatsapp/connect-number/step-2.png"
IN  "media:a/b/c/d.png"
OUT RAW="media:a/b/c/d.png"                        ESCAPED="media:a/b/c/d.png"
IN  "MEDIA:Whatsapp/Step.PNG"
OUT RAW="MEDIA:Whatsapp/Step.PNG"                  ESCAPED="MEDIA:Whatsapp/Step.PNG"
IN  "media:"
OUT RAW="media:"                                   ESCAPED="media:"
```

`media:` is not in `DANGEROUS_URL_PATTERN` (`lib/markdown_renderer_url_sanitizer.rb:3`), so `sanitized_href`
(`:14-19`) passes it through, and `escape_href` percent-escapes neither `:` nor `/`. **The renderer therefore
sees the key exactly as the author typed it**, and the resolver can parse it without un-escaping anything.

### 0.3 A destination containing a space is NOT an image node at all — measured, and it is a silent failure

```
IN  "media:whatsapp/connect-number/step 2.png"
OUT ![alt](media:whatsapp/connect-number/step 2.png)      <- literal text, no image node
```

CommonMark requires `<...>` around a destination containing a space. An author who names a file
`step 2.png` does not get a broken image — they get the Markdown source printed into the published page, and
`CustomMarkdownRenderer#image` (`lib/custom_markdown_renderer.rb:62-72`) is never called, so **no resolver
can detect it**. This is the single strongest reason the space ban in §1 must be enforced at the seed
boundary, where the raw bytes are still visible, rather than at render time.

### 0.4 `cw_image_width` cannot ride on a `media:` key — measured, and it breaks the editor's existing resize

```
IN  "media:x.png?cw_image_width=400px"
OUT RAW="media:x.png?cw_image_width=400px"  URI.query=nil  URI.opaque="x.png?cw_image_width=400px"
```

`CustomMarkdownRenderer#extract_image_width` (`:131-133`) → `query_param` (`:135-140`) reads
`URI.parse(src).query`. For a `media:` URL Ruby's RFC 3986 parse puts the whole remainder in `opaque` and
leaves `query` **nil**, so the `?...` is part of the key and the width is never read.

**Consequence, and it is the most important single fact for Agent 2**: the editor's existing drag-resize
mechanism — which encodes the chosen width as `?cw_image_width=400px` on the URL, the same mechanism
`BaseMarkdownRenderer#extract_image_sizing_style` (`lib/base_markdown_renderer.rb:24-31`) uses for replies —
**does not work on a `media:` key**. §1 therefore rejects a query string outright and §2 makes the resolver
the only source of dimensions.

### 0.5 `active_storage_blobs.metadata` is a `text` column, not `jsonb` — this settles the resolver's shape

`db/schema.rb:99-109`:

```
t.string "key",      null: false     # index_active_storage_blobs_on_key (:108), UNIQUE -- ActiveStorage's own storage key
t.string "filename", null: false     # no index
t.text   "metadata"                  # :103 -- TEXT
t.string "checksum"                  # no index
```

and `ActiveStorage::Blob` declares
`store :metadata, accessors: [ :analyzed, :identified, :composed ], coder: ActiveRecord::Coders::JSON`
(`activestorage-7.2.3.2/app/models/active_storage/blob.rb:31`).

So metadata is application-serialized JSON in a text column: **there is no `metadata->>'…'` operator to query
with.** Combined with R2-F2 (`P2-RULINGS-IMPLEMENTATION.md`: the only blob index is on `key`), the *only*
indexed access path to this portal's media is the attachments uniqueness index
`(record_type, record_id, name, blob_id)` (`db/schema.rb:96`, UNIQUE).

**Consequence**: the resolver cannot look a key up in SQL. It loads the portal's `documentation_media` set
once and indexes it in memory. That is not a compromise — it is the only indexed design, and it is why the
answer to "what is the N+1 risk for twenty images" is "there is none, by construction" (§2.4).

### 0.6 CORRECTION to contract §3A.1 — `purge_later` runs on the `default` queue, not `active_storage_purge`

The contract's parenthetical says `config/sidekiq.yml:31-32` carries the `active_storage_analysis` and
`active_storage_purge` queues "so `purge_later` really is processed". **The conclusion is right and the stated
reason is wrong**, and under this program's own R2-F1 lesson a conclusion resting on a false reason has to be
re-stated rather than repeated. The chain, read end to end:

| Step | Evidence |
|---|---|
| App loads 7.0 defaults | `config/application.rb:39` — `config.load_defaults 7.0` |
| `"7.0"` recurses into `"6.1"` | `railties-7.2.3.2/lib/rails/application/configuration.rb:218-219` |
| `"6.1"` recurses into `"6.0"` | `:180-181` |
| `"6.0"` sets the named queues | `:173-174` — `queues.analysis = :active_storage_analysis`, `queues.purge = :active_storage_purge` |
| `"6.1"` then sets both to **nil**, *after* 6.0 ran | `:204-205` — `queues.analysis = nil`, `queues.purge = nil` |
| Nothing in this repo overrides them | no-exclusion `git grep -n "active_storage.queues\|ActiveStorage.queues\|queues.purge\|queues.analysis"` → two hits, both in `docs/documentation-v2/discovery/066-activestorage.md:510-511`; **zero in `config/`, `app/`, `custom/`, `lib/`** |
| The jobs read that nil | `activestorage-7.2.3.2/app/jobs/active_storage/purge_job.rb:5` — `queue_as { ActiveStorage.queues[:purge] }`; `analyze_job.rb:5` likewise |
| ActiveJob falls back to `"default"` | `activejob-7.2.3.2/lib/active_job/queue_name.rb:47-51` — `queue_name = part_name \|\| default_queue_name`; `:9` — `default_queue_name, default: "default"` |
| `default` is a processed Sidekiq queue | `config/sidekiq.yml:21` |

**Restated for this interface**: `blob.purge_later` is really processed, because `ActiveStorage::PurgeJob`
enqueues on **`default`** (`config/sidekiq.yml:21`), not because of `:31-32`. The two queue names at
`config/sidekiq.yml:31-32` are **dead under this configuration** — nothing enqueues to them. Agent 066 found
the same nil-queue fact first (`discovery/066-activestorage.md:510-511`); it did not reach the contract.

This changes nothing about §6's semantics. It does mean an operator watching `active_storage_purge` for purge
progress will watch an empty queue forever, which is worth one line in the runbook (REQUESTED CHANGES #5).

### 0.7 Image analysis depends on **libvips**, not ImageMagick, and its failure is silent

| Step | Evidence |
|---|---|
| `load_defaults 7.0` sets `variant_processor = :vips` | `railties-7.2.3.2/lib/rails/application/configuration.rb:254` |
| Nothing in the repo overrides it | no-exclusion `git grep -n "variant_processor"` over `config Gemfile Gemfile.lock` → zero hits in `config/` |
| Default analyzer list | `activestorage-7.2.3.2/lib/active_storage/engine.rb:30` |
| Vips analyzer accepts only when the processor is `:vips` | `lib/active_storage/analyzer/image_analyzer/vips.rb:9-11` |
| ImageMagick analyzer accepts only when the processor is `:mini_magick` | `image_magick.rb:7-9` — so it **never runs here** |
| A missing libvips is swallowed | `vips.rb:14-20` — `rescue LoadError` → `logger.info "Skipping image analysis…"` → `return {}` |
| Analysis merges, so it cannot clobber our key | `app/models/active_storage/blob/analyzable.rb:29-31` — `update! metadata: metadata.merge(...)` |
| Attaching triggers it asynchronously | `app/models/active_storage/attachment.rb:127` — `blob.analyze_later unless blob.analyzed?` |

Measured in **this container**: `bundle exec ruby -e 'require "ruby-vips"'` → `VIPS_REQUIRE=ok
version=8.15.1`, and `ldconfig -p | grep -c vips` → `2`. `/usr/bin/convert` and `/usr/bin/identify` exist but
are irrelevant, because the ImageMagick analyzer never accepts.

**UNVERIFIED: whether libvips is installed on the production host.** What would settle it: `ldconfig -p |
grep vips` on production, or one `rails runner` printing
`ActiveStorage::Analyzer::ImageAnalyzer::Vips.accept?(some_png_blob)`. If it is absent, every seeded image
gets `metadata` with no `width`/`height`, the `<img>` ships without dimensions, and the only symptom is layout
shift plus one `info` log line. §3 therefore makes the seeder analyze **synchronously and report the count it
could not measure**, so a missing libvips is a visible seed output rather than a silent SEO regression.

### 0.8 The bare ActiveStorage direct-upload route answers 403 — so the editor cannot upload, by design

`config/initializers/active_storage.rb:52-63` installs `ActiveStorageBareDirectUploadGuard`, whose
`reject_bare_direct_upload` is `head :forbidden if instance_of?(ActiveStorage::DirectUploadsController)`,
included at `:71-73`. The two legitimate direct-upload endpoints are the account-scoped ones
(`config/routes.rb:129`, `:381`).

**Consequence for Agent 2**: there is no upload path available to a Super Admin editor in R2, and adding one
is not in Agent 2's ownership. Contract item 6 already says media is "seeded from the repository" — so the
editor's job is **inserting a reference to a key that already exists**, never uploading bytes. §8 states this
as a hard boundary.

### 0.9 Only **two** of the three renderers pass through `MarkdownRendererUrlSanitizer`

The task brief says "there are three renderers on `ChatwootMarkdownRenderer`, including
`render_markdown_to_plain_text`". There are three *entry points*, but the third uses no Ruby renderer class at
all: `render_markdown_to_plain_text` is `CommonMarker.render_doc(@content, :DEFAULT).to_plaintext`
(`lib/chatwoot_markdown_renderer.rb:21-23`) — the C library's own plaintext writer. It does not instantiate
`CustomMarkdownRenderer`, does not instantiate `BaseMarkdownRenderer`, and therefore **cannot be affected by
any change to `lib/markdown_renderer_url_sanitizer.rb`**. That is load-bearing for §7's blast radius and is
stated here so §7 is not read as hand-waving.

---

## 1. The `media:` key grammar

### 1.1 The literal form in Markdown

```markdown
![Step 2: paste the permanent token into the Token field](media:whatsapp/connect-number/step-2.png)
```

That is the **only** accepted form. The alt text is the bracket content and is required (§5). There is no
front-matter-only form, no reference-style form (`![alt][ref]` + `[ref]: media:…`), and no HTML `<img>` form —
raw HTML is dropped because `render_article` parses with `:DEFAULT` (`lib/chatwoot_markdown_renderer.rb:15`).

### 1.2 The key

```
key    ::= segment ( "/" segment )* "/" filename
segment::= [a-z0-9]([a-z0-9-]*[a-z0-9])?
filename::= [a-z0-9]([a-z0-9-]*[a-z0-9])? "." ext
ext    ::= "png" | "jpg" | "jpeg" | "gif" | "webp"
```

- **Allowed characters**: lowercase `a-z`, digits `0-9`, hyphen `-`, the `/` separator, and exactly one `.`
  before the extension. Nothing else.
- **Lowercase only, and case-sensitive.** `media:WhatsApp/Step.PNG` is rejected. Reason, and it is not
  cosmetic: the production store is `DiskService` on a case-sensitive Linux filesystem
  (`config/storage.yml:5-7`, contract §3) while the corpus is reviewed on developer machines that may not be,
  so a key that differs only in case would seed on one machine and 404 on the other. One case is the only
  reproducible rule. The `media:` scheme token itself is also lowercase-only (§0.2 shows `MEDIA:` parses
  cleanly, so only the grammar can reject it).
- **Depth**: at least two segments (`<section>/<name>.png`), at most four plus the filename. The corpus
  sections are the manifest's own slugs (`custom/db/documentation/manifest.yml`), so the first segment is
  expected to be a section slug; that is a convention the seeder reports on, not a validation, because the
  changelog corpus has a different section set (`custom/db/changelog/<locale>/releases`).
- **Length**: a key is at most 200 characters, so it always fits `active_storage_blobs.filename`
  (`t.string`, `db/schema.rb:101`) and the metadata value with room to spare.

### 1.3 Directory mapping

```
media:whatsapp/connect-number/step-2.png
  ->  custom/db/documentation/media/whatsapp/connect-number/step-2.png
```

The mapping is `<corpus root>/media/<key>`, where the corpus root is the `root:` the seeder is constructed
with — `ContentSeeder::DOCS_ROOT` = `custom/db/documentation` or `CHANGELOG_ROOT` = `custom/db/changelog`
(`custom/app/services/documentation/content_seeder.rb:10-11`). Media is **locale-independent**: there is no
`en/`/`ar/` level under `media/`, because the EN and AR translations of a page legitimately reference the same
screenshot (R2-F1 reason 1) and a per-locale tree would force two blobs for one image.

The `media/` directory is deliberately a **sibling** of the `en/`/`ar/` trees rather than inside them, so
`ContentSeeder#seed_section`'s glob `Dir.glob(root.join(locale, section['slug'], '*.md'))`
(`content_seeder.rb:52`) can never pick a media file up.

### 1.4 What is rejected, and what each rejection does

Rejection happens in **two** places and they do different jobs, which is the point:

- **The seed boundary** rejects by failing the seed run loudly (§3.5). It sees the raw corpus bytes, so it is
  the only place that can catch §0.3's space case.
- **The resolver** rejects by returning `nil`, which makes the renderer emit the fallback of §2.3 and makes
  the delivery route answer `404`. It is the runtime half and it never raises on a public request.

| Input | Seed boundary | Resolver / route | Why |
|---|---|---|---|
| `media:whatsapp/connect-number/step-2.png` | accepted | resolves | the documented form |
| `media:whatsapp/connect-number/step 2.png` | **seed FAILS** | never reached | §0.3 — it is not an image node; the Markdown source would be published verbatim. This is the one case only the seed boundary can see |
| `media:../../etc/passwd` | **seed FAILS** | `nil` → 404 | measured in §0.2: it parses as an image and `escape_href` leaves it intact, so escaping is no defence. Note what the real risk is and is not: contract §3.1 forbids `service.path_for`/`service.root`, so **no filesystem path is ever constructed from a key** — traversal is a grammar violation and a failed in-memory key lookup, not a file-read primitive. Saying otherwise would invent a threat this design does not have |
| `media:/absolute/x.png` | **seed FAILS** | `nil` → 404 | leading `/` is not a `segment`. (Measured: `URI.parse` gives `opaque=nil` for this form, so it is also the one shape whose `?query` *would* parse — another reason to ban it rather than tolerate it) |
| a signed id, e.g. `media:eyJfcmFpbHMi…` | **seed FAILS** (uppercase, `=`) | `nil` → 404 | contract item 10: a signed id is a verifier over the blob primary key keyed from `secret_key_base`, valid in exactly one database. The grammar's lowercase-only rule rejects base64 by construction, which is a deliberate second-order benefit |
| a key naming the **other** portal's file | accepted if the file exists under *this* corpus root; otherwise **seed FAILS** | `nil` → 404 | contract §0.2: the namespace is per-portal and resolution is scoped to the rendering portal. An identical file used by both corpora is committed twice and stored twice. There is no cross-portal fallback, deliberately |
| `media:` (empty key) | **seed FAILS** | `nil` → 404 | measured in §0.2: it parses, so it must be rejected explicitly |
| `media:x.png?cw_image_width=400px` | **seed FAILS** | `nil` → 404 | §0.4 — `?` is not in the character set, and the width would be silently ignored anyway. Sizing is the resolver's job |
| `media:x.png#frag` | **seed FAILS** | `nil` → 404 | same rule; `#` is not in the character set |
| `media:a%2Fb.png` | **seed FAILS** | `nil` → 404 | `%` is not in the character set. Measured: `escape_href` leaves `%2F` untouched, so a pre-escaped key would reach the resolver as a distinct, unmatchable string |
| uppercase anywhere | **seed FAILS** | `nil` → 404 | §1.2 |
| an extension outside `{png,jpg,jpeg,gif,webp}` — `.svg` especially | **seed FAILS** | `nil` → 404 | contract item 5: raster only, no SVG. The content type is checked independently of the extension at the seed boundary (§3.4), because an extension is an author's claim and the bytes are the fact |
| `[text](media:a/b.png)` — a key in a **link** position | **seed FAILS** | n/a | `MarkdownRendererUrlSanitizer#link` (`lib/markdown_renderer_url_sanitizer.rb:6-10`) emits `href="media:a/b.png"` verbatim (same `escape_href`, §0.2), which is a dead link in every browser. Only the `image` node is resolved, so a key in a link must be caught where the bytes are read |

### 1.5 One rule, one place

The grammar lives in exactly one constant, on the resolver, and the seeder calls the resolver's validator
rather than carrying a second copy:

```ruby
Documentation::MediaResolver::KEY = %r{\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:/[a-z0-9](?:[a-z0-9-]*[a-z0-9])?){1,4}\.(?:png|jpe?g|gif|webp)\z}
Documentation::MediaResolver.valid_key?(key) # -> true/false
```

No route constraint duplicates it. CLAUDE.md asks for enforcement at the earliest shared entry point; for a
key the shared entry point is this predicate, and a `constraints:` clause in `config/routes.rb` would be a
second copy of the grammar in a file Agent 1 does not own.

---

## 2. `Documentation::MediaResolver`

`custom/app/services/documentation/media_resolver.rb` — Agent 1 owns it.

### 2.1 Public signature

```ruby
class Documentation::MediaResolver
  KEY = %r{...}                       # §1.5
  Image = Struct.new(:key, :blob, :path, :content_type, :byte_size, :width, :height, keyword_init: true)

  def self.valid_key?(key)            # -> true | false

  # portal: the portal currently rendering -- keys are per-portal (contract 0.2).
  # article: needed to BUILD the delivery path, which is nested under the article so the route can apply the
  #          0.1 predicate. It is not needed to resolve the key.
  def initialize(portal:, article:)

  def resolve(key)                    # -> Image | nil
  def keys                            # -> Array<String>, this portal's attached keys (the seeder's orphan pass)
end
```

**It takes both, and the distinction matters**: `portal` is the *lookup* scope, `article` is only the *URL*
scope. If a future surface needs a key resolved without an article — there is none today — that is a new
method, not a nil-tolerant `article:`.

### 2.2 What it returns

`resolve` returns an `Image` or `nil`. Nothing else, and it never raises on a public request.

| Field | Source | Note |
|---|---|---|
| `key` | the input, after `valid_key?` | echoed so a caller can log it without re-deriving |
| `blob` | `attachment.blob` | for the delivery controller to stream. Contract §3.1: `blob.download`/`open`, never `service.path_for` |
| `path` | `public_portal_article_media_path(portal.slug, article.slug, key)` | **root-relative**, never a full URL. The article page is reachable on a tenant custom domain (`app/controllers/public_controller.rb:9-20`, and `ArticlesController` applies `ensure_custom_domain_request` to `show` at `articles_controller.rb:2`), so a host-qualified URL would leave the origin. With no `img-src` in the enforcing CSP (contract §0.4) same-origin is the only protection there is |
| `content_type` | `blob.content_type` | |
| `byte_size` | `blob.byte_size` | |
| `width`, `height` | `blob.metadata['width'] / ['height']` | **may be nil** — see §0.7. That is a measured framework behaviour, not a speculative guard |

Measured, so `path` can be trusted: a glob segment is formatted with `escape_path`
(`actionpack-7.2.3.2/lib/action_dispatch/journey/visitors.rb:9,146-148` → `Journey::Format.required_path`),
and `escape_path`'s unsafe set is `PATH = /[^#{UNRESERVED}#{SUB_DELIMS}:@\/]/`
(`lib/action_dispatch/journey/router/utils.rb:50,56-58`) with `UNRESERVED` including `.`
(`:43`). **So `/` and `.` in the key survive helper generation unescaped** and the generated path is
`/hc/lynomia-docs/articles/connect-whatsapp/media/whatsapp/connect-number/step-2.png`.

### 2.3 On a miss

`resolve` returns `nil`. The caller decides:

- **`CustomMarkdownRenderer#image`** (Agent 1's file): emits `<!-- media: unresolved key <key> -->` and
  nothing else. No `<img src="">`, because an empty `src` re-requests the current page in several browsers;
  no placeholder image, because there is no placeholder asset and inventing one is a parallel system. The
  comment is HTML-escaped and carries only the key, which is author-written corpus text and never user input.
  An unresolved key is a **corpus defect that the seed boundary should already have refused**, so the runtime
  behaviour only has to be inert and diagnosable.
- **The delivery route** (§4): `head :not_found`.

### 2.4 Memoization, and the twenty-image question

**It memoizes, per instance, and the instance lives for exactly one article render.**

```ruby
def index
  @index ||= portal.documentation_media.includes(:blob).index_by { |a| a.blob.metadata['documentation_key'] }
end
```

`portal.documentation_media` is an `ActiveStorage::Attached::Many` proxy with `delegate_missing_to :attachments`
(`activestorage-7.2.3.2/lib/active_storage/attached/many.rb:27,32-34`), so `.includes(:blob)` reaches the real
`documentation_media_attachments` association.

Why in memory rather than in SQL: §0.5 — `active_storage_blobs.metadata` is a `text` column with a JSON coder
(`blob.rb:31`), so there is no operator to query it with, and the only indexed path is the attachments
uniqueness index on `(record_type, record_id, name, blob_id)` (`db/schema.rb:96`).

**The N+1 answer for an article with twenty images: there is no N+1.** One `index_by` over
`portal.documentation_media.includes(:blob)` costs **two** queries — attachments by the index above, then
blobs by id — regardless of whether the article has one image or twenty. Twenty `resolve` calls are twenty
hash lookups.

Two conditions make that true, and both are interface requirements, not advice:

1. **One resolver instance per render**, constructed by the caller and passed in. `ChatwootMarkdownRenderer`
   constructs the renderer with no arguments today (`lib/chatwoot_markdown_renderer.rb:14`), so the resolver
   has to be threaded in — REQUESTED CHANGES #2 and #3.
2. **The set is the portal's whole media library, not the article's.** That is the cost of portal ownership
   (contract item 1): a portal with 400 images loads 400 attachment rows to render an article with one. At
   corpus scale that is a few hundred rows of two narrow tables and it is the right trade, because the
   alternative is per-key lookups with no index. If the docs corpus ever passes roughly a thousand media
   files this should be re-measured — recorded as **R2-O6** rather than pre-optimised.

Note what is *not* cached: nothing is memoized across requests. There is no `Rails.cache`, no class-level
memo, no `resolve_model_to_route` change (contract §2.3 — it is unset, the framework default
`:rails_storage_redirect` applies, and flipping it would move avatars, portal logos, chat attachments, macro
and automation files and exports to the proxy route at once). Resolution is **per render, per call**, exactly
as ruling R2 requires.

---

## 3. `Documentation::MediaSeeder`

`custom/app/services/documentation/media_seeder.rb` — Agent 1 owns it. Agent 5 owns the one line in
`ContentSeeder` that calls it, so this section is the shape Agent 5 codes against.

### 3.1 Public signature

```ruby
class Documentation::MediaSeeder
  Result = Struct.new(:uploaded, :replaced, :unchanged, :purged, :unmeasured, :unreferenced, keyword_init: true)

  # portal: the portal to attach to.  root: the SAME corpus root ContentSeeder was given; the media tree is
  # root.join('media').
  def initialize(portal:, root: Documentation::ContentSeeder::DOCS_ROOT)

  def perform!   # -> Result.  Raises Documentation::MediaSeeder::Error on any corpus defect (3.5).
end
```

Deliberately the same keyword shape as `ContentSeeder#initialize(portal:, author:, publish:, root:)`
(`content_seeder.rb:20`), so the one line Agent 5 writes reads like the code around it.

### 3.2 The one line Agent 5 owns

```ruby
# custom/app/services/documentation/content_seeder.rb, inside perform!
@result.media = Documentation::MediaSeeder.new(portal: portal, root: root).perform!
```

Two notes for Agent 5, both consequences rather than preferences:

- `Result = Struct.new(:created, :updated, :unchanged, :locales, keyword_init: true)`
  (`content_seeder.rb:14`) has no `media` member. Adding one is Agent 5's change to Agent 5's file.
- **Call it first, before `manifest['sections'].each`** (`:28-31`). A missing alt or a missing file is a seed
  failure (§3.5); failing before any article is written leaves the corpus untouched instead of half-seeded.
  Media never has to be seeded before articles for *correctness* — resolution happens at render time, not
  seed time — so this is purely about where the run aborts.

### 3.3 Why it re-scans the corpus instead of being handed the keys

`MediaSeeder` does its own walk: `Dir.glob(root.join('*', '*', '*.md'))` over the locale/section trees,
extracting `media:` references from each body. The alternative — `ContentSeeder` collecting keys per article
and handing them over — cannot be one line, and it would couple two agents' files on a per-article basis.
The cost is one extra read of 128 small files per seed run (§0.1), measured, and the benefit is that
`MediaSeeder` is independently runnable, which is what lets Agent 5 add a `documentation:media` rake task
beside the existing `documentation:content` (`lib/tasks/documentation.rake:16-20`).

### 3.4 Idempotency — by checksum against the portal's own attachments, never globally

For each referenced key:

1. Read the file at `root/media/<key>`.
2. Compute the candidate's checksum the way ActiveStorage does — `ActiveStorage::Blob.new` /
   `create_and_upload!` computes it via `compute_checksum_in_chunks`
   (`activestorage-7.2.3.2/app/models/active_storage/blob.rb:107,354`) — and compare it against the checksum
   of **this portal's existing attachment for that key**, found through the in-memory index of §2.4.
3. Same key, same checksum → `unchanged`, no write.
4. Same key, different checksum → §6 replace.
5. No attachment for that key → upload and attach, then `blob.analyze` synchronously.

**Never `ActiveStorage::Blob.find_by(checksum:)`.** `db/schema.rb:99-109` shows the only blob index is
`index_active_storage_blobs_on_key` (`:108`); `checksum` is unindexed (`:105`), so a global lookup is a
sequential scan of every attachment the product has ever stored (measured, `P2-RULINGS-IMPLEMENTATION.md`
R2-F2: `CHECKSUM_INDEXED=false`). It would also let one portal silently adopt another portal's blob because
two files happen to share bytes, which contract §0.2 forbids outright.

### 3.5 Where the key lives on the blob

`blob.metadata['documentation_key']` holds the full corpus-relative key. `blob.filename` holds the
**basename** only (`step-2.png`).

Why not put the key in `filename`: `ActiveStorage::Filename#to_s` is `sanitized`
(`activestorage-7.2.3.2/app/models/active_storage/filename.rb:64-66`), and `sanitized` replaces `/` and `:`
with `-` (`:59-61`). So `blob.filename.to_s` on a slash-bearing name returns
`whatsapp-connect-number-step-2.png` — a lossy value that silently differs from what was stored, reachable
only via `blob[:filename]`. A field whose reader lies is not a key. Basename-in-`filename` also gives the
delivery response a sensible `Content-Disposition`.

Why `metadata` is safe for this: `blob.analyze` **merges** (`blob/analyzable.rb:29-31`), so analysis cannot
clobber the key; the framework's own reserved accessors are `analyzed`, `identified`, `composed`
(`blob.rb:31`), none of which collide; and
`ActiveStorageDirectUploadMetadataFilter` (`config/initializers/active_storage.rb:15-25`) strips those three
on the **direct-upload** path only, which the seeder is not on. The accepted cost is that the key is not
SQL-queryable (§0.5) — which the resolver's design already requires.

The rejected alternative, named so nobody re-derives it: an additive Lynomia-owned table or column keyed by
`(portal_id, key, blob_id)`. It would make the key queryable and indexed. It is **not** taken because only
Agent 5 may add a migration (ownership table), it is a second content model beside ActiveStorage's own
(§2 of the charter: no parallel media system), and §2.4 shows the in-memory index costs two queries per render
at any corpus size this product will have. If R2-O6 ever fires, this is the thing to reconsider.

### 3.6 Enforcement at the seed boundary — and what failure looks like

Everything contract item 5 and item 7 freeze is checked here, because this is the earliest point that sees the
bytes and the prose together:

| Check | Failure |
|---|---|
| key matches `MediaResolver::KEY` (§1.5) | `Error` |
| `![…]` alt text is non-empty after strip | `Error` (§5) |
| the file exists at `root/media/<key>` | `Error` |
| the bytes' content type is in `{image/png, image/jpeg, image/gif, image/webp}` — checked from the bytes, not the extension | `Error` |
| `byte_size <= 2.megabytes` | `Error` |
| the key appears only in an `image` node, never a `link` node (§1.4) | `Error` |
| a `![…](…)` whose destination is a bare space-bearing path (§0.3) | `Error` |

`Documentation::MediaSeeder::Error` is a subclass of `StandardError` defined in `lib/custom_exceptions/` per
CLAUDE.md. It carries the corpus **file path**, the line, the key and the reason — never a storage path
(contract §3.2).

**What the operator sees.** `MediaSeeder` raises; `ContentSeeder#perform!` does not rescue; the rake task
(`lib/tasks/documentation.rake:16-20`) does not rescue, so `rake` prints the message and backtrace and exits
**1** — Rake's own behaviour for an unhandled exception in a task. No partial corpus is written, because §3.2
puts the media pass first. CLAUDE.md: a misconfigured state that indicates a setup bug fails loudly rather
than silently skipping.

### 3.7 What `Result` reports, so the rake task can print counts

| Member | Meaning |
|---|---|
| `uploaded` | keys newly attached to this portal |
| `replaced` | keys whose bytes changed — new blob attached, old purged (§6) |
| `unchanged` | keys whose checksum already matched |
| `purged` | orphan attachments purged because their key no longer appears in this portal's corpus (contract item 9) |
| `unmeasured` | uploaded or replaced blobs whose `metadata` came back with no `width`/`height` — the §0.7 signal. **Non-zero on a healthy corpus means libvips is missing on this host**, which is the one thing the operator cannot otherwise see |
| `unreferenced` | files under `root/media/**` that no corpus file references. **Not** a failure: they are committed to git, reviewed in diffs, and harmless. Reported so the number does not drift silently |

Suggested line for Agent 5's rake task, matching the existing style at `documentation.rake:13,19`:

```ruby
puts "media: #{m.uploaded} uploaded, #{m.replaced} replaced, #{m.unchanged} unchanged, #{m.purged} purged" \
     " (#{m.unmeasured} without dimensions, #{m.unreferenced} unreferenced)"
```

---

## 4. The delivery route and the controller

### 4.1 Path shape

```
GET /hc/:slug/articles/:article_slug/media/*media_key
```

Named `public_portal_article_media`, with **`format: false`**.

**`format: false` is not optional, and here is why.** A glob node's regexp is `/.+?/m`
(`actionpack-7.2.3.2/lib/action_dispatch/journey/nodes/node.rb:163-171`) — non-greedy and it crosses `/` and
`.`. Without `format: false`, `Mapping.normalize_path` appends `(.:format)`
(`lib/action_dispatch/routing/mapper.rb:116-130`: `optional_format?` is `format != false && !path.match?(OPTIONAL_FORMAT_REGEX)`),
so the non-greedy glob stops before the final dot and `/media/whatsapp/x/step-2.png` arrives as
`params[:media_key] == "whatsapp/x/step-2"` with `params[:format] == "png"` — a key that can never match.
With `format: false` the whole remainder, extension included, lands in `params[:media_key]`.

**It cannot collide with the two literal suffixes already claimed on the article route.** Rails' default
dynamic segment matches neither `/` nor `.`, so:

| Existing route | Segments after `hc/:slug` | Can it match a media path? |
|---|---|---|
| `hc/:slug/articles/:article_slug.png` (`config/routes.rb:516`, tracking pixel) | 2, with a literal `.png` suffix on the last | No — a media path has ≥4 |
| `hc/:slug/articles/:article_slug.md` (`:517-518`, `show_markdown`) | 2, literal `.md` | No |
| `hc/:slug/articles/:article_slug` (`:519`, `show`) | 2 | No |
| `hc/:slug/:locale/categories/:category_slug/articles` (`:515`) | 4, with literals `categories` and `articles` at positions 2 and 4 | No — the media path has `articles` at position 1 and `media` at position 3 |
| `hc/:slug/:locale/articles` (`:512`), `…/categories` (`:513`), `…/categories/:category_slug` (`:514`) | 2–3 | No |

**Declaration order is therefore not load-bearing**, which is a checkable claim rather than a hope: the
segment counts differ, so no earlier route can shadow it. It still goes immediately after `:519` so the
article routes stay together.

### 4.2 Parameters

| Param | Source | Use |
|---|---|---|
| `:slug` | path | the portal — `Portal.find_by(slug:, archived: false)`, the same lookup as `Public::Api::V1::Portals::BaseController#portal` (`base_controller.rb:34-36`) |
| `:article_slug` | path | the article the §0.1 predicate is applied to |
| `*media_key` | path glob | the key, validated by `MediaResolver.valid_key?` |

Nothing is read from the query string. No `format`, no `locale`, no `theme`, no `show_plain_layout`.

### 4.3 Controller

`app/controllers/public/api/v1/portals/media_controller.rb` — Agent 1 owns it.

**It inherits `PublicController`, not `Public::Api::V1::Portals::BaseController`**, and that is a measured
decision rather than a style choice. `BaseController` installs `around_action :set_locale`
(`base_controller.rb:7,38-43`) which, because `params[:article_slug]` is present, runs
`switch_locale_with_article` (`:53-65`) — an **unscoped** `Article.find_by(slug:)` across every portal, plus
an unconditional `Rails.logger.info "Article: not found for slug: …"` at `:55` that fires even when the
article *is* found. On a page with twenty images that is twenty extra cross-portal article queries and twenty
misleading log lines, for a binary endpoint that needs no locale at all. `BaseController` also adds
`set_global_config` (`:78-80`, a four-key `GlobalConfig.get` per request) and a `render_404` (`:71-76`) that
renders the portal's **HTML** error template — the wrong body for an `<img>` request.

Filters, in order:

```ruby
before_action :ensure_custom_domain_request   # PublicController:9-20
before_action :set_portal
before_action :ensure_portal_feature_enabled  # PublicController:22-27
```

`ensure_custom_domain_request` is included for **parity of refusal**, not for resolution: the article page
applies it (`articles_controller.rb:2`), so an unregistered custom domain gets `401` on the page and must not
get `200` on its images. `ensure_portal_feature_enabled` is included for the same reason; on a platform
portal it passes, because `Portal#feature_enabled?` answers from `PLATFORM_FEATURES`
(`app/models/portal.rb:193-199`).

### 4.4 The predicate

**Published OR the requester is a signed-in super admin** — contract §0.1, matching `set_article`
(`articles_controller.rb:83-86`) exactly:

```ruby
scope = previewing_as_super_admin? ? @portal.articles : @portal.articles.published
```

This is a *separate HTTP request* from the article page, so the predicate has to be evaluated again — there is
no shared request-time entry point to hoist it to. What must not be duplicated is the **rule**, and today
`previewing_as_super_admin?` exists only inside `ArticlesController` (`:88-91`). Leaving a second copy in the
media controller would reproduce, by construction, exactly the divergence already recorded as **R2-O1**
(`show` serves a draft to a super admin, `show_markdown` at `:29-33` refuses one). So §REQUESTED CHANGES #4
asks for the two methods to be extracted into one concern that both controllers include. The fallback, if the
Orchestrator declines, is two literal lines in the media controller plus a spec asserting the two controllers
agree — strictly worse, and named so the choice is explicit.

A no-exclusion search for `previewing_as_super_admin` found **no view or partial that calls it**: the only
code hits are `articles_controller.rb:84`, `:88`, `:91`; every other hit is in `docs/`. So the
`helper_method` declaration at `:91` is unused today. The extraction keeps it anyway — removing it is an
unrelated change (noted in OPEN).

### 4.5 The response

```ruby
def show
  image = resolver.resolve(params[:media_key])
  return head :not_found if image.nil?

  if @article.published?
    fresh_when(etag: image.blob.checksum, last_modified: image.blob.created_at, public: true)
    expires_in 1.hour, public: true
  else
    response.headers['Cache-Control'] = 'private, no-store'
  end

  send_blob_stream(image.blob, disposition: :inline)   # ActiveStorage::Streaming
end
```

- Body: the blob's bytes, streamed. `ActiveStorage::Streaming#send_blob_stream`
  (`activestorage-7.2.3.2/app/controllers/concerns/active_storage/streaming.rb:44-53`) uses `blob.download`
  and sets `type: blob.content_type_for_serving` and
  `disposition: blob.forced_disposition_for_serving || :inline`. Those two readers
  (`app/models/active_storage/blob/servable.rb:4-21`) are the mechanism that forces `image/svg+xml` to
  `ActiveStorage.binary_content_type` + `attachment` — the stored-XSS defence contract item 5 says is not to be
  relaxed. Using the framework's own streamer keeps that defence rather than re-deriving it, and it keeps
  contract §3.1 (no `service.path_for`, no `storage/` path, no `send_file`).
  **Note**: `config/initializers/active_storage.rb:27-45` prepends `ActiveStorageProxyRangeLimit` onto
  `ActiveStorage::Streaming`, so including the concern inherits the repo's own range hardening for free.
- `Content-Length` is not set by hand; the streamer handles it.

**Cache headers.**

| Case | Headers | Why |
|---|---|---|
| Published article | `Cache-Control: public, max-age=3600` + `ETag: <blob.checksum>` + `Last-Modified` | Contract item 4: cacheable to anyone. A long `immutable` max-age is **wrong** here because the URL is not content-addressed — contract item 8 lets the same key take new bytes, so a year-long cache would serve a replaced screenshot indefinitely. One hour bounds post-deploy staleness; the checksum ETag makes revalidation a `304` with no body. `fresh_when` handles the conditional request |
| Unpublished article, signed-in super admin | `Cache-Control: private, no-store` and no ETag | Contract items 3, 4 and 11, in the contract's own words. A draft's media is never cacheable and never public |

### 4.6 The 404 cases — every one is `head :not_found`, never 403, never a redirect

| Case | Why 404 |
|---|---|
| portal slug unknown, or `archived` | `find_by` + explicit `head :not_found`, rather than `find_by!`: `PublicController` does not rescue `ActiveRecord::RecordNotFound` (`app/controllers/concerns/request_exception_handler.rb:11-14` rescues only `RecordInvalid` and two custom exceptions), so a raise would produce Rails' HTML error page as the body of an image request |
| article slug not in this portal | the scope is `@portal.articles` |
| article unpublished and the requester is not a signed-in super admin | **404, not 403.** A 403 distinguishes "exists but hidden" from "does not exist" — an existence oracle for unpublished content on an unauthenticated endpoint, which is the exact defect the tracking pixel fix closed (`articles_controller.rb:35-37`) and which `00-program.md` §2.1 names ("an existence oracle counts as visibility") |
| key fails `valid_key?` | §1.4 |
| key is valid but this portal has no attachment for it | §2.3 |
| key belongs to the **other** platform portal | the index is `portal.documentation_media`; contract §0.2 forbids a cross-portal fallback |
| anything else | there is nothing else. **Never** a `rails_blob_*` redirect and never a signed id in a response — contract item 3 |

---

## 5. Alt text, and the caption question

### 5.1 Alt text is the Markdown's own alt, and nothing else

```markdown
![Step 2: paste the permanent token into the Token field](media:whatsapp/connect-number/step-2.png)
```

Field name: **the CommonMark alt text**. There is no `alt:` front-matter key and there must not be one — a
second home for the same value is a parallel system, and the value already has a correct home that every
Markdown tool understands.

**Alt is a public SEO/snippet field, not only an accessibility attribute.** Contract §0.3, re-verified:
`render_markdown_to_plain_text` (`lib/chatwoot_markdown_renderer.rb:21-23`) is `CommonMarker`'s
`to_plaintext`, which emits an image's alt and discards its destination, and it has two production consumers —
`PortalHelper#render_category_content` (`app/helpers/portal_helper.rb:97`) and the public search payload
(`app/views/public/api/v1/models/_search_article.json.jbuilder:1`, the public `articles.json` `content`
field). So an empty alt degrades the public search snippet as well as the screen-reader experience, and a
`media:` key can never leak into a snippet through that path because the URL is thrown away.

### 5.2 "Required at the seed boundary" — exactly what happens

Checked in `MediaSeeder#perform!` (§3.6): alt text, stripped, must be non-empty.

- **What the seed prints**: `Documentation::MediaSeeder::Error`, message
  `custom/db/documentation/en/whatsapp/connect-whatsapp.md:41 — media:whatsapp/connect-number/step-2.png has empty alt text. Alt is required: it is the public search snippet as well as the accessible name.` (illustrative; `connect-whatsapp.md` is a real corpus file, the line number and the key are not)
- **Exit code**: `1`. Nothing between the raise and Rake rescues it — not `MediaSeeder`, not
  `ContentSeeder#perform!` (`content_seeder.rb:28-31`), not the task body
  (`lib/tasks/documentation.rake:16-20`).
- **What is written**: nothing. Media runs first (§3.2), so the articles are untouched.

An image is never published with an empty alt, and that is enforced once, at the boundary, rather than by a
publish-time check in the editor *and* a seed check *and* a render check.

### 5.3 Decorative images

Reserved front-matter key, frozen now so nobody invents a second name:

```yaml
media:
  decorative:
    - whatsapp/connect-number/divider.png
```

It lives in `custom/db/documentation/manifest.yml`-governed article front matter, which Agent 3 owns; the
ownership table already anticipates this ("Agent 1 needs media front-matter keys … both submit their key
additions to the Orchestrator"). It is front matter rather than in-prose because a reserved alt token like
`decorative` would be emitted into the public snippet by §5.1's path, and a `title=` marker would surface as a
browser tooltip.

**R2 implements the strict rule only: an empty alt is a seed failure, with no exception.** The corpus has zero
images (§0.1) and therefore zero decorative images, so wiring the branch now would be a guard no caller can
reach — CLAUDE.md. The key name is frozen so Agents 2 and 3 can plan against it; the one condition that adds
the branch is the first decorative image in the corpus, as **R2-O5**.

### 5.4 Captions — R2-O2, deferred to R3

**What Agent 2 may assume**: that there is no caption in the content model today, and that alt text is a
separate field from any future caption — alt describes the image for a reader who cannot see it, a caption is
body copy. It may lay out the insertion panel so a caption field can be added later, shown disabled or absent.

**What Agent 2 must not do**, because each would decide R2-O2 unilaterally:

- emit `<figure>`/`<figcaption>` into the Markdown. `render_article` parses with `:DEFAULT`
  (`lib/chatwoot_markdown_renderer.rb:15`), so raw HTML renders as **literally nothing** — the caption would
  vanish on publish while looking correct in the editor. (Ruling R3 point 4 disqualified HTML-storing editors
  on exactly this evidence.)
- adopt a convention such as "the italic paragraph after an image is its caption". That makes ordinary prose
  load-bearing and is unrepresentable in the source model.
- write a `caption:` front-matter key, or a second value into the alt.
- put a caption in the image `title`. `CustomMarkdownRenderer#image` emits `title="…"` when present
  (`lib/custom_markdown_renderer.rb:68`), which is a hover tooltip, not a caption, and is invisible on touch.

---

## 6. Replace, remove and orphan semantics as an interface

All three are the seeder's, never a background job and never implicit in an article rewrite (contract items
8 and 9).

### 6.1 Changed bytes, same key

1. Upload the new file and attach it to the portal, with `metadata['documentation_key']` set to the same key.
2. `blob.analyze`.
3. **Only after the new attachment has succeeded**, `old_attachment.purge_later`.
4. `Result.replaced += 1`.

Order is the contract's (item 8) and the reason is §3A: a row without bytes is a broken published page, while
bytes without a row are an orphan the next run reclaims. If step 1 or 2 raises, the old attachment is still
there and the page still renders the previous screenshot.

Transiently, two attachments carry the same key, and **the resolver's behaviour in that window is not
specified**. `has_many_attached` generates `has_many :"#{name}_attachments", -> { where(name: name) }`
(`activestorage-7.2.3.2/lib/active_storage/attached/model.rb:228`) with no `ORDER BY`, so which of the two
`index_by` keeps is whatever order Postgres returns — it is not "the newer one", and anything written on the
assumption that it is would be wrong. That is why correctness comes from the step order above (purge only
after attach succeeds) and not from resolver ordering. The window exists only inside one seed run, between
steps 1 and 3, and a concurrent render during it serves one of two valid images.

### 6.2 A key removed from the corpus

After the referenced-key pass, any `documentation_media` attachment on this portal whose
`metadata['documentation_key']` does not appear in this portal's corpus is purged with `purge_later`, and
`Result.purged` counts it. That is contract item 9 verbatim: the seeder owns orphan cleanup, because nothing
in this app cleans unattached blobs today, and portal ownership (item 1) is what makes cleanup possible at all.

Scope discipline, from contract §0.2: the sweep is `portal.documentation_media` only. It never touches the
other platform portal's media, never `Portal#logo` (`app/models/portal.rb:50` — a different attachment name,
so it is outside `documentation_media` by construction), and never anything on an Article.

### 6.3 `purge_later` is really processed — with the corrected reason

`blob.purge_later` (`activestorage-7.2.3.2/app/models/active_storage/blob.rb:344`) enqueues
`ActiveStorage::PurgeJob`, which is `queue_as { ActiveStorage.queues[:purge] }`
(`app/jobs/active_storage/purge_job.rb:5`). Per §0.6 that value is **nil** in this app, so ActiveJob falls
back to `default_queue_name` = `"default"` (`activejob-7.2.3.2/lib/active_job/queue_name.rb:9,47-51`), and
`default` is processed (`config/sidekiq.yml:21`).

So: **processed, on `default`.** Not on `active_storage_purge` (`config/sidekiq.yml:32`), which nothing
enqueues to.

### 6.4 One thing this interface does not solve

The storage bytes are on local disk under `Rails.root.join("storage")` (contract §3) in a `.gitignore`d
directory (`.gitignore:59`) that the repository does not back up (contract §3A.1, **R2-O4, confirmed open**).
Replace and purge are correct *within* the application; they do nothing about a host rebuild or a
database-only restore. Nothing in this interface implies the media is safe, and §3A.2's smallest safe addition
remains designed and **not approved**.

---

## 7. The `data:image/*` closure

### 7.1 The absence claim, stated precisely

> **Nothing in this repository depends on `data:image/*` being permitted in the ARTICLE renderer path, and no
> production surface produces such a URL for an article.**

Scoped exactly that way. It is *not* a claim about the message/email path, where `data:image/*` is permitted,
is asserted by a passing spec, and stays permitted.

### 7.2 The five steps of `00-program.md` §2.3

**Step 1 — searches with no exclusion filter**, over every tracked file (`git grep`; `node_modules` and
`vendor/bundle` are untracked, and `.gitignore:59` excludes `storage`):

```
git grep -n "data:image"                 # 32 files
git grep -n "MarkdownRendererUrlSanitizer"
git grep -n "SAFE_DATA_IMAGE_PATTERN"
git grep -n "DANGEROUS_URL_PATTERN"
git grep -n "sanitized_href"
git grep -n "BaseMarkdownRenderer"
git grep -n "render_article\b" / "render_message\b" / "render_markdown_to_plain_text"
git grep -n "stripInlineBase64Images" / "hasInlineImages"
git grep -n '!\[' -- custom/db/documentation custom/db/changelog
```

**Step 2 — every `data:image` hit classified by hand.** All 32 files:

| Class | Files | Depends on the article renderer's `data:` permission? |
|---|---|---|
| SVG assets with an embedded raster | `app/javascript/dashboard/assets/images/auth/auth--bg.svg:89`, `public/assets/images/auth/auth--bg.svg` | No — image files, parsed by no Markdown renderer |
| CSS `background-image: url("data:…")` | `app/javascript/dashboard/assets/scss/_base.scss:109`, `_woot.scss:48,55`, `app/javascript/widget/assets/scss/woot.scss:110`, `app/javascript/v3/components/Form/Select.vue:88`, `app/views/super_admin/application/_filters.html.erb:39` | No — stylesheets |
| **The editor**, and it only *strips* | `app/javascript/dashboard/helper/editorHelper.js:43-54` — `stripInlineBase64Images`, regex at `:49`. Its one production caller is `MessageSignature.vue:28,32` (profile **message signature**) | No — and it is evidence the other way: the only product code that knows about Markdown data-images removes them, on a non-documentation surface |
| Specs for that stripper | `editorHelper.spec.js:483-507` | No |
| An unrelated mocked QR data URL | `settings/inbox/specs/FinishSetup.spec.js:66` — `mocks.toDataURL` | No |
| **The article-renderer spec that asserts the current behaviour** | `spec/lib/markdown_renderer_security_spec.rb:205-222` — the comment at `:205-210` records the decision and says it is "recorded for the media contract rather than changed inside a security hotfix"; `:211-213` asserts `data:image/png` is permitted in `render_article`; `:215-217` asserts `data:text/html` is blanked in a **link**; `:219-222` asserts `svg+xml` is blanked | **Yes — `:211-213` is the one assertion the closure inverts**, and it is a spec, not a dependency. `:215-217` and `:219-222` stay green |
| The message-renderer spec, which must stay green | `spec/lib/base_markdown_renderer_spec.rb:77-83` (svg blanked), `:85-89` (`data:image/png` permitted) | No — and keeping it green is the containment proof (§7.4) |
| Program documents | 19 files under `docs/` | No |

**Step 3 — aliases, helpers, concerns and config republication followed.** `SAFE_DATA_IMAGE_PATTERN` is
referenced from exactly two source lines, `lib/markdown_renderer_url_sanitizer.rb:4` and `:16`; it has no
alias, no `const_get`, no YAML or ENV republication, and no reference from any initializer
(`git grep -n "SAFE_DATA_IMAGE_PATTERN"` — every non-`docs/` hit is those two lines plus the spec comment at
`markdown_renderer_security_spec.rb:206`). The module has exactly **two** includers, found with no exclusion
filter: `lib/base_markdown_renderer.rb:2` and `lib/custom_markdown_renderer.rb:2`.

**Step 4 — the chain inspected server → renderer → public surface, for all three entry points:**

| Entry point | Renderer class | Goes through the sanitizer? | Production consumers |
|---|---|---|---|
| `render_article` (`lib/chatwoot_markdown_renderer.rb:13-19`) | `CustomMarkdownRenderer` | **Yes** (`custom_markdown_renderer.rb:2`); `#image` calls `sanitized_href` at `:63` | exactly one: `app/controllers/public/api/v1/portals/articles_controller.rb:113` |
| `render_message` (`:6-11`) | `BaseMarkdownRenderer` | **Yes** (`base_markdown_renderer.rb:2`); `#image` calls `sanitized_href` at `:16` | five: `app/helpers/email_helper.rb:10`, `app/helpers/message_format_helper.rb:14`, and `app/views/mailers/conversation_reply_mailer/{conversation_transcript.html.erb:33, reply_with_summary.html.erb:16, reply_without_summary.html.erb:4}` |
| `render_markdown_to_plain_text` (`:21-23`) | **none** — `CommonMarker…to_plaintext` | **No** (§0.9) | two: `app/helpers/portal_helper.rb:97`, `app/views/public/api/v1/models/_search_article.json.jbuilder:1` |

**Step 5 — the corpus, and only then the negative.** Zero image references and zero `data:` URLs in either
corpus (§0.1). The Super Admin authoring surface is a plain `Field::Text` textarea
(`custom/app/dashboards/article_dashboard.rb:19`; ruling R3 point 8 records that its `rows: 28` is inert), so
no authoring surface for an article can paste a data URI into `content` except by typing it. No production
code produces an article `data:image/*`; one spec asserts the permission; the corpus contains none.

**The negative stands, scoped as §7.1 states it.**

### 7.3 The closure

Two edits, both to files Agent 1 owns, in wave 2:

```diff
--- a/lib/markdown_renderer_url_sanitizer.rb
+++ b/lib/markdown_renderer_url_sanitizer.rb
@@
   def sanitized_href(url)
     url = url.to_s
-    return '' if url.match?(DANGEROUS_URL_PATTERN) && !url.match?(SAFE_DATA_IMAGE_PATTERN)
+    return '' if url.match?(DANGEROUS_URL_PATTERN) && !permitted_data_image?(url)
 
     escape_href(url)
   end
+
+  # The agent composer and the message-signature editor can produce an inline base64 image, so the message and
+  # email path keeps this exception. The article path overrides it to false -- see CustomMarkdownRenderer.
+  def permitted_data_image?(url)
+    url.match?(SAFE_DATA_IMAGE_PATTERN)
+  end
```

```diff
--- a/lib/custom_markdown_renderer.rb
+++ b/lib/custom_markdown_renderer.rb
@@
+  # R2: a documentation image is a `media:` key resolved to the app-owned route, so a data URI has no use here
+  # and would bypass every control the seed boundary enforces -- type, size, raster-only, required alt -- while
+  # being permanent once committed to git. Article scope only: the message/email renderer keeps the exception.
+  def permitted_data_image?(_url)
+    false
+  end
```

A method defined in the class wins over one from an included module, so the article path narrows and nothing
else is touched. The rejected alternative — editing `SAFE_DATA_IMAGE_PATTERN` or `sanitized_href`'s condition
directly — is rejected precisely because the module is shared (§7.2 step 3) and that would change the
conversation and email path, which the owner's "no universal sanitizer" ruling forbids.

### 7.4 The exact blast radius

**Changes behaviour on:** `render_article` only — i.e. exactly one call site,
`app/controllers/public/api/v1/portals/articles_controller.rb:113`, which is `GET
/hc/:slug/articles/:article_slug`. After the closure, `![a](data:image/png;base64,…)` in an article renders
`<img src="" …>` instead of the data URI, the same output the article path already produces for
`data:image/svg+xml` (`spec/lib/markdown_renderer_security_spec.rb:219-222`).

**Also newly blanked, deliberately**: `data:image/*` in an article **link** href — `[x](data:image/png;base64,…)`
— because `MarkdownRendererUrlSanitizer#link` (`:6-10`) routes through the same `sanitized_href`. That closes
agent 065's **F5** ("`SAFE_DATA_IMAGE_PATTERN` is a prefix match and is applied to `<a href>` as well as
`<img src>` … an unnecessary exception on the wrong element",
`discovery/065-markdown-render-sanitization.md:406`) for the article path, and only for the article path. There
is no spec for that case today; wave 2 should add one beside the inverted assertion.

**Does not change behaviour on:**

| Surface | Why unaffected |
|---|---|
| Conversation message bubbles | `app/helpers/message_format_helper.rb:14` → `render_message` → `BaseMarkdownRenderer`, which does not override `permitted_data_image?` |
| Outbound reply email, transcript, summary emails | `app/helpers/email_helper.rb:10` and the three mailer views above — same renderer |
| The public category description and the public `articles.json` `content` field | `render_markdown_to_plain_text` uses no Ruby renderer at all (§0.9) |
| The agent reply composer and message signature | client-side; `stripInlineBase64Images` (`editorHelper.js:43-54`) already strips signature data-images before they are stored, and is untouched |
| Every `<a href>` in a message | the module's `link` (`:6-10`) still calls `sanitized_href`, and `permitted_data_image?` still answers from `SAFE_DATA_IMAGE_PATTERN` there |
| `javascript:`, `vbscript:`, `file:` anywhere | `DANGEROUS_URL_PATTERN` (`:3`) is unchanged; the closure only removes the re-permission, in one subclass |

**Spec consequences**, so wave 2 has no surprises:

- `spec/lib/markdown_renderer_security_spec.rb:206-221` must be inverted for the article path. Whether Agent 1
  may edit that file is not settled by the ownership table — REQUESTED CHANGES #6.
- `spec/lib/base_markdown_renderer_spec.rb:77-89` must stay **green, unmodified**. That is the containment
  assertion: if the closure leaks into the shared module, `:85-89` ("preserves safe image data URLs") turns red.
  Agent 1 does not own that file and does not need to.

**Nothing is applied this wave.** The sanitizer is untouched, as instructed.

---

## 8. What Agent 2 may mock

### 8.1 The exact boundary — safe to stub, shapes guaranteed

```ruby
Documentation::MediaResolver.valid_key?(key)                      # -> true | false
Documentation::MediaResolver.new(portal:, article:)
  #resolve(key)                                                  # -> Image | nil
  #keys                                                           # -> Array<String>
Documentation::MediaResolver::Image = Struct.new(
  :key, :blob, :path, :content_type, :byte_size, :width, :height, keyword_init: true
)
Documentation::MediaResolver::KEY                                 # the Regexp of 1.5
```

A fixture Agent 2 can hard-code with confidence:

```ruby
Documentation::MediaResolver::Image.new(
  key: 'whatsapp/connect-number/step-2.png',
  blob: nil,                                 # Agent 2 never needs the blob
  path: '/hc/lynomia-docs/articles/connect-whatsapp/media/whatsapp/connect-number/step-2.png',
  content_type: 'image/png', byte_size: 184_320, width: 1280, height: 720
)
```

Also stable enough to build against:

- the route helper name and arity — `public_portal_article_media_path(portal_slug, article_slug, key)` — and
  that it keeps the key's slashes and dot (measured, §2.2);
- the Markdown form `![alt](media:<key>)` (§1.1) as the only string the editor ever writes or parses;
- the seeder's `Result` members (§3.7), if the editor ever surfaces seed output.

### 8.2 What Agent 2 must not do

**It must not implement an alternative media path.** Concretely:

| Forbidden | Why |
|---|---|
| Any upload endpoint, direct-upload, or `ActiveStorage::DirectUploadsController` use | §0.8: the bare route answers `403` by design. Contract item 6: media is seeded from the repository. An editor upload path is a second ingestion route and bypasses every seed-boundary control |
| `rails_blob_path`, `rails_storage_proxy_path`, `url_for(blob)`, `blob.signed_id`, `blob.url` | Contract items 3 and 10, and §1.2 of the contract: a signed id is a verifier over the blob primary key keyed from `secret_key_base`, so a committed URL is valid in exactly one database |
| Writing `data:image/*` into article `content` on paste or drop | §7 closes it. The editor must strip or refuse such a paste, and `editorHelper.js:43-54` is the existing pattern to follow — not to reuse in place, since it is the signature surface |
| Inventing a caption representation | §5.4 |
| Inventing a second alt field, or making alt optional in the UI | §5.1, §5.2. The editor may *also* block an empty alt client-side for a better message; that is a convenience, and the seed boundary stays the enforcement |
| `?cw_image_width=` on a `media:` key | §0.4: measured not to work. If the editor needs resize, that is a new interface request, not a workaround |
| A second resolver, key parser, or `media:` regex in JS | §1.5. If Agent 2 needs the grammar client-side, ask for it to be published once rather than transcribed |
| Touching `lib/custom_markdown_renderer.rb`, `lib/markdown_renderer_url_sanitizer.rb`, `app/models/portal.rb`, or anything under `custom/app/services/documentation/media_*` | Agent 1's files |

If the interface is missing something Agent 2 needs, the answer is a request to Agent 1 via the Orchestrator —
not a local implementation that later has to be deleted.

---

## REQUESTED CHANGES

Six. Each names the exact file, the exact diff and why. Agent 1 writes none of them.

### #1 — `config/routes.rb` (Orchestrator-only): the delivery route

Insert immediately after `:519`:

```diff
   get 'hc/:slug/articles/:article_slug', to: 'public/api/v1/portals/articles#show', as: :public_portal_article
+  # The documentation media route (docs/documentation-v2/R2-MEDIA-INTERFACE.md section 4). Nested under the
+  # article so the published-or-signed-in-super-admin predicate can be applied; a glob because a `media:` key
+  # contains `/` and `.`; `format: false` because otherwise the non-greedy glob loses the extension to
+  # params[:format] (actionpack journey/nodes/node.rb:166-171 with routing/mapper.rb:116-130).
+  get 'hc/:slug/articles/:article_slug/media/*media_key', to: 'public/api/v1/portals/media#show',
+                                                          as: :public_portal_article_media, format: false
```

**Why**: §4.1. Agent 1 owns the controller but not the routes file. No collision with `:516`, `:517-518` or
`:519` — the segment counts differ (§4.1 table), so placement is for readability only.

### #2 — `lib/chatwoot_markdown_renderer.rb` (unowned): let the caller pass a resolver

```diff
-  def render_article
-    markdown_renderer = CustomMarkdownRenderer.new
+  def render_article(media: nil)
+    markdown_renderer = CustomMarkdownRenderer.new(media: media)
     doc = CommonMarker.render_doc(@content, :DEFAULT, [:table])
```

**Why**: `CustomMarkdownRenderer#image` has to reach a `Documentation::MediaResolver`, and the renderer is
constructed here with no arguments (`:14`). `CommonMarker::Renderer#initialize` is keyword-only
(`commonmarker-0.23.12/lib/commonmarker/renderer.rb:10-18`), so `CustomMarkdownRenderer` can accept
`media:` and forward the rest — that half is Agent 1's own file. `media: nil` keeps every existing caller and
every existing spec working unchanged. **The rejected alternative** is a thread-local or a `Current`
attribute, which would let the renderer resolve a portal with no visible dependency; CLAUDE.md prefers
clarity, and hidden global state in a render path is how the double-`yield` surprise in
`discovery/_ARBITRATION.md:935` happened.

### #3 — `app/controllers/public/api/v1/portals/articles_controller.rb` (unowned): construct the resolver

```diff
   def render_article_content(content)
-    ChatwootMarkdownRenderer.new(content).render_article
+    ChatwootMarkdownRenderer.new(content).render_article(
+      media: Documentation::MediaResolver.new(portal: @portal, article: @article)
+    )
   end
```

**Why**: one resolver instance per render is what makes the N+1 answer in §2.4 true. Both `@portal` and
`@article` are already set by the time `show` (`:24-27`) runs.

### #4 — a new concern, so the §0.1 predicate has one definition

New file `app/controllers/concerns/public/portal_article_visibility.rb`:

```ruby
# The predicate R2-MEDIA-CONTRACT.md section 0.1 freezes: a published article is public, and a signed-in super
# admin additionally sees a draft, which is the whole point of the preview. Extracted so the article page and
# the media route cannot drift -- `show` and `show_markdown` already disagree (R2-O1), and that is enough.
module Public::PortalArticleVisibility
  extend ActiveSupport::Concern

  included { helper_method :previewing_as_super_admin? }

  private

  def visible_articles
    previewing_as_super_admin? ? @portal.articles : @portal.articles.published
  end

  def previewing_as_super_admin?
    respond_to?(:current_super_admin) && current_super_admin.present?
  end
end
```

and in `articles_controller.rb`:

```diff
 class Public::Api::V1::Portals::ArticlesController < Public::Api::V1::Portals::BaseController
+  include Public::PortalArticleVisibility
@@
   def set_article
-    scope = previewing_as_super_admin? ? @portal.articles : @portal.articles.published
-    @article = scope.find_by!(slug: permitted_params[:article_slug])
+    @article = visible_articles.find_by!(slug: permitted_params[:article_slug])
   end
-
-  def previewing_as_super_admin?
-    respond_to?(:current_super_admin) && current_super_admin.present?
-  end
-  helper_method :previewing_as_super_admin?
```

**Why**: §4.4. The media request is a separate HTTP request, so the predicate must be evaluated twice; what
must not exist twice is the rule. Behaviour-preserving: the comments at `articles_controller.rb:77-82` stay
with `set_article`, and the `helper_method` is preserved even though a no-exclusion search found no view that
calls it. **If declined**, Agent 1 duplicates the two lines in the media controller and writes a spec
asserting the two controllers agree — worse, and the divergence that `R2-O1` already records is the argument.

### #5 — `deployment/ROLLBACK.md` (Orchestrator-only, one line, no behaviour change)

Wherever queue names are mentioned, note that `ActiveStorage::PurgeJob` and `ActiveStorage::AnalyzeJob` run on
the **`default`** Sidekiq queue, not on `active_storage_purge` / `active_storage_analysis`
(`config/sidekiq.yml:31-32`), which nothing enqueues to under `load_defaults 7.0`.

**Why**: §0.6. An operator watching the named queue for purge progress watches an empty queue. This is
documentation only; `deployment/**` is explicitly off-limits for any behaviour change and I am not proposing
one.

### #6 — a ruling, not a diff: who owns `spec/lib/markdown_renderer_security_spec.rb`

The ownership table gives Agent 1 "`spec/` files for the above", but this spec's basename matches none of
Agent 1's source files, and `:206-221` is the assertion the §7 closure must invert. Either confirm Agent 1 may
edit `:205-222`, or name the agent who does. `spec/lib/base_markdown_renderer_spec.rb:77-89` needs **no**
change and should stay untouched as the containment proof (§7.4).

### A note on the changelog media directory

The ownership table grants Agent 1 `custom/db/documentation/media/**`. §1.3's mapping is
`<corpus root>/media/<key>`, so a changelog image would live at `custom/db/changelog/media/**`, which is
inside Agent 3's tree and in nobody's media grant. **No request is made**, because the changelog corpus has
zero images (§0.1) and R2 does not need one. Recorded as **R2-O7** so the first changelog image is a decision
rather than a surprise.

---

## OPEN

| # | Item |
|---|---|
| **R2-O1** | *(contract)* `show_markdown` refuses a draft to a super admin (`articles_controller.rb:29-33`) while `show` serves one. Media follows `show`. Unchanged by this document, and now additionally the reason REQUESTED CHANGES #4 extracts the predicate |
| **R2-O2** | *(contract)* Captions have no representation in the source model. Deferred to R3. §5.4 states what Agent 2 may assume and the four things it must not do |
| **R2-O3** | *(contract)* Responsive variants need `web_image_content_types` set explicitly (`activestorage-7.2.3.2/lib/active_storage/engine.rb:49-53` shows the default is png/jpeg/gif, no webp) which is product-wide. Out of scope; originals only |
| **R2-O4** | *(contract, CONFIRMED)* Production storage is local disk in a `.gitignore`d directory with no repository backup. §6.4. The §3A.2 addition stays designed and **not approved** |
| **R2-O5** | **New.** Decorative images: the front-matter key `media.decorative` is frozen (§5.3), the branch is not implemented. The first decorative image in the corpus is the one condition that adds it |
| **R2-O6** | **New.** The resolver loads the portal's whole media set per render (§2.4). Two queries at any article size, but it scales with the *portal's* library rather than the article's. Re-measure past roughly a thousand media files; do not pre-optimise |
| **R2-O7** | **New.** `custom/db/changelog/media/**` is in no agent's ownership grant. Moot while the changelog has zero images |
| **R2-O8** | **New, UNVERIFIED.** Whether **libvips** is installed on the production host. `load_defaults 7.0` → `variant_processor = :vips` → only `ImageAnalyzer::Vips` accepts, and a missing library is swallowed with an `info` log (§0.7). Present in this container at 8.15.1. Settled by `ldconfig -p \| grep vips` on production, or one `rails runner` printing `ActiveStorage::Analyzer::ImageAnalyzer::Vips.accept?(blob)`. §3.7's `unmeasured` count makes it visible either way |
| **R2-O9** | **New, observation only.** `helper_method :previewing_as_super_admin?` (`articles_controller.rb:91`) is called by no view — no-exclusion search, every hit classified (§4.4). CLAUDE.md says remove unused code; it is preserved by REQUESTED CHANGES #4 because removing it is an unrelated change. Orchestrator's call |
| **R2-O10** | **New, observation only.** `Public::Api::V1::Portals::BaseController:55` logs `"Article: not found for slug: …"` unconditionally, including when the article **is** found. Pre-existing, in nobody's ownership, and part of why the media controller does not inherit that base (§4.3) |
