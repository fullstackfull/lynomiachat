---
agent: 071
scope: Structured rich content components for documentation articles — how a component can be expressed at all, given that `article.content` is CommonMark that must round-trip through files and the editor
confidence: high
---

## 1. What exists today

### 1.1 The content format and who reads it

`article.content` holds the article **body only**. The seeder splits YAML front matter off and stores
`match.post_match.strip` (`custom/app/services/documentation/content_seeder.rb:126-131`), so front matter never
reaches the content column and never reaches any editor. The front-matter keys that survive at all are an
explicit allowlist — `doc_key`, `title`, `description`, `tags`, `version`, `release_date`
(`content_seeder.rb:105-113`); every other key is silently dropped.

Body → HTML goes through exactly one path:
`ChatwootMarkdownRenderer#render_article` → `CommonMarker.render_doc(@content, :DEFAULT, [:table])` →
`CustomMarkdownRenderer#render` → `html_safe` (`lib/chatwoot_markdown_renderer.rb:13-19`).

### 1.2 The renderer already rejects raw HTML, by design and by spec

`CustomMarkdownRenderer.new` is constructed with **no arguments** (`lib/chatwoot_markdown_renderer.rb:14`), so
`CommonMarker::Renderer#initialize` applies `options: :DEFAULT, extensions: []`
(`vendor/bundle/ruby/3.4.0/gems/commonmarker-0.23.12/lib/commonmarker/renderer.rb:10-18`). `:UNSAFE` is therefore
off, and the gem's Ruby renderer emits a placeholder for both block and inline raw HTML:

- `html(node)` → `out("<!-- raw HTML omitted -->")` unless `:UNSAFE`
  (`commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb:110-118`)
- `inline_html(node)` → the same (`html_renderer.rb:120-126`)

This is a tested invariant, not an accident: `spec/lib/custom_markdown_renderer_spec.rb:31-38` asserts
`<script>alert("xss")</script>` renders as `<!-- raw HTML omitted -->`.

This answers the question `01-current-system.md` §5 left open for the article path. There is no `sanitize` call
because **the renderer never emits author HTML in the first place**. Agents 065, 081 and 084 own the full
statement; for this report it is the governing constraint: *no component can be expressed as HTML in a `.md`
file.*

`CustomMarkdownRenderer#html` is overridden (`lib/custom_markdown_renderer.rb:22-27`) for exactly one marker,
`<!--cw-colwidths:1,2,3-->`, which it consumes and emits nothing for, then calls `super` for everything else.
That one carve-out is the only raw-HTML-shaped thing in the system that survives, and it survives because the
renderer was taught about it.

### 1.3 The renderer's existing non-CommonMark extensions

| Extension | Markdown written by hand | Mechanism | Evidence |
|---|---|---|---|
| Tables | GFM pipe table | `:table` parse extension + `table` override wrapping in `.tableWrapper` | `chatwoot_markdown_renderer.rb:15`; `custom_markdown_renderer.rb:29-41` |
| Table column widths | `<!--cw-colwidths:…-->` before the table | `html` override captures, `table` splices `<colgroup>` | `custom_markdown_renderer.rb:17-27,95-98` |
| Superscript | `^text^` | `text` override splits on `^…^` | `custom_markdown_renderer.rb:43-52,211-219` |
| Video / tool embeds | a bare link alone on its own line | `link` override matches the link against **`config/markdown_embeds.yml`** and substitutes an HTML template | `custom_markdown_renderer.rb:4-11,54-59,164-209` |
| Image sizing | `cw_image_width=320px` query param on the image URL | `image` override | `custom_markdown_renderer.rb:61-71,130-146` |

`config/markdown_embeds.yml` is the important precedent. It is **one declarative file consumed by both sides**:
the Ruby renderer loads it (`custom_markdown_renderer.rb:4-8`) and the Vue editor imports the same YAML
(`app/javascript/dashboard/helper/markdownEmbeds.js:1-12`), which is how the editor's live preview and the
public portal agree. Its header documents the extension procedure in three steps
(`config/markdown_embeds.yml:1-11`). This is the established answer to "how does a structured block get into an
article without HTML in the source".

