---
agent: 067
scope: Editor technology evaluation for the Super Admin documentation editor — decided against this product's constraints, measured, not against popularity
confidence: high
---

A note on citations. Claims about the editor engine cite
`node_modules/@chatwoot/prosemirror-schema/src/...:LINE`. That is not a transient artefact: the package
publishes its `src/` tree (`node_modules/@chatwoot/prosemirror-schema/package.json`, `"files": ["src/*"]`),
the repository imports from it directly (`app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue:24-27`),
and `package.json:41` pins the version exactly at `1.4.5`, so those lines are the code this installation ships.

Round-trip numbers in §3 were measured by loading the pinned package in-process and running the real
`ArticleMarkdownTransformer` → `ArticleMarkdownSerializer` pair over all 126 corpus files. No database, no
Rails, no network, no writes. The HTML comparison uses `markdown-it` in CommonMark+tables mode as a stand-in
for `CommonMarker.render_doc(content, :DEFAULT, [:table])`; it is a proxy, and I say where that matters.

---

## 1. What exists today

### 1.1 The authoring surface, and the editor that is already in the building

Super Admin authors documentation in a textarea: `content: Field::Text.with_options(rows: 28)`
(`custom/app/dashboards/article_dashboard.rb:19`), on the form attribute list
`portal category title slug description content locale status position meta` (`article_dashboard.rb:36`).

The dashboard's own header states the premise this report has to test:

