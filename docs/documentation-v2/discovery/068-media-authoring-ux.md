---
agent: 068
scope: Image and media authoring UX for documentation articles — what exists to reuse, and the authoring experience to specify
confidence: high
---

Documentation articles contain no images today. `grep -rn '!\[' custom/db/documentation/` returns **nothing**
across all 126 corpus files, and Super Admin offers no way to add one (`custom/app/dashboards/article_dashboard.rb:19`
is a 28-row textarea). So this report is not an audit of a weak feature; it is an inventory of the four
upload experiences the product already ships, and a specification that assembles a fifth out of them rather
than inventing one.

The headline finding: **a complete, production-grade article image authoring UX already exists in this
repository** — the Help Center article editor (`FullEditor.vue` + `@chatwoot/prosemirror-schema`). It has
file-picker, drag/drop, paste, external-URL rehosting, per-file progress, failure with retry/remove, cancel,
in-place drag-resize, a navigation guard for in-flight uploads, and a typed/sized allowlist enforced on every
entry point. It is unreachable from documentation authoring for exactly two reasons: its route is
account-scoped and the documentation portals are account-less, and its upload endpoint authenticates the
`:user` scope, not `:super_admin`. Neither reason is about media.

---

## 1. What exists today

### 1.1 Four upload experiences, in four different shapes

**A — The conversation composer** (`app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`).
The oldest and least reusable. `vue-upload-component` is the picker
(`app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue:5,282-307`), with
`:accept="allowedFileTypes"` from `getAllowedFileTypesByChannel` (`ReplyBottomPanel.vue:205-219`), `:drop`
bound to a computed (`:220-222,290`), `:drop-directory="false"` (`:291`) and a hard `:size="4096 * 4096"`
(`:287`). Paste is a **document-level** listener, not an editor-level one
(`ReplyBox.vue:601,624`), filtering `e.clipboardData.files` by non-zero size and by
`isFileTypeAllowedForChannel` (`ReplyBox.vue:771-806`, `app/javascript/shared/helpers/FileHelper.js:49-87`).
Upload itself is `fileUploadMixin` (`app/javascript/dashboard/mixins/fileUploadMixin.js`): a per-MIME size
ceiling (`:26-49`), `checkFileSizeLimit` (`shared/helpers/FileHelper.js:22-26`), then either ActiveStorage
`DirectUpload` to a conversation-scoped endpoint (`:65-93`) or a deferred multipart send (`:95-107`).
A composable twin exists for the new-conversation surface
(`app/javascript/dashboard/composables/useFileUpload.js:21-117`).

Its UX properties matter because they are the ones **not** to copy:
- **No progress.** `DirectUpload` is created without a `directUploadDidProgress` delegate
  (`fileUploadMixin.js:76-84`); the only feedback is the attachment row appearing when it finishes.
- **No failure affordance.** `upload.create((error, blob) => { if (error) useAlert(error) ... })`
  (`:86-92`) — a raw error string in a toast, no retry, no cancel, nothing left on screen.
- **No drop-zone visual.** `vue-upload-component`'s `drop` prop binds the handler; the only styling is a
  cursor and hover rule (`ReplyBottomPanel.vue:406-414`).
- **Preview and removal** are real but minimal: `AttachmentsPreview.vue` renders a 24px thumbnail from a
  `FileReader` data URL (`ReplyBox.vue:1110-1124`, `AttachmentsPreview.vue:56-60`), filename, size, and an
  `i-lucide-x` button that removes by index (`:24-31,78-85`).
- One dead prop to not propagate: `:data="{ direct_upload_url: '/rails/active_storage/direct_uploads', ... }"`
  (`ReplyBottomPanel.vue:292-295`) points at a route the installation explicitly forbids
  (`config/initializers/active_storage.rb:52-64`).

**B — The Help Center article editor** (`app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue`).
This is the one to extend. It is a ProseMirror editor over `fullSchema` with a CommonMark round-trip
(`ArticleMarkdownTransformer` / `ArticleMarkdownSerializer`, `FullEditor.vue:4-7,64,352`). Media behaviour:

| Capability | Evidence |
|---|---|
| Hidden `<input type="file" multiple>` + slash command `/image` | `FullEditor.vue:635-642,305,356-358` |
| **Drag and drop** at the drop position, with the caret moved to the drop coords first | `FullEditor.vue:463-481` |
| **Paste from clipboard** (files) on the editor DOM, not the document | `FullEditor.vue:487-493` |
| **Paste of an external image URL** → rehosted into the installation's own storage | `imagePastePlugin(this.handleImageUpload)` (`:105`), `handleImageUpload` (`:359-365`) |
| Type + size allowlist applied to *every* entry point, picker/drop/paste alike | `bucketFor` (`:371-397`), with the comment "Drop and paste bypass the file input's accept filter" (`:41-42`) |
| Images ≤ 4 MB, `png/jpeg/jpg/gif/webp`; `video/mp4` to the installation limit | `MAXIMUM_FILE_UPLOAD_SIZE = 4` (`:40`), `ALLOWED_IMAGE_TYPES` (`:43-49`), `maximumVideoUploadSize` (`:125-129`) |
| Uploads blocked during a window where they would be lost, with a reason | `uploadsBlockedMessage` (`:85,400-403`), set by `ArticleEditor.vue:65-70` |
| **Navigation guard** on in-flight or failed uploads | `hasPendingUploads` (`FullEditor.vue:417-425`), `ArticleEditor.vue:61,71-78` |
| Localised upload status labels injected into the editor package | `setUploadLabels` (`FullEditor.vue:141-150`) |
| In-place **drag-resize** persisted as a URL query param | `imageResizeView` (`:453`), `node_modules/@chatwoot/prosemirror-schema/src/nodeViews/imageResize.js:39-48` |