### 1.4 The editor that defines the round-trip

Super Admin authors in a 28-row textarea (`custom/app/dashboards/article_dashboard.rb:19`), whose own comment
states the rationale: `content` is "the same source format the dashboard's editor produces and the same the
public renderer consumes" (`article_dashboard.rb:7-10`). A textarea round-trips anything, so it imposes no
constraint. **The constraint comes from the editor any upgrade will reuse**: the dashboard Help Center's
ProseMirror editor, `FullEditor.vue`, which parses with `ArticleMarkdownTransformer(fullSchema)` and serializes
with `ArticleMarkdownSerializer`
(`app/javascript/dashboard/components/widgets/WootWriter/FullEditor.vue:2-20,63-73`).

`ArticleMarkdownSerializer` handles exactly these nodes —
`blockquote, code_block, heading, horizontal_rule, bullet_list, ordered_list, list_item, paragraph, image,
hard_break, text, table, table_row, table_cell, table_header` — and these marks — `em, superscript, strike,
strong, link, code` (`node_modules/@chatwoot/prosemirror-schema/dist/index.es.js:3532-3557`). There is **no
`html_block` or `html_inline` node in either direction.**

The parser is `MarkdownIt('commonmark', { html: false, linkify: true, breaks: true })`
(`…/index.es.js:2949-2953`). `html: false` means raw HTML is never tokenised as HTML; it becomes literal text in
the document.

`ARTICLE_EDITOR_MENU_OPTIONS` (`app/javascript/dashboard/constants/editor.js:174-191`) exposes
`strong em strike link undo redo bulletList orderedList h1 h2 h3 imageUpload code insertTable video
horizontalRule`. There is no blockquote button and no code-block button — but `FullEditor` builds the schema from
`fullSchema`, not from the menu list (`FullEditor.vue:64-71`), so blockquote and code_block **are** in the schema
and do round-trip even though no button inserts them.

### 1.5 What the corpus actually does — measured

63 EN files, 63 AR files.

| Construct | EN | AR | Note |
|---|---|---|---|
| `##` headings | 519 occurrences, 223 distinct | — | the entire structural vocabulary |
| `###` headings | 1 | — | `troubleshooting/contact-lynomia-support.md:37` |
| Pipe tables | 54 / 63 files | 54 / 63 | the dominant comparison device |
| Ordered lists (`1. `) | 37 / 63 files | — | the step device |
| Inline code spans | 256 | 256 | exact parity — identifiers are never translated |
| Blockquotes | 5 lines in 4 files | 5 lines in 4 files | see below |
| Fenced code blocks | **1 file, 2 fences, both with no language** | — | `integrations/webhooks.md:79-81` |
| Raw HTML tags | **0** | 0 | the only angle brackets are placeholder names in prose/code: `<inbox>`, `<timestamp>`, `<raw body>`, `<trigger>` |
| Images | **0** | 0 | |
| `→` arrow | **141** | 2 | |
| `←` arrow | **0** | **137** | |
| Callout keywords (`Note:`/`Warning`/`Important`/`Tip`/`Caution`/`Danger` used as a label) | **0** | 0 | "Note" appears 5× purely as prose, e.g. `conversations/labels.md:93` "Note step 2 put the label on the **contacts**" |

Two conventions are already real and already consistent:

**The `##` heading repertoire is the structure.** It is documented — `docs/global-documentation/06-information-architecture.md:64-65`
fixes the article skeleton as *What is this → When to use it → When not to use it → What you need first → Steps →
An example → Who can do it → Limits → Related → If it does not work* — and it is audited:
`docs/global-documentation/15-content-quality-audit.md:35-67` maps each contract section to the headings this
corpus uses for it, with per-section coverage counts (`RELATED 43/43`, `LIMITATIONS 39/43`, `TROUBLESHOOTING
39/43`, `STEP-BY-STEP 26/43`). Measured against the current corpus: `## Related` 57, `## Limits` 52,
`## Who can do this` 45, `## If it does not work` 39, `## A worked example` 38, `## What you need first` 24,
`## Steps` 24.