> `content` is CommonMark, the same source format the dashboard's editor produces and the same the public
> renderer consumes (ChatwootMarkdownRenderer#render_article) — a textarea here is the same content, not a
> lesser one (`custom/app/dashboards/article_dashboard.rb:8-10`)

The second half is true. **The first half is false, and that is the central finding of this report** (§3.1).

"The dashboard's editor" is real and it is a full CommonMark article editor against the *same* `articles.content`
column:

| Piece | Path |
|---|---|
| Editor component | `app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue` (690 lines) |
| Authoring page | `app/javascript/dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditor.vue:233-243` |
| Engine | `@chatwoot/prosemirror-schema@1.4.5` (`package.json:41`), MIT (`node_modules/@chatwoot/prosemirror-schema/LICENSE`) |
| Markdown in | `new ArticleMarkdownTransformer(fullSchema).parse(content)` (`FullEditor.vue:64`) |
| Markdown out | `ArticleMarkdownSerializer.serialize(editorView.state.doc)` (`FullEditor.vue:352`) |
| Enabled toolbar | `ARTICLE_EDITOR_MENU_OPTIONS` — strong, em, strike, link, undo, redo, lists, h1–h3, imageUpload, code, insertTable, video, horizontalRule (`app/javascript/dashboard/constants/editor.js:174-191`) |

It is not reachable for documentation today, and that is by design, not oversight: the dashboard help centre
reads `Current.account.portals`, the documentation portals are platform-owned with `account_id = NULL`, and
Super Admin's `scoped_resource` is `Article.where(portal: Documentation::Library.portals)`
(`custom/app/controllers/super_admin/articles_controller.rb:30`). Two editors, one column, disjoint rows.

### 1.2 What is already in `package.json`, and what is not

The brief asks what is already bundled. The answer is unambiguous.

**Present and shipped in production bundles:**

| Package | Where declared | Gzipped ESM |
|---|---|---|
| `@chatwoot/prosemirror-schema` 1.4.5 (exact pin) | `package.json:41` | 47 KB |
| the full ProseMirror stack — `model`, `view`, `state`, `transform`, `markdown`, `tables`, `menu`, `commands`, `history`, `inputrules`, `keymap`, `schema-list`, `dropcursor`, `gapcursor`, `utils` | transitively via the above; `prosemirror-model` also a devDependency (`package.json:147`), and `prosemirror-view`/`prosemirror-model` carry pnpm overrides (`package.json:173,177`) | 174 KB total |
| `markdown-it` 14.3.2 + `markdown-it-link-attributes`, `markdown-it-sup` | `package.json:88` | 44 KB |
| `dompurify` 3.4.16, `vue-dompurify-html` 5.3.0 | `package.json:77,105` | — |
| `highlight.js` 11.10.0 + `@highlightjs/vue-plugin` | `package.json:80` | — |

Every one of those is MIT, as is the repository (`package.json:"license": "MIT"`). No licence question arises.

**Absent from the lockfile entirely:** tiptap, quill, monaco, easymde, toast-ui, lexical, trix, slate,
editorjs, ckeditor, tinymce, milkdown, remirror, bytemd — zero occurrences each in `pnpm-lock.yaml`.

**One near-miss worth stating honestly.** CodeMirror 6 *is* in the lockfile (`@codemirror/view@6.34.1`,
`state`, `language`, `commands`, `lint`, `lang-json`, `theme-one-dark`), but only as a transitive dependency
of `@histoire/controls@0.17.17`, itself under the `histoire` **devDependency** (`package.json` devDependencies).
It appears in no production entrypoint. Using it would mean promoting a transitive devDependency to a direct
production dependency — that is adding a dependency, not reusing one, and it should not be scored as reuse.

**Ruby side:** `commonmarker (0.23.12)` (`Gemfile.lock:174`) and `administrate >= 0.20.1` (`Gemfile:97`).
`actiontext (7.2.3.2)` is present transitively via Rails (`Gemfile.lock:36`) but **`trix` is absent from
`pnpm-lock.yaml`**, so ActionText has no editor asset here. Reaching for ActionText would mean adding Trix
*and* accepting HTML storage, which §2.2 shows the render path rejects.

### 1.3 The render path the editor must feed (constraint 5)

`render_article` is `CommonMarker.render_doc(@content, :DEFAULT, [:table])` through `CustomMarkdownRenderer`,
then `html_safe` with a `Rails/OutputSafety` disable (`lib/chatwoot_markdown_renderer.rb:13-19`), called from
`app/controllers/public/api/v1/portals/articles_controller.rb:109-110`.

`CustomMarkdownRenderer` is **already co-designed with the ProseMirror article editor**. This is not an
inference; the file says so:

| Renderer behaviour | Evidence | The editor counterpart it exists for |
|---|---|---|
| `TABLE_CELL_MIN_WIDTH_PX = 50`, commented *"Matches `columnResizing({ cellMinWidth: 50 })` in @chatwoot/prosemirror-schema"* | `lib/custom_markdown_renderer.rb:14-16` | `columnResizing({ cellMinWidth: 50 })` in `node_modules/@chatwoot/prosemirror-schema/src/index.js` |
| `COLWIDTHS_COMMENT` captured and consumed, commented *"The article editor serializes column widths as a `<!--cw-colwidths:...-->` HTML comment immediately before each resized table"* | `lib/custom_markdown_renderer.rb:17-27` | `serializeColwidths` → `state.write(colwidthMarker)` in `src/schema/markdown/serializer.js` |
| `parse_sup` turns `^x^` into `<sup>` | `lib/custom_markdown_renderer.rb:43-52,211-219` | `superscript` mark (`src/schema/article.js:70`), `markdown-it-sup` in the parser |
| `extract_image_width` reads `cw_image_width` from the image URL | `lib/custom_markdown_renderer.rb:130-132` | `image` serializer appends `cw_image_width=` (`src/schema/markdown/serializer.js`) |
| `apply_embed_width` reads `cw_video_width` from the link URL, commented *"The editor stores a resized embed's width (cw_video_width) on the link"* | `lib/custom_markdown_renderer.rb:174-185` | `embedPreviewPlugin` (`FullEditor.vue:107`) |

That is five independent server-side features whose only consumer is this editor's output dialect. The render
path is not neutral ground that any editor could be dropped into; it is **already this editor's render path**.

### 1.4 Super Admin asset architecture (constraint 4, read first-hand)

The brief asks whether Administrate pages have a build step. **In this installation they do.**

- `app/views/layouts/super_admin/application.html.erb:25-26` emits `vite_client_tag` and
  `vite_javascript_tag 'superadmin'` on every Administrate page.
- `app/views/super_admin/application/_navigation.html.erb:11` additionally emits
  `vite_javascript_tag 'superadmin_pages'`.
- `app/javascript/entrypoints/superadmin_pages.js` is **a generic Vue-3 mounting harness for Administrate
  pages**: it reads `#app`'s `data-component-name` and `data-props`, looks the name up in a `ComponentMapping`,
  `createApp`s it, installs `VueDOMPurifyHTML`, and mounts (`superadmin_pages.js:5-11,13-25,27-34`).
- The deploy builds it: stage 6 runs `pnpm vite build` and asserts the manifest exists
  (`deployment/deploy.sh:284-285`). `vite-plugin-ruby` picks up every file in `app/javascript/entrypoints/`
  (`config/vite.json`, `vite.config.ts`).
- Administrate's own JS is separate and unchanged (`app/views/super_admin/application/_javascript.html.erb:10-12`).

**The harness currently has zero mount points.** `grep` for `data-component-name`, `data-props` or `id="app"`
across `app/views/super_admin` and `custom/app/views/super_admin` returns nothing; `PlaygroundIndex` and
`DashboardIndex` (`app/javascript/superadmin_pages/views/*/Index.vue`) are dormant. So the mechanism ships, is
already loaded on every Super Admin page, and adding the first mount point collides with nothing.

The field-level extension point is equally established by precedent: `ArticleMetaField`
(`custom/app/fields/article_meta_field.rb`) plus `custom/app/views/fields/article_meta_field/_form.html.erb`
renders arbitrary markup inside an Administrate form and declares `self.permitted_attribute`
(`article_meta_field.rb:33-35`). A `content` field would follow the same shape.

### 1.5 Media (constraints 4 and 6)

`FullEditor`'s uploads go to `articles/attachImage` → `uploadFile` → `POST /api/v1/accounts/:account_id/upload`,
with the account id taken from `window.location.pathname.split('/')[3]`
(`app/javascript/dashboard/helper/uploadHelper.js:27-30,36`). That controller inherits
`Api::V1::Accounts::BaseController` (`app/controllers/api/v1/accounts/upload_controller.rb:1`).

**Neither half of that works from Super Admin.** The path is `/super_admin/articles/:id/edit`, so
`split('/')[3]` yields garbage; and a `SuperAdmin` session is not an account user, so the account-scoped
controller would reject it. The documentation portals have `account_id = NULL` by design, so there is no
account to borrow.

The response shape is also a problem waiting downstream: `render_success` returns `url_for(file_blob)`
(`upload_controller.rb:48`), a permanent blob URL. The Platform Support module in this same Super Admin already
wrote down the opposite rule — *"THE LINK IS THE AUTHORIZED ROUTE, never `rails_blob_path` and never a signed
id. Blob URLs do not expire in this installation, so a signed id rendered into a page is a permanent bearer
token for that blob"* (`app/views/super_admin/platform_support/_attachments.html.erb:4-7`). The editor's image
serializer writes whatever `src` it is handed straight into stored Markdown, where it is permanent.

Current state of the corpus: **zero images.** `grep -rn '!\[' custom/db/documentation/` returns nothing across
all 126 files. §9.8 of `01-current-system.md` called this "an absent one"; it is now counted.

### 1.6 Storage format and source of truth (constraint 2)

`articles.content` is `text` (`db/schema.rb:209`). The seeder writes `content: body` where `body` is
`match.post_match.strip` — everything after the YAML front matter, verbatim
(`custom/app/services/documentation/content_seeder.rb:96,126-131`). So the stored value *is* the file's
CommonMark body, byte for byte, and `content` is the only round-trip surface an editor touches. Front matter
maps to columns and `meta` and is not the editor's business.

`draft_title` and `draft_content` columns exist (`db/schema.rb:220-221`) and the dashboard editor uses them
(`ArticleEditor.vue:45-52`). `ArticleDashboard::FORM_ATTRIBUTES` exposes neither (`article_dashboard.rb:36`),
so Super Admin has a draft mechanism in the schema that it ignores. That is free ground for agent 069.

---

## 2. Constraints the existing system imposes

### 2.1 CommonMark round-trip is not a preference, it is a transitivity requirement

Three writers touch one column. `Documentation::ContentSeeder` writes from files and compares `changed?` to
count created/updated/unchanged (`content_seeder.rb:78-80`). An editor writes from a browser. The public
renderer reads. If the editor's `serialize(parse(x)) ≠ x`, then every article an operator merely *opens and
saves* diverges from its file, the next `rails documentation:content` run reports it "updated" and overwrites
it, and the operator's intent and the file's intent trade places on every deploy. §8.1 of the charter calls
two writers that overwrite each other forbidden. **A lossy editor makes every source-of-truth option worse,
including "database canonical"** — because the corpus would then have to be regenerated *from* the database,
and the regeneration is the lossy direction.

### 2.2 The render path positively rejects HTML storage

With `:DEFAULT` options and no `:UNSAFE`, commonmarker emits a literal `<!-- raw HTML omitted -->` for every
raw HTML block and inline
(`vendor/bundle/ruby/3.4.0/gems/commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb:110-127`).
`CustomMarkdownRenderer#html` intercepts only the colwidths marker and delegates everything else to that
`super` (`lib/custom_markdown_renderer.rb:22-27`).

Two consequences, both load-bearing:

1. **An HTML-storing editor does not merely change the source of truth — its output renders as nothing.**
   Trix/ActionText, Quill, TinyMCE and CKEditor all store HTML. On the existing public portal their output
   would come out as a string of `<!-- raw HTML omitted -->` comments. Adopting one means switching
   `render_article` to `:UNSAFE` *and* introducing the sanitizer that `01-current-system.md` §5 could not find
   — i.e. taking on the program's single largest security question as a prerequisite rather than a review item.
   That is not a trade-off to weigh; it is a disqualification.
2. The corpus has **no raw HTML at all** (`grep -rlE '<(div|span|br|img|table|sup|iframe|p|a |b>|strong|details|summary)' custom/db/documentation/` → nothing; `grep -rln '<!--'` → nothing). So the editor parser's
   `html: false` (`src/schema/markdown/articleParser.js:41`) destroys nothing that exists today. Noted so that
   nobody treats it as a blocker; it is not.

### 2.3 Arabic is a text constraint and a chrome constraint, and they have different answers

Measured over all 63 Arabic files: **183,200 Arabic codepoints in, 183,200 out, delta 0**, zero backslash
escapes newly placed before Arabic letters or `،؟؛`, zero bidi control characters added or removed. The
engine's text layer is Arabic-clean. The structural defects in §3 hit Arabic and English identically — they
are not RTL defects.

The chrome is a different story and it is worse than "unverified":

- The editor *is* RTL-aware when a direction exists: `FullEditor.vue:214` reads
  `getComputedStyle(this.$refs.editor).direction === 'rtl'` to flip the slash menu, and
  `node_modules/@chatwoot/prosemirror-schema/src/styles/base.scss:341` carries a `[dir="rtl"] &` rule.
- **Super Admin never sets a direction.** `app/views/layouts/super_admin/application.html.erb:16` is
  `<html lang="...">` with no `dir`, and `grep -rln 'rtl|direction'` over
  `app/javascript/dashboard/assets/scss/super_admin/` returns nothing. So an Arabic article would be edited in
  LTR chrome whatever the engine can do.
- **The public documentation portal does not set `dir` either.**
  `app/views/layouts/portal.html+documentation.erb:2` is `<html lang="<%= html_lang_attribute(I18n.locale) %>">`,
  and `grep -rn 'dir=' app/views/public/api/v1/portals/` returns nothing — while
  `documentation_layout/_sidebar.html.erb:15` is full of `rtl:` Tailwind variants that need a `dir="rtl"`
  ancestor to fire. Those variants are dead today.

The practical consequence for this decision: **"RTL preview" cannot be delivered by an editor choice**, because
there is no RTL portal to preview. The `dir` fix belongs upstream of any editor and is the same one-attribute
fix whichever editor wins. Flagged to 061, 072 and 099.

### 2.4 What the editor may produce is bounded by the renderer, and the bound is already breached

`render_article` passes extensions `[:table]` only (`lib/chatwoot_markdown_renderer.rb:15`), while
`render_message` passes `[:strikethrough, :autolink]` (`:8`). But `ARTICLE_EDITOR_MENU_OPTIONS` includes
`'strike'` (`app/javascript/dashboard/constants/editor.js:177`), the schema has a `strike` mark
(`src/schema/article.js:78`) and the serializer writes `~~x~~` (`src/schema/markdown/serializer.js:409`).

**Strike-through typed in the editor is stored as `~~text~~` and rendered on the public documentation portal as
literal `~~text~~`.** One toolbar button, already enabled, producing output the render path cannot read. Either
the button goes or `:strikethrough` is added to `render_article` — a decision that belongs to 065, not to an
editor choice.

The embed path is the larger surface. `CustomMarkdownRenderer#link` turns a URL alone on its own line into raw
third-party HTML from `config/markdown_embeds.yml`, including `<iframe>` for YouTube, Loom, Vimeo, Arcade,
Bunny, CodePen and Guidejar, and **`<script src>` for Wistia (`:91-92`) and GitHub Gist (`:154`)**. The
templates are server-controlled and captures are `CGI.escapeHTML`'d (`lib/custom_markdown_renderer.rb:205-207`),
so this is not author HTML injection — but the editor's `video` menu option and `embedPreviewPlugin` are the
ergonomic front door to it, and an author pasting a gist URL puts a third-party `<script>` on a public
documentation page. 081/082/085 own the verdict; it is listed here because it is squarely "what the editor can
produce".

---

## 3. Findings

### 3.1 BLOCKER — the existing editor does not round-trip the corpus. 126 of 126 files change; 2,315 spurious `<br>` appear

Parse-then-serialize every corpus file with the real pinned transformer and serializer, no edits in between:

| Measure | Result |
|---|---|
| Files tested (63 EN + 63 AR) | 126 |
| Byte-identical after one round trip | **0** |
| Rendered HTML identical after one round trip | **0** |
| Files gaining `<br>` tags | **126** |
| Total `<br>` tags added | **2,315** |
| Parse errors | 0 |

Three independent defects, in descending severity.

**(a) Every soft line break becomes a hard break.** The corpus is hard-wrapped at ~118 columns (see any file,
e.g. `custom/db/documentation/en/getting-started/connect-your-first-channel.md:8-10`); 1,829 prose lines sit in
the middle of a paragraph. The chain:

- parser is `MarkdownIt('commonmark', { html: false, linkify: true, breaks: true })`
  (`src/schema/markdown/articleParser.js:40-43`)
- `softbreak: { node: 'hard_break' }` (`src/schema/markdown/parser.js:34`) — a CommonMark soft break becomes a
  ProseMirror hard break, indistinguishable from a deliberate Shift+Enter
- `hard_break` serializes as `'\\\n'` when text follows (`src/schema/markdown/serializer.js:258,276`)

So `Line one\nLine two` comes back as `Line one\\\nLine two`. In CommonMark a trailing `\` **is** a hard break,
so the round trip is syntactically valid and semantically wrong: commonmarker renders a softbreak as `"\n"` and
a linebreak as `"<br />\n"`
(`vendor/.../commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb:165-177`). Opening an article and
saving it without editing a character inserts a visible line break at every wrap point. Worst single file:
`custom/db/documentation/en/audiences-and-campaigns/whatsapp-campaigns.md`, +44 `<br>`.

**(b) Every tight list becomes loose.** Root cause is precise and local. `prosemirror-markdown`'s own schema
carries a `tight` attribute on lists and sets it from `listIsTight()` on parse
(`node_modules/.pnpm/prosemirror-markdown@1.13.0/node_modules/prosemirror-markdown/dist/index.cjs:128,152,499,508`),
and its serializer uses `node.attrs.tight` when defined, otherwise `options.tightLists`, which defaults to
`false` (`:714,897`). But `fullSchema` takes `orderedList`/`bulletList` from **`prosemirror-schema-list`**,
which has no `tight` attribute (`src/schema/article.js:56-64`), and `ArticleMarkdownSerializer` is constructed
with no options (`src/schema/markdown/articleSerializer.js:35`) and called with none
(`FullEditor.vue:352`). Result: `tight` is always `undefined`, `tightLists` is always `false`, every list
serializes with blank lines between items, and `<li>text</li>` becomes `<li><p>text</p></li>` — a visible
spacing change on the public portal.

This one has a one-line in-repo fix: pass `{ tightLists: true }` at `FullEditor.vue:352`. Named here because
it is the cheapest of the three and the only one that needs no upstream change.

**(c) A bold or italic run spanning a link is split into three.** 18 source lines across 6 files contain this
shape; 10 files show the damaged signature in their output. Concretely,
`custom/db/documentation/en/automation/agent-bots.md:23`:

```
in   - **When a [flow](flow-builder) would do.** A menu, …
out  * **When a **[**flow**](flow-builder)** would do.** A menu, …
```

Rendered, `<strong>When a <a…>flow</a> would do.</strong>` becomes
`<strong>When a <strong><a…><strong>flow</strong></a></strong> would do.</strong>`. Visually near-identical,
but the stored Markdown is degraded and the nesting is noise. Severity **major**, not blocker — I checked the
render rather than assuming.

**(d) Cosmetic, listed so nobody double-counts it:** `-` bullets become `*`, and table cells are padded to
column width. Neither changes the rendered HTML.

**Convergence.** 120 of 126 files are stable from the second pass onward. The 6 that are not —
`{en,ar}/automation/agent-bots.md`, `{en,ar}/commerce/connect-shopify.md`,
`{en,ar}/contacts/custom-attributes.md` — are the mark-over-link files; they settle at pass 3 (cycle length 1),
so the churn terminates. It does not oscillate forever. It also does not undo itself.

**This refutes `custom/app/dashboards/article_dashboard.rb:8-10` in one direction.** The textarea *is* the same
content as what the dashboard editor consumes. It is not the same content as what the dashboard editor
*produces*. The comment's conclusion — that the textarea is not a lesser surface — turns out to be more true
than its author meant.

### 3.2 There is no round-trip test anywhere, and the existing mitigation is at the wrong layer

`grep -rln 'ArticleMarkdownSerializer|roundTrip' --include=*.spec.js app/javascript` returns nothing. The
serializer has 460 lines of extremely careful escape logic — `splitTrailingBreaks`, setext-underline
neutralisation, `isMarkedUnderline`, `isIndentedUnderline`, a comment noting *"chatwoot's signature machinery
compares serializations byte for byte"* (`src/schema/markdown/serializer.js:120-130`) — and not one test
asserting that a document survives it.

The team has met the churn. `app/javascript/dashboard/helper/articleDiffHelper.js:9-11` exports
`rendersIdentically`, and `app/javascript/dashboard/routes/dashboard/helpcenter/pages/PortalsArticlesEditPage.vue:86`
uses it to silently discard a draft whose markdown renders the same as the live content — the comment reads
*"the renderer ignores like a blank line… so it doesn't leave a 'pending changes' badge with nothing to
compare"* (`:78-80`). That is a **diff-display** mitigation, not a storage one. And it does not even cover the
defects in §3.1: `rendersIdentically` uses `MarkdownIt('commonmark')` with `breaks: false`, so a soft break and
a `\` hard break render differently and `<li>text</li>` and `<li><p>text</p></li>` render differently. Both
real defects are correctly reported as changes; only the blank-line noise is swallowed. The bytes still churn.

### 3.3 The reusable editor is missing three of the required features outright

Against the gap list in `00-program.md` §1.4 and `01-current-system.md` §6:

| Required | In `FullEditor` today | Evidence |
|---|---|---|
| Media insertion | **yes** — picker, paste, drag-drop, progress, resize, mp4 | `FullEditor.vue:357-434`, `src/nodeViews/imageResize.js` |
| Preview beside the text | no | preview is a redirect to the saved public URL (`super_admin/articles_controller.rb:22-25`) |
| Dirty state / unsaved-work protection | **yes** — autosave + `onBeforeRouteLeave` + flush on unmount | `ArticleEditor.vue:70-77,84-98,140-149` |
| Draft / publish separation | **yes** — `draft_title`/`draft_content` + a diff panel | `ArticleEditor.vue:45-52`, `ArticleDiffPanel.vue` |
| **Required alt text** | **no — and no alt UI at all** | `imageResize.js:51-53` only mirrors `alt \|\| ''`; nothing prompts, nothing enforces |
| **Structured documentation components** (callout, note, warning, steps) | **no — no such nodes exist** | `src/schema/article.js:43-67` has doc, paragraph, blockquote, hr, heading, code_block, text, image, hard_break, lists, tables. Nothing else. |
| SEO field validation | no | `ArticleMetaField` renders plain inputs with hints and no validation (`custom/app/views/fields/article_meta_field/_form.html.erb`) |
| **RTL preview** | **not deliverable by any editor** | the portal sets no `dir` (§2.3) |

Alt text and structured components are the two that need new code whichever engine wins. Structured components
are additive rather than a fork: a `docsSchema` can be composed in-repo from `fullSchema.spec` plus new node
specs, with matching serializer entries — but each new node needs a Markdown representation that
`CommonMarker.render_doc(..., [:table])` can render, and the only extension points the renderer offers are the
ones in §1.3 (a captured HTML comment, a `^sup^` text hook, URL query parameters). A callout has to be
expressible as blockquote-plus-convention or as another captured comment marker. That is a real design
constraint on 071, and it is independent of the editor choice.

### 3.4 Media has no Super Admin route, and the corpus has no media

Covered in §1.5. Restated as a finding because it is a hard blocker on the *feature*, not on the *engine*: the
editor's upload plumbing is complete and account-scoped, and Super Admin is not in an account. A new
`POST /super_admin/.../upload` under `SuperAdmin::ApplicationController`, returning an authorized route rather
than a permanent blob URL (per `_attachments.html.erb:4-7`), is required work for 066/068/083 whatever is
decided here.

### 3.5 Bundle, licence, maintenance

| Question | Answer |
|---|---|
| Licence | MIT throughout: ProseMirror packages, `markdown-it`, `@chatwoot/prosemirror-schema`, and the repo itself |
| Size | ProseMirror stack 174 KB gzip + schema package 47 KB + `markdown-it` 44 KB ≈ **265 KB gzip** — all of it already shipped in the dashboard bundle today |
| Size gate | `size-limit` constrains only the widget (300 KB) and the SDK (40 KB) (`package.json` `size-limit`). Neither the dashboard nor the Super Admin bundle is gated, and Super Admin is an operator surface. Size is not a deciding factor here. |
| Build step | Already present: `vite_javascript_tag` in the Super Admin layout, `pnpm vite build` with a manifest assertion in the deploy (`deployment/deploy.sh:284-285`) |
| Maintenance of ProseMirror | active — `prosemirror-view@1.42.6`, `prosemirror-model@1.25.12`, both carrying pnpm overrides in this repo, so the team already tracks them |
| Maintenance of `@chatwoot/prosemirror-schema` | **the weak link.** Pinned exactly at `1.4.5` (`package.json:41`, no caret), upstream at `github.com/chatwoot/prosemirror-schema`. The §3.1(a) and (c) fixes live in that package, not in this repository. Options are an upstream PR, a pin bump to a release that fixes them, or a vendored fork. None is free, and the cost should be named in Phase 4 rather than discovered in Phase 5. |

---

## 4. Options

### Option A — Reuse `@chatwoot/prosemirror-schema` + `FullEditor.vue` in Super Admin **(RECOMMENDED)**

Mount the existing component into the Administrate article form through the harness that already ships:
an `ArticleContentField` (shaped on `ArticleMetaField`) whose `_form.html.erb` renders the `#app`-style mount
div plus a hidden input, registered in `superadmin_pages.js`'s `ComponentMapping`, with a thin Super Admin
wrapper supplying `dir` from `article.locale` and a Super-Admin-scoped upload endpoint.

**The decisive reason is not that ProseMirror is already in `package.json`. It is that the server-side render
path is already this editor's render path.** `lib/custom_markdown_renderer.rb` contains five features
(§1.3) whose sole purpose is to consume the dialect `ArticleMarkdownSerializer` emits — colwidth markers,
`cellMinWidth: 50`, `^sup^`, `cw_image_width`, `cw_video_width` — three of them with comments naming
`@chatwoot/prosemirror-schema` explicitly. Any other engine would be a second dialect feeding a renderer built
for the first, and agent 065 would be asked to support two. Reusing it is the only option where the renderer
needs no new surface at all.

Secondary reasons, in order: the authoring workflow the program asks for (autosave, draft/live, diff panel,
dirty-state and pending-upload guards) exists and is production-tested in `ArticleEditor.vue`; the whole stack
is MIT and already shipped, so nothing enters `package.json`; and Arabic text survives the engine untouched
(§2.3).

**What this option must fix before it may touch the corpus** — these are conditions, not nice-to-haves:

1. `softbreak` must stop becoming `hard_break` (`src/schema/markdown/parser.js:34`, `articleParser.js:43`).
   Upstream change, or a vendored fork, or — the in-repo alternative — normalise at the boundary by unwrapping
   soft-wrapped paragraphs before the editor sees them and accepting that stored paragraphs become single
   lines. **That last choice reflows all 126 files and makes every future diff paragraph-granular instead of
   line-granular. It is a source-of-truth decision for Agent 000 (§8.1), not an implementation detail.**
2. `{ tightLists: true }` at `FullEditor.vue:352`. One line, in this repo.
3. The mark-over-link split (§3.1c). Upstream.
4. A round-trip test over the real corpus, as a gate. The absence of one (§3.2) is why these three defects
   reached a shipped editor.
5. `strike` either leaves the toolbar or `:strikethrough` joins `render_article` (§2.4).
6. A Super Admin upload endpoint returning an authorized route (§3.4).
7. `dir` on the Super Admin editor wrapper, and on the public portal layout (§2.3).

**Honest accounting:** items 1 and 3 are not in this repository. If upstream will not take them and a fork is
refused, Option A degrades to "a rich editor that damages files on save", which is worse than the textarea.
**The round-trip test is therefore the gate, not the polish** — it is what distinguishes Option A from
Option A-that-should-not-ship.

### Strongest alternative — CodeMirror 6 as a Markdown *source* editor

Not a WYSIWYG: a textarea replacement with Markdown syntax highlighting, line numbers, bracket matching,
soft-wrap control and a server-rendered preview pane beside it.

**Why it is the strongest alternative:** it cannot have a round-trip problem, because there is no intermediate
document model — the buffer *is* the CommonMark. That eliminates §3.1 entirely, which is the single largest
risk in this whole area. It keeps files canonical for free, keeps the seeder's `changed?` honest, and needs no
new render-path surface. It is MIT, it is modular (`@codemirror/view` + `state` + `language` +
`@codemirror/lang-markdown`), it is actively maintained, and it has genuine RTL and bidi support in its own
right.

**Why I do not recommend it:** three reasons, in order.

1. It is **not** reuse. CodeMirror is in the lockfile only under the `histoire` devDependency (§1.2);
   `@codemirror/lang-markdown` is not present at all. This means new direct dependencies, which the charter's
   governing rule disfavours when something shipped can be extended.
2. It delivers none of the program's §1.4 feature list except preview. No media insertion UI, no alt-text
   enforcement, no structured components, no table editing — an author still types Markdown by hand. The gap
   §1.4 names is "the authoring surface is a textarea"; a nicer textarea is a smaller answer to it.
3. It abandons the renderer co-design. The colwidth markers, `cw_image_width` and `cw_video_width` would be
   hand-typed or unused.

**What would change my mind and make this the recommendation:** if the §3.1(a)/(c) fixes are rejected upstream
and a vendored fork of `@chatwoot/prosemirror-schema` is ruled out. At that point the choice is between a
WYSIWYG editor that corrupts the corpus and a source editor that cannot, and the source editor wins without
argument. I would also switch if Phase 4 freezes *files* as the single canonical source with the database as a
pure projection, since in that world an operator editing in Super Admin is editing something that will be
overwritten anyway, and the honest surface is a good source editor plus a faithful preview.

### Rejected — Tiptap

Tiptap is the popular answer and it is the wrong one here. It wraps the same ProseMirror this repo already
has, so it buys a nicer API and a plugin ecosystem at the cost of a new dependency tree (`@tiptap/core`,
`starter-kit`, extensions, `tiptap-markdown` or equivalent), and its Markdown story is a community add-on with
its own round-trip characteristics — the exact problem class §3.1 documents, re-acquired from a different
vendor, against a renderer co-designed for the serializer we would be dropping. Tiptap's natural output is
HTML, which §2.2 shows renders as `<!-- raw HTML omitted -->`. Choosing it would mean re-implementing the five
renderer integrations in §1.3 for a second dialect. There is no constraint in this product that Tiptap answers
better than the ProseMirror schema already installed.

### Rejected — Trix / ActionText, Quill, TinyMCE, CKEditor, EasyMDE, Toast UI, Monaco

- **HTML-storing editors (Trix/ActionText, Quill, TinyMCE, CKEditor):** disqualified by §2.2. Their output
  renders as nothing on the existing portal. Adopting one requires `:UNSAFE` plus a new sanitizer, which turns
  the program's largest open security question into a prerequisite. Trix additionally is not installed
  (`trix: 0` in `pnpm-lock.yaml`) despite `actiontext` being present transitively.
- **EasyMDE / Toast UI Editor:** new dependencies that bundle their own Markdown parser and renderer, giving a
  *third* CommonMark implementation (after commonmarker and markdown-it) whose preview would disagree with the
  public portal on exactly the five features in §1.3. Toast UI's WYSIWYG mode has its own round-trip profile.
- **Monaco:** a code editor, 2–3 MB, absent from the lockfile, and far heavier than CodeMirror 6 for strictly
  less relevant capability.

### Option E — "Extend what exists": upgrade the textarea in place, no new editor engine

The brief asks for this explicitly and for an honest verdict. What it looks like, using only what is here:

| Feature | How, with zero new dependencies |
|---|---|
| Preview | the faithful version is a server-rendered iframe of `/hc/:portal/articles/:slug?show_plain_layout=true`, extending `super_admin/articles_controller.rb:22-25` to render unsaved content. A client-side `markdown-it` preview is cheaper and **lies**: it has no `^sup^` hook, no colwidth handling, no embeds, and disagrees with `render_article` on strike |
| Toolbar | plain JS in `superadmin.js` (which already does progressive enhancement of an Administrate form, `superadmin.js:3-38`) wrapping the selection in `**`, `_`, `` ` ``, `#`, `>`, `-` |
| Syntax highlighting | `highlight.js` (`package.json:80`) can colour a read-only mirror, not an editable buffer |
| Validation | SEO length checks as Rails validations surfaced through Administrate's existing error rendering |
| Dirty state | a `beforeunload` guard |
| RTL | `dir` on the textarea from `article.locale` — the textarea is the one surface where this is trivially correct |

**Is it sufficient for the required feature set? No — and it is not close.** It cannot deliver three of the
items `00-program.md` §1.4 names:

- **Media insertion.** A toolbar cannot upload a file, show progress, or insert a resized image. An author
  would paste URLs by hand. With zero images in the corpus today and media as a Phase 4 contract item (§8.3),
  this is the feature the gap list leads with.
- **Required alt text.** You cannot enforce alt text on Markdown an author types freely. Validation could
  reject `![](...)` on save, but that is a rejection, not an authoring affordance.
- **Structured rich content components.** Nothing in a textarea makes a callout discoverable or correct.

What it *is*, and this matters: **Option E is strictly better than today, strictly cheaper than everything
else, and the only option with no round-trip risk whatsoever.** If Phase 4 freezes files as canonical and
decides Super Admin editing is for corrections rather than authoring, Option E is the right answer and this
report should not be read as arguing otherwise. It is also the correct *first increment* of Option A — the
server-rendered preview, the SEO validation, the `dir` attribute and the dirty-state guard are all needed by
Option A too and none of them depends on the editor engine. Sequencing them first buys real improvement while
the §3.1 round-trip work is settled upstream.

What it cannot be is the answer to "the authoring surface is a textarea". It is a better textarea.

---

## 5. Risks

| # | Risk | Severity | Note |
|---|---|---|---|
| 1 | Option A ships without the round-trip fixes, and the first operator save rewrites an article with 20–44 spurious `<br>` | **blocker** | Measured: 126/126 files, 2,315 `<br>`. Mitigation is the corpus round-trip gate, and nothing less |
| 2 | §3.1(a) and (c) are not fixable in this repository; upstream declines; a fork is refused | **blocker** | Option A has no safe form in that world. This is the decision that routes to the alternative, and it should be settled in Phase 4, not Phase 5 |
| 3 | Unwrapping soft-wrapped paragraphs (Option A, fix 1, in-repo variant) reflows all 126 files and makes every future diff paragraph-granular | major | A source-of-truth and review-workflow decision for Agent 000 (§8.1), disguised as a formatting choice |
| 4 | The content seeder overwrites `content` unconditionally (`content_seeder.rb:94-104`) and forces `status` (`:101`). A richer editor makes losing operator work more expensive, not less | major | Agent 000 §8.1/§8.2. A better editor raises the stakes on an unresolved conflict rather than resolving it |
| 5 | A client-side Markdown preview disagrees with `render_article` on sup, colwidths, embeds and strike, and operators trust it | major | Only the server-rendered preview is faithful. Applies to Option A and Option E alike |
| 6 | Media lands before the Super Admin upload route exists, and `url_for(blob)` permanent URLs get written into stored Markdown against the rule at `_attachments.html.erb:4-7` | major | 066/068/083 |
| 7 | `strike` is enabled in the toolbar today and `render_article` cannot render `~~` | minor | One-line fix either way; needs an owner (065) |
| 8 | The editor's embed path puts third-party `<iframe>` and `<script>` (Wistia, Gist) on public documentation pages from a pasted URL | major | `config/markdown_embeds.yml:91-92,154`. 081/082/085 |
| 9 | Neither Super Admin nor the public documentation portal sets `dir`, so the portal's `rtl:` Tailwind variants are dead and no editor can preview RTL faithfully | major | Independent of this decision; blocks the "RTL preview" feature outright. 061/072/099 |
| 10 | `@chatwoot/prosemirror-schema` is pinned exactly at `1.4.5`; a pin bump for a fix may carry unrelated changes into the agent-facing composer and help-centre editor | minor | The package serves message composition too; a bump is not scoped to documentation |

### Not checked

- Whether the `<br>` behaviour reproduces under `commonmarker` itself. The HTML comparison used `markdown-it`
  in CommonMark+tables mode as a proxy. The *mechanism* is confirmed from source on both sides
  (`parser.js:34` → `serializer.js:276` emits `\`; `html_renderer.rb:165-177` renders `linebreak` as
  `<br />` and `softbreak` as `"\n"`), so I am confident in the direction and the count is a close estimate
  rather than an exact figure. Running it through `CommonMarker` would need `bundle exec`, which §6.1 forbids.
- Behaviour of the editor in a live browser inside an Administrate form — CSRF, hidden-input synchronisation,
  Administrate's own jQuery, and the Vue mount against Administrate's markup. Reasoned from
  `superadmin_pages.js` and the field-partial precedent; not executed.
- Whether `@chatwoot/prosemirror-schema` upstream has already fixed any of §3.1. Would need a read of the
  public repository, which is outside this brief.
- Screen-reader behaviour of the ProseMirror menubar in Arabic. 072's territory.