The upload *chrome* lives in the pinned package: a scrim + status pill over the image while it uploads, with
a spinner, `Uploading · 42% · 1.2 MB`, a cancel button, and — on failure — retry and remove buttons
(`node_modules/@chatwoot/prosemirror-schema/src/nodeViews/uploadOverlay.js:39-115`), progress held at 99%
while the request is open (`:65-66`), `429` distinguished from a generic failure
(`node_modules/@chatwoot/prosemirror-schema/src/plugins/uploadState.js:119-122`), and a separate inline card
for video (`uploadOverlay.js:118-137`). A blob-URL preview is inserted immediately, decoded first so the
first paint has real dimensions, and the `src` is swapped in place on completion without touching undo
history (`.../plugins/uploads.js:108-119,153-189`). `blob:` srcs are never serialized, so an autosave cannot
capture a preview (`.../schema/markdown/serializer.js:220-222`).

**C — The Platform Support attachment picker**
(`app/javascript/dashboard/routes/dashboard/help/components/AttachmentPicker.vue`). The newest and the best
*non-editor* pattern, and the one whose discipline the documentation media UI should inherit. Limits are
stated **before** the picker, not after a rejection (`:14-24,49-54,144-147`); rejection messages name the
file and the rule (`:60-75`); count, type and size are each refused separately (`:84-96`); upload is
all-or-nothing so a half-filled picker never happens (`:100-118`); each accepted file becomes a named,
sized, removable row (`:188-217`); the form carries signed blob ids, not a multipart body (`:21-23`).

**D — The single-image field.** `components-next/avatar/Avatar.vue` with `allow-upload` is the product's
one-image control: a hidden input with `accept="image/png, image/jpeg, image/jpg, image/gif, image/webp"`
(`:296`), emitting `upload` and `delete` (`:51`). The Help Center portal logo uses it
(`components-next/HelpCenter/Pages/PortalSettingsPage/PortalBaseSettings.vue:185-193,134-150`), and the
server side is the **ownership pattern worth copying**: `has_one_attached :logo`
(`app/models/portal.rb:50`), attach by signed blob id
(`app/controllers/api/v1/accounts/portals_controller.rb:67-70`), purge on delete (`:48-51`), serve
`url_for(logo)` (`app/models/portal.rb:107-113`).

### 1.2 Super Admin and file fields

Administrate does have a file field in use, twice: `Field::ActiveStorage` with a `destroy_url` proc on the
user and agent-bot avatars (`app/dashboards/user_dashboard.rb:14-18`,
`app/dashboards/agent_bot_dashboard.rb:13-18`), backed by `destroy_avatar` actions
(`app/controllers/super_admin/users_controller.rb:49-51`,
`app/controllers/super_admin/agent_bots_controller.rb:45-47`) and routes
(`config/routes.rb:607,614`). Display is a one-line custom field: `AvatarField` (`app/fields/avatar_field.rb`)
rendering `image_tag` (`app/views/fields/avatar_field/_show.html.erb`).

So the Administrate half of a media field is a solved problem *for a single attachment on a record*. What
does not exist:
- No file field of any kind on the documentation dashboards. `ArticleDashboard::FORM_ATTRIBUTES`
  (`custom/app/dashboards/article_dashboard.rb:36`) is `portal category title slug description content locale
  status position meta`.
- The only media-shaped field in documentation authoring is `meta['feature_image']`, a **hand-typed absolute
  URL** labelled "Feature image URL", changelog-only (`custom/app/fields/article_meta_field.rb:13,21,30`,
  `custom/app/views/fields/article_meta_field/_form.html.erb:5-14`). Its consumer renders it with
  `loading="lazy"` and a derived alt (`components-next/changelog-card/StackedChangelogCard.vue:59-68`) — and
  with a `v-else` branch that renders the same `<img :src="card.feature_image">` when `feature_image` is
  absent, i.e. a guaranteed broken image (`:70-81`). Pre-existing, unrelated to this program, cheap to fix.