**The UI-path convention is direction-mirrored per locale.** EN writes `**Settings → Labels → Add label**`
(`en/conversations/labels.md:77`); AR writes `**الإعدادات ← الوسوم ← إضافة وسم جديد**`
(`ar/conversations/labels.md:76`) with U+2190 LEFTWARDS ARROW. 141 `→` in EN with zero `←`; 137 `←` in AR with
two `→`. The two Arabic `→` are defects in one file
(`ar/troubleshooting/contact-lynomia-support.md:14,20`) — they are the exceptions that prove the rule.

The five blockquotes are **pull-quotes, not callouts**: a single fully-bolded one-line distinction
(`en/automation/automation-or-flow-builder.md:13` "An automation rule reacts and finishes. A flow remembers and
waits.", `en/conversations/macros-or-automation.md:14`, `en/audiences-and-campaigns/labels-or-shared-audiences.md:13`)
plus one example-set listing (`en/conversations/labels.md:33-34`). Tailwind Typography's blockquote style wraps
content in curly quotation marks (`'blockquote p:first-of-type::before': { content: 'open-quote' }`,
`node_modules/@tailwindcss/typography/src/styles.js:1493-1497`), which is correct for a pull-quote and wrong for
a callout.

The nearest thing to a callout in the corpus is a standalone fully-bold paragraph, and there are **two** of them
in 63 files (`en/conversations/labels.md:41`, `en/automation/automation-or-flow-builder.md:37`). The 18 other
bold prohibitions (`**Do not delete the inbox.**`, `**Nothing happened.**`) are all symptom leaders inside
`## If it does not work` sections — a symptom/remedy pair, not a callout.

### 1.6 Rendering and the surfaces a component must not break

Article HTML lands in `#cw-article-content` with `prose dark:prose-invert` plus explicit `[&_table]`/`[&_th]`/
`[&_td]` overrides (`app/views/public/api/v1/portals/articles/_content.html.erb:6-19`). There is no stylesheet
hook for anything the renderer does not emit, and no author-supplied class can ever arrive (§1.2).

The sidebar table of contents is built client-side by scanning `h1, h2, h3` inside `#cw-article-content`
(`app/javascript/portal/portalHelpers.js:14-29,100-112`). With 519 `##` and one `###`, the TOC *is* the `##`
repertoire. Anything that hides body content from that scan removes it from the article's navigation.

Direction is set client-side: `setDirectionAttribute` reads `html.lang` and assigns `html.dir`
(`portalHelpers.js:153-162`). The documentation layout itself emits only `lang`, never `dir`
(`app/views/layouts/portal.html+documentation.erb:2`), so `dir="rtl"` exists only after JS runs. Tailwind
Typography uses logical properties throughout (`paddingInlineStart`, `borderInlineStartWidth`,
`borderInlineStartColor` — `@tailwindcss/typography/src/styles.js:45-49,250-254,1485-1492`), so prose itself is
RTL-correct once `dir` lands.

## 2. Constraints the existing system imposes

These are not preferences. Each is enforced by code that runs today.

1. **No raw HTML, block or inline.** The renderer replaces it with `<!-- raw HTML omitted -->`
   (`html_renderer.rb:110-126`; `spec/lib/custom_markdown_renderer_spec.rb:31-38`). `<div class="callout">`,
   `<details>`, `<summary>`, `<kbd>`, `<aside>` are all unavailable.
2. **No author-supplied CSS class, ever.** Styling must be decided by the renderer from the AST.
3. **The editor cannot represent HTML.** `html: false` (`…/index.es.js:2950`) turns it into
   literal text; there is no `html_block` node in `fullSchema` and no serializer entry for one
   (`…/index.es.js:3631-3654,3532-3557`). HTML pasted into a `.md` file becomes visible gibberish on first
   editor open, then returns to the file as a text paragraph.
4. **`[` and `]` are escaped on serialization.** `MarkdownSerializerState#esc` replaces every
   ``` [`*\~[]_] ``` with a backslash escape
   (`node_modules/.pnpm/prosemirror-markdown@1.13.0/node_modules/prosemirror-markdown/dist/index.js:820-827`).
   A bracketed marker such as `> [!NOTE]` therefore comes back from the editor as `> \[!NOTE\]`, broken. The
   same `esc` leaves letters, `:`, `!`, `(` and `)` alone, and leading `- * + > #` are escaped only at line
   start.
5. **Mark syntax is emitted by the mark spec, not by `esc`.** `strong` writes `**` from
   `{ open: '**', close: '**' }` (`…/index.es.js:3481-3486`), so a bolded marker survives serialization
   byte-exact. This is the one inline marker channel that is provably escape-proof.
6. **Front matter cannot carry body structure.** It is stripped before `content`
   (`content_seeder.rb:126-131`), filtered to six keys (`content_seeder.rb:105-113`), and invisible to the
   editor, which edits `content` alone (`FullEditor.vue:64`). It also cannot express *where in the body* a
   component sits.
7. **The seeder overwrites `content` on every run** (`content_seeder.rb:94-104`, and
   `01-current-system.md` §3). Whatever the editor writes is lost at the next `documentation:content`. So a
   component's canonical form must be the one a human types into the `.md` file; the editor's serialization has
   to *match* that form, not merely be equivalent to it.
8. **The TOC is the `##` scan** (`portalHelpers.js:14-29`). Collapsed or wrapped body content leaves the
   navigation.
9. **EN/AR parity is exact and audited** — 256 inline code spans and 54 table files on each side. Any component
   must be writable identically in both corpora, and its marker must not need translating (or the two corpora
   diverge structurally).

## 3. Findings

**F1 — Raw HTML in Markdown is not an option; it is a dead end on three independent counts.** It is omitted by
the renderer (`html_renderer.rb:110-126`), it is unrepresentable in the editor schema
(`…/index.es.js:3631-3654`), and it is already proven absent from the corpus (0 tags in 126 files). Agent 065
will report the renderer behaviour; this report's recommendation does not depend on their verdict, because the
option fails on the editor round-trip and on corpus evidence regardless.

**F2 — The corpus has no callout convention to inherit.** Zero uses of `Note:`/`Warning`/`Important`/`Tip`/
`Caution`/`Danger` as a label, in either locale. The five blockquotes are pull-quotes. Two standalone bold
paragraphs are the whole of the existing callout-shaped surface. The honest reading is that the authors routed
every caution into `## Limits` (52), `## If it does not work` (39) and `## Who can do this` (45) instead — a
deliberate IA choice recorded at `06-information-architecture.md:64-70`, which singles out "Limits" as one of the
two sections that make documentation worth reading.

**F3 — A fenced code block loses its language on every editor round-trip. This is a one-word bug.** The parser
writes the attribute `language`: `fence: { block: 'code_block', attrs: tok => ({ language: tok.info && tok.info.trim() || null }) }`
(`…/index.es.js:2749-2755`). The serializer reads `params`: `state.write('```' + (node.attrs.params || ''))`
(`…/index.es.js:3238-3244`). The node spec declares only `params`
(`prosemirror-markdown@1.13.0/.../dist/index.js:95-105`), and ProseMirror's `computeAttrs` iterates the spec's
attrs, so `language` is discarded on parse and `params` stays `""`. ` ```ruby ` opens in the editor as a code
block and saves as a bare ` ``` `. Corroborating evidence that nobody has exercised this: the corpus contains
exactly two fences and neither carries a language (`en/integrations/webhooks.md:79-81`), and
`ARTICLE_EDITOR_MENU_OPTIONS` has no code-block button at all
(`app/javascript/dashboard/constants/editor.js:174-191`). Owner: whoever owns the editor stream. The fix is to
rename the parser attr to `params`; it is not a new component.