- **Super Admin can mount Vue.** `render_vue_component` writes `#app` with `data-component-name` and
  `data-props` (`app/controllers/super_admin/application_controller.rb:33-42`); the `superadmin_pages`
  entrypoint mounts the named component (`app/javascript/entrypoints/superadmin_pages.js:8-33`), loaded on
  every Administrate page (`app/views/super_admin/application/_navigation.html.erb:11`). One view uses it
  today (`app/views/super_admin/dashboard/index.html.erb:5`). This is the extension point that makes a real
  media/editor experience in Super Admin possible without a second application.

### 1.3 The upload endpoint

One generic endpoint serves both the article editor and the portal logo:
`POST /api/v1/accounts/:account_id/upload` (`config/routes.rb:348`,
`app/controllers/api/v1/accounts/upload_controller.rb`).

- Multipart `attachment`, or `external_url` for rehosting (`:3-9`).
- External fetches go through `SafeFetch`, which is SSRF-filtered and restricted to `image/` and `video/`
  content-type prefixes with a 40 MB fallback ceiling (`lib/safe_fetch.rb:4,9,26-34`), and whose failures map
  to distinct `422`s (`upload_controller.rb:25-36`).
- The blob is created with **no owner**: `ActiveStorage::Blob.create_and_upload!(io:, filename:,
  content_type:)` (`:39-45`) — no `record`, no `attach`.
- The response is `{ file_url: url_for(blob), blob_id: blob.signed_id }` (`:47-49`). With the default
  `resolve_model_to_route`, `file_url` is an absolute, host-qualified, unauthenticated
  `/rails/active_storage/blobs/redirect/<signed_id>/<filename>` URL.
- **Filename is the client's, verbatim** (`:18,23`). ActiveStorage sanitizes it for the URL path and
  `Content-Disposition`, and the on-disk/bucket key is random, so this is not an injection problem — but it
  is not generation either: a screenshot called `Screenshot 2026-10-13 at 14.22.01.png` stays that, in the
  public URL, forever.
- Rate limit: 60 uploads per account per hour (`config/initializers/rack_attack.rb:271-275`), surfaced in the
  editor as a distinct "Upload limit reached" state (`uploadState.js:119-122`, copy at
  `app/javascript/dashboard/i18n/locale/en/helpCenter.json:49`).
- Authorization: `Api::V1::Accounts::BaseController` → `Api::BaseController` authenticates the `:user` scope
  or an access token (`app/controllers/api/base_controller.rb:4-6`) and then requires an `account_users` row
  for the current user (`app/controllers/concerns/ensure_current_account_helper.rb:23-27`). The Super Admin
  session is the Devise `:super_admin` scope (`config/routes.rb:590-593`) and `SuperAdmin < User`
  (`app/models/super_admin.rb:47`), so even if the warden scope were satisfied the account-membership check
  would not be. **There is no upload endpoint a Super Admin session can call.** This is the single hard
  blocker between the existing editor and documentation authoring.

No scheduled job purges unattached blobs (`config/schedule.yml` has no such entry; nothing in `app/jobs`
references `unattached`), so orphan blobs persist indefinitely. Documentation images will not disappear —
and nothing tracks or reclaims them either.

### 1.4 What the render path does with an image

**Client (dashboard previews, search snippets):** `app/javascript/shared/helpers/MessageFormatter.js`.
`setImageSizing` (`:5-19`) reads `cw_image_width` from the `src` and writes
`style="width: Npx; max-width: 100%; height: auto;"`; failing that, `cw_image_height` →
`style="height: Npx;"`. It runs as a core rule after `inline` (`:29-41`). `markdown-it` runs with
`html: false` (`:45`), so raw HTML in article source is escaped, not rendered. `new URL(imgSrc)` (`:8`) will
throw on a relative `src` — all current sources are absolute, so this is latent, not live.

**Server (the public portal — the one that matters for documentation):**
`ChatwootMarkdownRenderer#render_article` → `CustomMarkdownRenderer`
(`lib/chatwoot_markdown_renderer.rb:13-19`), reached from
`app/controllers/public/api/v1/portals/articles_controller.rb:26,109-111`. `CustomMarkdownRenderer#image`
(`lib/custom_markdown_renderer.rb:61-71`) emits exactly:

```
<img src="{sanitized}" alt="{children}" title="{escaped, if present}" style="width: Npx; max-width: 100%; height: auto;" />
```

- `src` passes `MarkdownRendererUrlSanitizer#sanitized_href`, which blanks `javascript:`/`vbscript:`/`file:`/
  `data:` except `data:image/(png|gif|jpeg|webp)` (`lib/markdown_renderer_url_sanitizer.rb:3-4,14-18`).
- Width comes only from `cw_image_width`, constrained to `\A(\d+)px\z` and 1–2000
  (`custom_markdown_renderer.rb:130-146`). **`cw_image_height` is ignored on the article path** — the
  client-side formatter and `BaseMarkdownRenderer` honour it (`base_markdown_renderer.rb:23-32`), the article
  renderer does not. Harmless today (nothing writes height for articles) and worth not "fixing".