**F4 — `softbreak` maps to `hard_break`, so the hard-wrapped corpus does not survive an editor round-trip
today.** `baseNodesMdToPmMapping` maps both `softbreak` and `hardbreak` to the `hard_break` node
(`…/index.es.js:2740-2745`), and `MarkdownIt` is built with `breaks: true` (`…/index.es.js:2952`). The
`hard_break` serializer writes `'\\\n'` — a backslash hard break — for ordinary following text
(`…/index.es.js:3327-3344`). Every corpus file wraps prose at ~110 columns
(`en/conversations/labels.md:8-11` and throughout), so opening any article in `FullEditor` and saving converts
every wrap point into an explicit `<br />`. This is outside my scope to fix but it is **inside my scope as a
constraint**: "survives the editor round-trip" is currently false for ordinary paragraphs, before any component
is added. Agents 067 and 069 must arbitrate this; no component recommendation is safe until they do.

**F5 — The one marker channel that is provably escape-proof is a strong mark.** `esc` escapes
``` ` * \ ~ [ ] _ ``` (`prosemirror-markdown/dist/index.js:820-827`), which rules out `[!NOTE]`, `**` written as
text, `_NOTE_` and `` `NOTE` `` as *text*. But `**` emitted by the `strong` mark spec
(`…/index.es.js:3481-3486`) never passes through `esc`. A blockquote containing a paragraph whose first inline
child is a `strong` node round-trips byte-exact: `blockquote` → `wrapBlock('> ', …)`
(`…/index.es.js:3235-3237`), paragraph, strong, text. I traced each node to its serializer; nothing in that
chain can alter the marker.

**F6 — `config/markdown_embeds.yml` is the shape of the answer, and it is already load-bearing.** A plain-CommonMark
construct (a bare link on its own line) is recognised by the renderer and expanded from a declarative template
that the editor imports from the same file (`custom_markdown_renderer.rb:4-11,164-209`;
`app/javascript/dashboard/helper/markdownEmbeds.js:1-12`). The file even documents how to add a type
(`config/markdown_embeds.yml:1-11`). Extending it, or copying its pattern, is the EXTEND-DO-NOT-DUPLICATE move
for structured content.

**F7 — Blockquote-as-callout needs the renderer to stop emitting `<blockquote>`, not just to add a class.**
Tailwind Typography injects open-quote/close-quote pseudo-elements on blockquote paragraphs
(`@tailwindcss/typography/src/styles.js:1493-1497`) and italicises the content (`:1485-1492`). A callout that
renders as `<blockquote>` gets curly quotes around "Note — …". The renderer must emit a different element for a
matched marker and leave `<blockquote>` for the five real pull-quotes.

**F8 — RTL is a layout problem, not a component problem, and it has a defect of its own.** Once `dir` is set,
Tailwind Typography is fully logical-property based (`styles.js:45-49,1485-1492`) and any component built from
`border-s`/`ps`/`text-start` is RTL-correct. But `dir` is only ever set by JS after load
(`portalHelpers.js:153-162`); the documentation layout emits `lang` and no `dir`
(`portal.html+documentation.erb:2`), so Arabic articles paint LTR first and stay LTR if the script fails. The
`ltr:`/`rtl:` variants already in the sidebar (`documentation_layout/_sidebar.html.erb:15`) have the same
dependency. Agent 072 owns this; I flag it because every RTL answer below is conditional on it.

**F9 — The step sequence is already solved, twice over.** `## Steps` (24 files) and `## A worked example`
(38 files) with ordered lists (37 files) is the convention, it is documented
(`06-information-architecture.md:64-65`), it is audited (`15-content-quality-audit.md:42,54-67`), ordered lists
round-trip cleanly through parser and serializer (`…/index.es.js:2762-2767,3532-3545`), and the headings feed the
TOC (`portalHelpers.js:14-29`). A step component would replace a documented, measured, working convention with a
new one. There is no need to answer.

## 4. Options

### 4.1 How a component can be expressed — the five real candidates