- **No `loading="lazy"`. No `decoding`. No intrinsic `width`/`height` attributes. No `srcset`/`sizes`. No
  `<picture>`. No `<figure>`/`<figcaption>`.**
- Responsive behaviour is therefore entirely `max-width: 100%` plus Tailwind `prose`
  (`app/views/public/api/v1/portals/articles/_content.html.erb:6-18`). That is correct but unaided: every
  documentation image will be served at full upload resolution to a phone, and because no intrinsic
  dimensions are emitted, every image is a layout shift. There is one `loading="lazy"` precedent in the
  product (`StackedChangelogCard.vue:66`) and one in an embed template
  (`config/markdown_embeds.yml:115`), so the idea is not foreign to the codebase.
- Video is URL-driven, not upload-driven in output: an uploaded mp4 becomes a paragraph whose only child is a
  link to the file (`.../plugins/uploads.js:329-343`), and the renderer's embed table turns an `.mp4` link
  into `<video controls preload="metadata">` (`config/markdown_embeds.yml:47-56`,
  `custom_markdown_renderer.rb:54-59,164-175`). Nine other providers (YouTube, Loom, Vimeo, Arcade, Wistia,
  Bunny, CodePen, Guidejar, Gist) are configured the same way. **A documentation media story gets video for
  free** and should not build its own player.

### 1.5 Alt text and captions, end to end

The round trip supports both and the UI offers neither.

- The schema's image node carries `src`, `alt`, `title`, `width`, `uploadId`
  (`.../schema/article.js:18-43`). `alt` parses from markdown (`.../schema/markdown/parser.js:48-60`) and
  serializes back as the bracket text (`.../schema/markdown/serializer.js:242-249`).
- Nothing ever **sets** it. `insertImageFiles` inserts `{ src: objectUrl, uploadId: id }`
  (`.../plugins/uploads.js:184`); `alt` defaults to `null`. So every uploaded image serializes as
  `![](https://…png?cw_image_width=400px)` and renders as `alt=""`.
- `ImageResizeView` reads alt only to mirror it onto the DOM node (`.../nodeViews/imageResize.js:51-56`).
  There is no alt editor, no title editor, no caption. The only author-facing image control in the whole
  product is the corner resize handle (`.../nodeViews/cornerResize.js`).
- `alt=""` is, by accident, the *correct* markup for a decorative image. The authoring problem is that it is
  also the markup for an author who forgot.
- No `<figcaption>` exists anywhere in the render path (`grep` for `figcaption` across `app lib custom`
  returns one unrelated Vue component, `.../whatsapp/ManualSetupVideo.vue:35-38`). A markdown title renders
  as `title="…"` — a hover tooltip, invisible on touch, not a caption.
- The SEO audit does not look at images at all: `lib/tasks/documentation_seo_audit.rake` checks canonicals,
  titles, descriptions and hreflang (`:77,82,97-105`) and nothing else. An article full of `alt=""` images
  passes with `0 SEO errors`.

---

## 2. Constraints the existing system imposes

1. **CommonMark is the storage format, and the corpus files are the source.** Anything the authoring UI
   produces must survive `ArticleMarkdownSerializer` → `.md` file → `Documentation::ContentSeeder` →
   `CustomMarkdownRenderer`. Markdown image syntax carries exactly three things: alt, URL, title. A caption,
   a decorative flag, a srcset or a figure **has nowhere to live in a `![]()`** without either a convention
   on the URL (the `cw_image_width` precedent) or a block-level extension both renderers must learn.
2. **The editor chrome is in a pinned external package**, `@chatwoot/prosemirror-schema@1.4.5`
   (`package.json:41`), with no pnpm patch entries. Upload states, the overlay, the resize handle and the
   image node spec are all inside it. But `FullEditor.vue` already supplies its own `nodeViews`
   (`:452-454`) and its own plugin list (`:104-110`), so a Lynomia-owned image nodeView and plugins can be
   added **in this repo** without forking the package. Changing the *schema* (a new caption/figure node)
   cannot.
3. **The documentation portals are account-less and the dashboard editor is account-scoped.**
   `Documentation::Library.portals` is `Portal.platform.active` (`custom/app/services/documentation/library.rb:37-39`),
   while the dashboard resolves portals as `Current.account.portals`
   (`app/controllers/api/v1/accounts/portals_controller.rb:10`,
   `app/controllers/api/v1/accounts/articles_controller.rb:91`). Reusing `FullEditor.vue` for documentation
   means either mounting it in Super Admin (via `render_vue_component`) or giving platform portals a
   Super-Admin-scoped API. It does not mean copying the component.
4. **No upload endpoint answers a Super Admin session** (§1.3). Everything else in this specification is
   downstream of solving that.
5. **Images are referenced by absolute, host-qualified URL.** `url_for(blob)` embeds `FRONTEND_URL`
   (`config/environments/production.rb:105`). A corpus `.md` file committed to source control would carry
   this installation's host and a signed blob id — not portable to another install, not reviewable in a
   diff, and meaningless in a fresh database. See §5.1; this is an arbitration item for Agent 000, not a
   decision for this report.
6. **Rate limit of 60 uploads/account/hour** (`rack_attack.rb:271-275`). A documentation sprint that
   screenshots thirty articles will hit it. The editor already surfaces it as a distinct state; a
   Super-Admin-scoped endpoint needs its own throttle entry, not an exemption.
7. **`html: false` / no sanitizer on the article path.** Raw `<img>` HTML is not an authoring route; images
   must come through markdown syntax. (Agents 065, 081, 084 own the sanitization question; this report
   assumes nothing about its outcome and specifies nothing that depends on raw HTML.)
8. **RTL.** The portal layout uses logical properties (`ltr:`/`rtl:` variants,
   `app/views/public/api/v1/portals/documentation_layout/_sidebar.html.erb:15`) but the inline `style` the
   image renderer emits is width-only and direction-neutral — fine. Any alignment or caption feature must
   use logical properties, not `left`/`right`. Agent 072 owns the wider RTL question.

---

## 3. Findings

**F1 — The authoring experience to specify already exists; it is the plumbing that does not.** Eleven of the
fourteen behaviours this brief asks for are implemented, tested and shipping in `FullEditor.vue` and its
package. Only required alt text, the decorative escape hatch, and captions are genuinely absent. Any plan
that rebuilds upload, drag/drop, paste, progress, failure, retry, cancel or preview is duplicating working
code. (`FullEditor.vue:356-493`, `uploadOverlay.js:39-137`, `uploads.js:108-189`)

**F2 — Required alt text is the only part of this scope with no precedent anywhere in the product.** Nothing
in the repository requires, validates, prompts for or audits alternative text — not the editor
(`imageResize.js:51-56`), not the schema (`article.js:23-27`), not the insert path (`uploads.js:184`), not
the renderer (`custom_markdown_renderer.rb:66`), not the SEO audit
(`documentation_seo_audit.rake:77,97-105`). This is the one new UI primitive the program needs.

**F3 — Captions have nowhere to go without a format decision.** `title` is a tooltip
(`custom_markdown_renderer.rb:67`); there is no `<figure>`/`<figcaption>` in the render path. A caption
therefore costs either (a) a renderer convention — e.g. promote the markdown title to a `<figcaption>` when
the image is alone in its paragraph, which `CustomMarkdownRenderer` is already structured to detect
(`surrounded_by_empty_lines?`, `:148-162`, used today for embeds), or (b) a new schema node, which means
touching the pinned package. (a) is reversible, costs one renderer method, and keeps the corpus plain
CommonMark readable by any other tool.

**F4 — Responsive output is `max-width: 100%` and nothing else.** No lazy loading, no intrinsic dimensions,
no `srcset`, served at upload resolution (`custom_markdown_renderer.rb:61-71`,
`_content.html.erb:6-18`). Every image is a CLS event and a full-resolution mobile download. The two cheap
fixes — `loading="lazy"` and emitted intrinsic `width`/`height` — are renderer-only, need no authoring UI,
and have in-product precedent (`StackedChangelogCard.vue:66`). `srcset` needs ActiveStorage variants and is
Agent 066's and 080's territory, not an authoring question.

**F5 — Ordering is a non-problem.** Images are inline nodes in a CommonMark document; their order is the
document order, maintained by ProseMirror's own drag/drop (`FullEditor.vue:463-481`). There is no gallery,
no media list, nothing to sort. Specifying an ordering UI here would be the first step toward the DAM this
program is forbidden to build.

**F6 — "Safe filename generation" is half-solved and half-mis-stated.** ActiveStorage already prevents the
dangerous half: random storage keys, sanitized filenames in URL and `Content-Disposition`. What is missing
is the *useful* half — a descriptive, slug-derived filename for image SEO instead of
`Screenshot 2026-10-13 at 14.22.01.png` (`upload_controller.rb:18,23`). That is a one-line change at the
blob-creation boundary, not a filename-safety feature.

**F7 — Nothing owns a documentation image.** Blobs are created with no `record`
(`upload_controller.rb:39-45`), `Article` has no attachment (`app/models/article.rb` schema block, lines
1-35), and no job reclaims unattached blobs (`config/schedule.yml`). The portal logo shows the pattern that
fixes this in one model line plus three controller lines (`app/models/portal.rb:50`,
`portals_controller.rb:48-51,67-70`). Charter §8.3 asks what an article's image is attached to; the answer
already has a template in the repository.

**F8 — The limits-first discipline exists and should be the house rule.** `AttachmentPicker.vue:14-24`
states the rule before the picker and refuses with the file's name and the rule that failed. `FullEditor.vue`
does the opposite: it alerts after rejection (`:371-397`), with the type message not naming the file
(`helpCenter.json:55`). For documentation, where an author uploads twenty screenshots in a sitting, the
Platform Support pattern is the better one, and it is in-repo copy, not invention.