The test for each: survives the renderer / survives the editor round-trip / survives the "sanitizer" (here: the
renderer's own raw-HTML omission, which is the only sanitization in the path) / works in RTL / hand-writable in a
`.md` file.

| Option | Renderer | Editor round-trip | Raw-HTML omission | RTL | Hand-writable |
|---|---|---|---|---|---|
| **A. Blockquote + marker convention, recognised by the renderer** | yes — override `blockquote(node)` alongside the existing `table`/`text`/`link`/`image` overrides | **yes, byte-exact** — blockquote → paragraph → strong → text, each with a serializer (F5) | n/a — no HTML in the source | yes, with logical-property classes the renderer emits (F8) | yes — reads as a bolded lead-in even to a renderer that knows nothing (F7 is a styling fix, not a correctness one) |
| **B. Fenced block with an info string** (` ```callout warning `) | yes — override `code_block(node)` and branch on `fence_info` | **no** — the language is dropped (F3). Even once F3 is fixed, the editor renders the body as monospace code and the author loses inline links and bold inside the callout, since `code_block` has `marks: ""` (`prosemirror-markdown/dist/index.js:95-105`) | n/a | yes | yes, but the content is inert text |
| **C. Raw HTML in Markdown** | **no** — `<!-- raw HTML omitted -->` (F1) | **no** — unrepresentable, becomes literal text (F1) | **no, by definition** | n/a | yes, and that is the trap |
| **D. A custom CommonMarker extension** (new C-level parse extension) | yes | **no** — the editor's markdown-it would have to grow a matching plugin, and the ProseMirror schema a matching node, serializer entry and parser mapping, all hand-kept in sync across two languages and a vendored package | n/a | yes | depends entirely on the syntax chosen |
| **E. Front-matter-driven structure** | n/a | **no** — front matter is stripped before `content` and the editor never sees it (constraint 6) | n/a | n/a | yes, but it cannot say *where* in the body the component goes |

C and E are eliminated by code, not by preference. D is eliminated on cost: it is the only option that requires
touching a vendored package (`@chatwoot/prosemirror-schema`) and a C extension to the commonmarker gem, for a
need that §1.5 shows the corpus has been meeting with `##` headings and tables. B is eliminated because
`code_block` forbids marks, so a callout written that way cannot contain the links the house style uses in every
section (`en/conversations/labels.md:26,46,58`).

**A is the recommendation**, and it is the option that matches what the system already does: the renderer
recognises a plain-CommonMark construct and decides the markup, exactly as `markdown_embeds.yml` does for links
and `<!--cw-colwidths:-->` does for tables (F6).

### 4.2 The recommended mechanism, concretely

**One mechanism: a blockquote whose first inline child is a strong mark matching a declared label, recognised by
`CustomMarkdownRenderer#blockquote` and styled from a declarative map.**

Source form, identical in both locales except for the label text:

```
> **Note** — Lynomia Chat stores labels in lower case, whatever you type.
```

What each layer does:

- **Renderer**: a `blockquote(node)` override reads the first child paragraph's first inline node. If it is
  `:strong` and its text matches a declared label, emit
  `<div class="cw-callout cw-callout-note" role="note">` with the label rendered as the heading and the rest as
  the body; otherwise call `super` and the five existing pull-quotes keep rendering as `<blockquote>` (F7). This
  sits beside the four overrides already in that file (`custom_markdown_renderer.rb:22,29,43,54,61`).
- **Label map**: a YAML map of `label → { class, icon, en, ar }`, following `config/markdown_embeds.yml`'s
  pattern and header (`config/markdown_embeds.yml:1-11`) so the editor can import the same file
  (`markdownEmbeds.js:1-12`) and preview identically. The per-locale label text lives here, which is what keeps
  the EN and AR corpora structurally identical while each reads naturally (constraint 9). The Arabic corpus
  already proves it needs this: it mirrors `→` to `←` per locale (§1.5), so a per-locale label is the
  established habit, not a new one.
- **Styling**: Tailwind utilities in `_content.html.erb`'s class list, in the same `[&_…]` arbitrary-variant
  style the table rules already use (`_content.html.erb:12-17`), using `border-s`, `ps-*`, `text-start`. Nothing
  custom, nothing scoped, no inline styles.
- **Editor**: nothing to build. The construct is already a legal blockquote in `fullSchema`, already round-trips
  (F5), and a preview styling pass can read the same YAML. No new ProseMirror node, no vendored-package change.
- **Degradation**: with no renderer change at all, the same source renders as a styled blockquote with a bold
  lead-in — readable, not broken. That is the property raw HTML and `[!NOTE]` both lack.

### 4.3 The minimum component set

Every entry below cites the corpus need it answers. Nothing is included because an editor supports it.

| # | Component | Mechanism | Documented need |
|---|---|---|---|
| 1 | **Callout — two variants only: `Note` and `Warning`** | §4.2 | Thin but real: two standalone bold-sentence paragraphs that are doing callout work today (`en/conversations/labels.md:41`, `en/automation/automation-or-flow-builder.md:37`), and `06-information-architecture.md:64-70` names "Limits" — the things the UI hides — as one of the two sections that make the docs worth reading. Those belong in prose with emphasis; a `Warning` gives the two existing ones a home without inventing a severity ladder. |
| 2 | **Pull-quote — the existing bare blockquote, left exactly as it is** | no change; `super` in the `blockquote` override | 5 lines in 4 files, all a single bolded distinction (`en/automation/automation-or-flow-builder.md:13`, `en/conversations/macros-or-automation.md:14`, `en/audiences-and-campaigns/labels-or-shared-audiences.md:13`, `en/conversations/labels.md:33-34`). This is not a new component; it is the thing the callout override must not break. |
| 3 | **Table — unchanged** | already shipped: `:table` + `table` override + `<!--cw-colwidths:-->` | 54 / 63 files in each locale. Fully round-trips. Nothing to do. |
| 4 | **Step sequence — `## Steps` / `## A worked example` + ordered list, unchanged** | no mechanism | F9: documented (`06-information-architecture.md:64-65`), audited (`15-content-quality-audit.md:42,54-67`), 24 and 38 files, feeds the TOC. Already the answer. |
| 5 | **UI path — bold text with the locale's own arrow, unchanged** | no mechanism | 141 `→` in EN, 137 `←` in AR (§1.5). Already consistent, already direction-correct, and a component would be a worse version of it. The only work is a corpus fix for the two stray `→` in `ar/troubleshooting/contact-lynomia-support.md:14,20`, which belongs to agent 061. |
| 6 | **Keys and identifiers — inline code, unchanged** | no mechanism | 256 spans per locale, exact parity. `` `/` `` for the slash key (`en/conversations/macros.md`), `` `vip` ``, `` `phone_number` ``, `` `+966551112233` ``. `<kbd>` is impossible anyway (F1), and inline code already reads as a key. |

**That is one new component.** The rest of the set is a statement that the existing conventions are the
components, and the deliverable is to write them down, not to replace them.

### 4.4 Explicitly rejected

| Rejected | Why — on evidence, not taste |
|---|---|
| **Collapsible `<details>`/`<summary>`** | Impossible (F1: omitted by renderer, unrepresentable in editor). Zero corpus uses. It would also hide body content from the `h1,h2,h3` TOC scan (`portalHelpers.js:14-29`), and the corpus's answer to long articles is 223 distinct `##` headings plus that TOC. No documented need. The only `<details>` handler in the portal targets `details[data-close-on-clickaway]` chrome (`portalHelpers.js:130-140`), not article content. |
| **A five-level callout ladder (`info`/`tip`/`warning`/`danger`/`note`)** | The corpus uses **zero** callout keywords in either locale (§1.5). Shipping five variants to cover two existing bold paragraphs is inventing need. Two is already generous; a third gets added when a corpus file demonstrates it. |
| **`> [!NOTE]` GitHub alert syntax** | Provably broken by the round-trip: `esc` escapes `[` and `]`, so it returns from the editor as `> \[!NOTE\]` (constraint 4, F5). It also degrades to literal `[!NOTE]` rather than to readable prose. |
| **Fenced info-string components (` ```callout `)** | `code_block` has `marks: ""` (`prosemirror-markdown/dist/index.js:95-105`), so the body cannot carry the links and bold the house style uses in every section. Compounded by the live `language`/`params` bug (F3). |
| **A custom CommonMarker parse extension** | Requires a C-level gem extension *and* a matching markdown-it plugin, ProseMirror node, serializer entry and parser mapping inside the vendored `@chatwoot/prosemirror-schema`, kept in sync by hand across two languages. Option A reaches the same output with one Ruby method and one YAML file. |
| **`<kbd>` keyboard styling** | Impossible (F1). Inline code already serves, 256 times. |
| **Code blocks with syntax highlighting / a language picker** | The corpus has one fenced block in 126 files, with no language (`en/integrations/webhooks.md:79-81`). The need is a bug fix (F3, one word), not a feature. Highlighting adds a JS payload to the public portal for two code fences. |
| **Tabs, accordions, cards, badges, step-wizards** | No corpus evidence of any kind, no mechanism that survives F1, and every one of them would be in the set only because a rich editor offers it. |
| **Front-matter-driven structure** | Eliminated by code: stripped before `content`, filtered to six keys, invisible to the editor, and unable to say where in the body a component sits (constraint 6). |

## 5. Risks

**R1 — The editor round-trip is already broken for plain paragraphs (F4), which makes "round-trips cleanly" a
conditional claim for everything above.** `softbreak → hard_break → '\\\n'` converts every soft wrap in the
hard-wrapped corpus into an explicit break. My blockquote-marker trace (F5) covers the *marker*; the prose inside
the callout rides on whatever agents 067/069 decide about F4. If F4 is not fixed, no editor may touch a corpus
file, and the mechanism's round-trip property is untested in practice. **This is the one thing that must be
arbitrated before the component set is frozen.**

**R2 — A marker convention can be typed wrong, and a typo fails silently.** `> **Note:** …` with a trailing
colon, or `> **note** …`, or a label a locale translated differently from the YAML map, renders as an ordinary
blockquote with curly quotes. The mitigation is cheap and belongs where the system already validates content:
`lib/tasks/documentation_seo_audit.rake`, which already audits data through the real helpers and exits 1 on error
(`01-current-system.md` §8). A warning for "blockquote starting with a strong node that nearly matches a declared
label" costs one check. Not a blocker; a check.

**R3 — The five existing pull-quotes must keep rendering as pull-quotes.** The override has to fall through to
`super` for them (F7). Three of the five are a single fully-bolded sentence, which is structurally
`blockquote > paragraph > strong` — the *same shape* as a callout. The discriminator cannot be "starts with
strong"; it must be "starts with a strong node whose text matches a declared label **and** is followed by more
content in the same paragraph". I have not verified that discriminator against all five by running anything —
read-only; it holds by inspection of `en/automation/automation-or-flow-builder.md:13`,
`en/conversations/macros-or-automation.md:14`, `en/audiences-and-campaigns/labels-or-shared-audiences.md:13`
(fully bold, nothing after) and `en/conversations/labels.md:33-34` (no strong at all), but it needs a spec.

**R4 — RTL correctness is borrowed, not owned (F8).** The component's own classes can be logical-property based,
but the Arabic portal's `dir` arrives from JS after first paint and never arrives at all if the script fails.
A callout with `border-s-4` renders on the wrong side in that window. Agent 072 owns the fix
(`dir` in `portal.html+documentation.erb:2`); until then this component inherits the defect along with the
sidebar.

**R5 — The seeder overwrites `content` on every run** (`content_seeder.rb:94-104`). If the editor's
serialization of a callout differs from the hand-written form by even a space, every `documentation:content` run
reverts the editor's version and the diff churns forever. This is why the recommendation insists on a
**byte-exact** round-trip (F5) rather than a semantically-equivalent one, and why option B and option D — whose
serialized forms are chosen by code rather than matching what a human typed — are worse than they look.

**R6 — Two variants will be asked to become five.** The pressure will come from the editor's toolbar, not from
the corpus. The defence is the rule this report was given: a variant is added when a corpus file demonstrates the
need, and the demonstration is a citation, not a preference. Agent 000 should hold the label map as a frozen
contract in Phase 4 rather than leaving it to a Phase 5 writer.

**R7 — Unverified.** I did not execute anything (read-only per §6.1): no renderer run, no editor round-trip, no
spec. Every claim above is traced through source. The three claims most worth a spec before implementation are
F3 (the `language`/`params` mismatch), F4 (`softbreak` → `'\\\n'` over a real corpus file), and R3 (the
pull-quote discriminator against all five existing blockquotes).