**F9 — Copy already exists for most of this.** `helpCenter.json:44-58` holds `UPLOADING`, `UPLOAD_FAILED`,
`RATE_LIMITED`, `RETRY`, `REMOVE`, `CANCEL`, `ERROR_FILE_SIZE`, `ERROR_ATTACHMENT_FILE_SIZE`,
`ERROR_UNSUPPORTED_TYPE`, plus two strings with **no consumer at all** — `ERROR_FILE_FORMAT` and
`ERROR_FILE_DIMENSIONS` ("Image dimensions should be less than 2000 x 2000"); `grep` finds no reference in
any `.vue` or `.js`. Either dimension validation was removed or never landed. Documentation media needs
dimension handling (a 4000px-wide screenshot in a 700px column), and the string is already written.

---

## 4. Options

### 4.1 The specified authoring experience, item by item

Each row says what the behaviour is, where it comes from, and whether it extends something or is new.

| # | Item | Specification | Extends / New |
|---|---|---|---|
| 1 | **Upload** | Hidden `multiple` file input behind a toolbar button and a `/image` slash command; accepted types stated above the editor, not after a rejection | **Extends** `FullEditor.vue:305,356-358,635-642`; adopt the limits-first presentation of `AttachmentPicker.vue:14-24,144-147` |
| 2 | **Drag and drop** | Drop at the drop position, caret moved there first, directories refused | **Extends** `FullEditor.vue:463-481`. Add a drop-target highlight — **new primitive**, nothing in the product draws one (§1.1 A) |
| 3 | **Paste from clipboard** | Editor-level `paste` for files; pasted external image URLs rehosted into the installation's storage so no article depends on a third-party host | **Extends** `FullEditor.vue:487-493`, `imagePastePlugin` (`:105,359-365`), `SafeFetch` (`upload_controller.rb:21-37`) |
| 4 | **Progress** | Blob preview inserted immediately at real decoded dimensions; scrim + pill with spinner, percent and size; held at 99% until the response lands | **Extends** `uploadOverlay.js:99-115,65-66`, `uploads.js:153-189`. Nothing new |
| 5 | **Failure** | Image stays on screen in an error state with retry and remove; `429` reads as "upload limit reached", distinct from a generic failure | **Extends** `uploadOverlay.js:38-56,87-94`, `uploadState.js:119-122`, copy at `helpCenter.json:48-52` |
| 6 | **Cancel** | Cancel an in-flight upload; aborts the request and removes the preview without polluting undo history | **Extends** `uploadState.js:64-81`, `uploads.js:70-77` |
| 7 | **Preview** | The image itself, in place, at its real size — not a filename row. The document *is* the preview | **Extends** `imageResizeView` (`FullEditor.vue:452-454`) |
| 8 | **Replace** | Select the image, pick/drop a new file over it; the node keeps its alt, caption and width and only `src` changes | **New**, but small: `setNodeMarkup` with a preserved attrs spread, exactly as the upload swap already does (`uploads.js:108-119`) |
| 9 | **Remove** | Select and delete, as any node; plus the explicit remove button in the error state | **Extends** existing behaviour. Nothing new |
| 10 | **Ordering** | Document order, maintained by ProseMirror drag/drop. No gallery, no sort UI (F5) | **Extends**. Explicitly **not** a new surface |
| 11 | **REQUIRED alt text** | A required field on the image, prompted at insertion and shown in a selected-image panel. Serializes as the markdown bracket text. Publishing is blocked while any image in the article has neither alt text nor the decorative flag | **NEW — the one substantial new UI primitive.** No alt affordance exists anywhere (F2). Enforcement reuses `documentation_seo_audit.rake` (`:77`) as the article-level gate and the editor panel as the in-line one |
| 12 | **"This image is decorative" escape hatch** | An explicit checkbox beside the alt field. Checking it satisfies the requirement and serializes `![](…)` — `alt=""`, which is already the correct decorative markup (§1.5). The flag is *recorded by its absence of alt*, so nothing new goes into the file format | **NEW** (the control). **Extends** the output: `custom_markdown_renderer.rb:66` already emits `alt=""` |
| 13 | **Caption** | Optional, authored in the same panel, stored as the markdown title. The renderer promotes it to `<figcaption>` inside a `<figure>` when the image is alone in its paragraph; otherwise it stays a `title` attribute | **NEW** in the renderer (one method), **extends** `CustomMarkdownRenderer#surrounded_by_empty_lines?` (`:148-162`), which already drives the same "alone in its paragraph" decision for embeds. Format decision — see §4.2 |
| 14 | **Safe filename generation** | Derive the stored filename from the article slug plus a short counter, keeping the original extension; keep the client's name only in metadata | **NEW**, one line at `upload_controller.rb:18,23`. Safety is already handled by ActiveStorage (F6); this is for image SEO and legible URLs |
| 15 | **Type validation** | `png/jpeg/jpg/gif/webp` for images, `mp4` for video, enforced on picker, drop and paste alike. **SVG stays refused**, as it is today | **Extends** `FullEditor.vue:43-50,371-397`. Server-side the same list must gate the Super-Admin endpoint — `SafeFetch`'s `image/`+`video/` prefixes (`lib/safe_fetch.rb:4`) are too broad to be the only check. Agent 084 owns SVG |
| 16 | **Size validation** | 4 MB per image, installation limit for video, both stated before the picker; plus a max-dimension rule (the unused 2000×2000 string, F9) with automatic downscale rather than refusal | **Extends** `FullEditor.vue:40,371-397`, `checkFileSizeLimit`. Dimension handling is **new** — the copy exists, the code does not |
| 17 | **Responsive output** | Add `loading="lazy"` and intrinsic `width`/`height` to the article renderer's `<img>`; keep `max-width:100%; height:auto` | **Extends** `custom_markdown_renderer.rb:61-71`. `srcset`/variants is a separate decision owned by 066/080 and is **not** required for the authoring UX to ship |
| 18 | **Ownership** | `has_many_attached :images` on `Article`, attached by signed blob id at save, purged with the article | **Extends** the portal-logo pattern verbatim (`app/models/portal.rb:50`, `portals_controller.rb:48-51,67-70`). Feeds charter §8.3 |
| 19 | **A Super-Admin upload endpoint** | The prerequisite for all of the above: an upload action in the `super_admin` namespace, reusing `UploadController`'s body, authorised by the `:super_admin` Devise scope, with its own Rack::Attack entry | **NEW route, extended controller.** Not a new service. This is the actual blocker (§1.3, constraint 4) |

**New UI primitives required — the complete list.** Everything else on this page already exists.

1. **The alt-text / decorative / caption panel for a selected image.** A Lynomia-owned image nodeView
   supplied through `FullEditor.vue`'s existing `nodeViews` option (`:452-454`), so the pinned package is not
   forked. Must work in RTL with logical properties (constraint 8).
2. **A drop-target highlight.** No drop-zone visual exists in the product at all (§1.1 A, and the package's
   stylesheet has no drag/drop rules).
3. **A publish-time "images missing alt text" blocker** in the authoring surface — new UI, but the check
   itself belongs in the existing SEO audit so CI and the editor agree.

Deliberately **not** specified, because they are the DAM this program forbids: a media library, a reusable
asset browser, folders, tags, search over images, cross-article reuse, usage counts, bulk operations, image
editing or cropping.

### 4.2 Decisions that need Agent 000

**D1 — Where the authoring surface lives.** Three real options.

| Option | What it means | Trade-off |
|---|---|---|
| **(a) Mount `FullEditor.vue` in Super Admin** via `render_vue_component` (`super_admin/application_controller.rb:33-42`, `entrypoints/superadmin_pages.js:8-33`) | Super Admin stays the authoring home; the whole media UX arrives at once; `superadmin` keeps one Devise scope and one authorization story | Needs the new `:super_admin` upload endpoint (item 19); `FullEditor` reads `this.$route.params.portalSlug` (`:361,428`) and `this.$store` — both need parameterising. Bundle cost on Administrate pages |
| **(b) Give platform portals an account-scoped door** so the existing dashboard Help Center editor can reach them | Zero new editor code; zero new upload code | Breaks the invariant that platform portals have `account_id = NULL` (`01-current-system.md` §10) for tenant isolation. **Do not** |
| **(c) A documentation authoring route inside the dashboard app**, super-admin-gated, reading platform portals through `Documentation::Library` | Full dashboard component library, routing and store available; no Administrate constraints | Largest build; two authoring surfaces for one `Article` unless Administrate's article form is retired |

**Recommendation: (a).** It is the smallest change that delivers items 1–10 unmodified, it keeps one
authoring surface, and the Vue-in-Administrate bridge it depends on already exists and is already loaded on
every Super Admin page. (c) is the better end state if the editor grows beyond media — Agent 067's call, not
this report's.

**D2 — How a caption is stored.** Options: the markdown title promoted to `<figcaption>` when the image is
alone in its paragraph (recommended — no format extension, plain CommonMark, one renderer method, mirrors the
existing embed decision at `custom_markdown_renderer.rb:148-162`); a new ProseMirror `figure` node (clean
model, requires forking the pinned package, and the markdown it serializes is no longer something another
tool reads the same way); or an HTML comment convention like the existing `<!--cw-colwidths:…-->`
(`custom_markdown_renderer.rb:17,22-27`) — precedented, but it makes the corpus files less readable and the
existing marker already has to be stripped in three places (`MessageFormatter.js:73-74`).

**D3 — Where alt-text enforcement lives.** The editor panel is the author's feedback loop; the gate must be
`lynomia:docs:seo_audit`, which already exits 1 on an error (`documentation_seo_audit.rake:1-11`) and is
already a release blocker by construction. One new check — "article contains an image with neither alt text
nor an explicit empty alt" — gives the editor, the operator and CI the same answer. Note the audit cannot
distinguish "decorative" from "forgotten" if the escape hatch is encoded as `alt=""`; if D2 chooses a
convention-based caption, the same convention can carry an explicit decorative marker. Flagged, not resolved.

**D4 — Portability of image URLs across environments.** Arbitration item, stated in §5.1.

---

## 5. Risks

**5.1 — Absolute, installation-specific image URLs in source-controlled Markdown (blocker-shaped).** Every
upload yields `https://<FRONTEND_URL>/rails/active_storage/blobs/redirect/<signed_id>/<filename>`
(`upload_controller.rb:48`, `config/environments/production.rb:105`). If repository Markdown is canonical
(charter §8.1), committing that URL into `custom/db/documentation/en/<section>/<key>.md` ties the corpus to
one host and one database's blob ids: unresolvable on a fresh install, meaningless in a code review, and
broken the moment the installation's host changes. If the database is canonical, the corpus files stop being
the source and §8.1 is decided by the media design rather than on its own merits. **Agent 000 must resolve
this before any media implementation starts.** A middle path exists — store a stable relative reference
(e.g. `/docs/media/<slug>/<filename>`) and resolve it to a blob at render time — but that is a new
indirection layer and therefore a charter §2 question, not a detail.

**5.2 — Forking the pinned editor package.** `@chatwoot/prosemirror-schema@1.4.5` is an external dependency
(`package.json:41`) with no patch entries. Any change to the image *node spec* — a caption node, a
`decorative` attribute — means forking or vendoring, and the package also serves the conversation composer
and the Help Center editor, so a fork regresses two shipping surfaces. The nodeView escape hatch
(`FullEditor.vue:452-454`) avoids this for UI, not for schema. Design the alt/caption feature to need no
schema change.

**5.3 — The 60/hour upload throttle meets documentation work.** `rack_attack.rb:271-275` is sized for agents
attaching files to conversations. An author illustrating a section will exceed it, and the failure surfaces
as the generic rate-limit state. A Super-Admin endpoint needs its own limit set from documentation reality,
not inherited.

**5.4 — Unowned blobs, unbounded.** Until item 18 lands, every documentation image is an orphan blob with no
owner, no reference count and no reclamation (`upload_controller.rb:39-45`, `config/schedule.yml`). A corpus
several times its current size, re-illustrated over time, accumulates unreferenced images forever. Attaching
images to the article is the fix; a sweeper is not, and a sweeper that purges unattached blobs would also
purge legitimate images attached to nothing. **Do not add a sweeper before ownership.**

**5.5 — Required alt text becomes theatre if the escape hatch is one click.** A decorative checkbox beside a
required field is the correct accessibility design *and* the easiest way to dismiss the requirement. The
risk is not technical: it is that the corpus ends up uniformly `alt=""` and passes every audit. Mitigation is
product, not code — the decorative option should be visibly the exception (and screenshots of the product,
which is what documentation images almost always are, are never decorative).

**5.6 — No sanitizer is proven on the article render path.** `01-current-system.md` §5 flags this and agents
065/081/084 own it. This specification deliberately depends on nothing beyond markdown `![]()` syntax and the
existing `sanitized_href` allowlist (`markdown_renderer_url_sanitizer.rb:14-18`), so its surface does not
widen whatever those agents conclude. One consequence to carry forward: `sanitized_href` permits
`data:image/(png|gif|jpeg|webp)` (`:4`), so a pasted data-URI image bypasses the upload pipeline, every size
and type check, and lands inline in the corpus file. Not reachable through the UI today; reachable the moment
paste handling is widened carelessly.

**5.7 — Two renderers that disagree.** The client formatter honours `cw_image_height`; the article renderer
does not (`MessageFormatter.js:17-18` vs `custom_markdown_renderer.rb:130-146`). Today no article sets
height, so nothing breaks. Any new sizing or caption convention must land in **both** `CustomMarkdownRenderer`
and `MessageFormatter.js`, or the dashboard preview and the public portal will show different documents —
and the preview is what the author trusts.

---

## Not checked

- Whether the Devise `:super_admin` warden scope satisfies `authenticate_user!` in `Api::BaseController`
  (`:6`). The account-membership check (`ensure_current_account_helper.rb:23-27`) makes the endpoint
  unusable for platform-portal authoring either way, so the finding stands; the precise failure mode does
  not.
- ActiveStorage variant/`libvips` availability for a future `srcset` — Agent 066's scope
  (`config/application.rb:71` disables previewers; `deployment/deploy.sh` stage 4b asserts libvips).
- Blob URL authorization and expiry semantics — Agent 083's scope.
- Whether `ERROR_FILE_FORMAT` / `ERROR_FILE_DIMENSIONS` (`helpCenter.json:56-57`) once had a consumer; I
  confirmed only that none exists on this branch.
- Anything requiring a database, a server or a running build: not run, per §6.1.
