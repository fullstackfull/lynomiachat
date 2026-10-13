# Orchestrator rulings — Agent 000

Decisions I am making as orchestrator, because a specialist asked for arbitration and the answer follows from the
evidence rather than from the owner's preference. Each names the agents that forced it. Anything that is the
**owner's** call is in `discovery/_ARBITRATION.md` under URGENT or PD, not here.

These rulings bind Phase 5 writers. They are not frozen contracts — Checkpoint 2 freezes those — but no writer
may contradict one without bringing me new evidence.

---

## R1 — Sanitization: the charter row was wrong, and the fix is still "extend, don't duplicate"

**Forced by**: 065, 081, 085 (independently), 071, 082.

`00-program.md` §2 said to extend "the existing article render path" and not to build a second sanitizer. Agent
081 pointed out that this is **unsatisfiable as written: there is no first sanitizer.** No `sanitize`, Loofah or
`Rails::HTML` call exists anywhere in the article render path. What protects the path today is that CommonMarker
is built with `:DEFAULT`, so raw author HTML is **omitted** rather than escaped — a property of the parser
configuration, not a control anybody chose.

That is a brittle protection for three reasons the agents proved: one word (`:UNSAFE`) turns it into stored XSS
everywhere; enabling `:UNSAFE` would *not* also enable `tagfilter`, because the renderer is built with
`extensions: []`, so the obvious "let authors write a little HTML" change is maximally unsafe; and there are
**zero XSS regression tests** in either renderer spec.

**Ruling.** The rule was never "add no code". It was "do not build a parallel system". So:

1. Add **exactly one** sanitization pass, inside `ChatwootMarkdownRenderer#render_as_html_safe` — the single
   existing choke point every article already passes through. `Loofah` and `Rails::HTML` are already in
   `Gemfile.lock`. One pass at one choke point *is* extending the existing path; a second renderer, a second
   pipeline or a client-side-only control would be duplicating it.
2. Keep `:DEFAULT`. The sanitizer is defence in depth behind omission, not a licence to relax omission.
3. **Remove `github_gist` and `wistia` from `config/markdown_embeds.yml`.** These are the two providers that
   emit third-party `<script>` tags into a public page on the product's own origin, and Gist content is
   attacker-authored. The corpus uses **zero** embeds and **zero** images, so the cost is nil and the benefit is
   the removal of a live, reachable, author-triggerable script injection. That file is imported by the dashboard
   editor too, so it gets **one owner across both trees** in the Phase 5 ownership map.
4. Add XSS regression tests asserting exact `render_article` output for raw HTML, `javascript:`, `data:`, an
   `onerror` attribute, a `</script>` in a title reaching JSON-LD, and each remaining embed provider. Agent 081
   verified by reading that the JSON-LD case is *already safe* (`json_escape(...).to_json`), and a test is what
   keeps it that way.
5. The `?show_plain_layout=true` preview must stop deleting `X-Frame-Options` without a `frame-ancestors`
   replacement, and a `script-src`/`frame-src` CSP for the documentation portal moves from an initializer
   comment into the Phase 4 contract.

## R2 — Media: ActiveStorage is the storage mechanism, not a URL in a Markdown file

**Forced by**: 066 (the decisive fact), 068 (same conclusion from the UX side), 083, 087.

Agent 066 established that an ActiveStorage signed id is a `message_verifier("ActiveStorage")` over the blob's
**primary key**, keyed from `secret_key_base`. **A blob URL committed into a git-canonical Markdown file is
valid in exactly one database.** My charter row "Media → ActiveStorage" could therefore be read as mandating
something that cannot work, and agent 066 was right to refuse to assume.

**Ruling.** The row is amended in place. ActiveStorage remains the storage and serving mechanism — we are not
adding a DAM, an S3 convention of our own, or a second asset pipeline. But the corpus **never contains a blob
URL**. The leading design, to be frozen at Checkpoint 2 once 083 and 084 report, is agent 066's Option D:

- media files live beside the Markdown in the repository,
- referenced from the body by a stable **`media:` key**, never a URL,
- uploaded idempotently **by checksum** by the existing `ContentSeeder`,
- attached to the platform **Portal**, not the Article — because the seeder rewrites Articles wholesale and
  would orphan an Article-owned attachment on every run,
- resolved to a URL **at render time, per call**, never by flipping `resolve_model_to_route` globally,
- raster only; originals, not variants,
- **alt text required at the seed boundary**, which is the only place that can enforce it for both a file-authored
  and an operator-authored image.

Two supporting rulings: **`![](data:image/…)` must be closed before Phase 5 writes a single image** (agent 087's
F4 — it bypasses every media control by construction and is permanent in git); and the media authoring UX is
**reused, not rebuilt** — agent 068 showed the picker, drag-and-drop, paste, progress, retry, remove and resize
all already ship in `FullEditor.vue`, and only three primitives are genuinely new: an alt/decorative/caption
panel, a drop-target highlight, and a publish-time missing-alt blocker.

## R3 — Editor: reuse what ships, gated on a round-trip test, with the textarea upgrade as increment one

**Forced by**: 063, 067, 071, 082.

Agent 067 measured the thing that matters: **the already-installed editor does not round-trip this corpus.**
126 of 126 files change on a no-edit parse-and-serialize, adding 2,315 spurious `<br>`. Agent 071 independently
found the same class of defect. So "reuse the existing editor" is right in principle and would damage every file
on first save today.

**Ruling.**

1. The target is the **already-installed ProseMirror editor** (`@chatwoot/prosemirror-schema@1.4.5`, MIT, exact
   pin), mounted in Super Admin through the **existing** `superadmin_pages` Vue harness, which agent 063 found is
   already loaded on every Administrate page with zero mount points. No new editor dependency is justified:
   agent 067 confirmed no tiptap, quill, lexical, monaco, easymde, toast-ui, trix, slate, ckeditor or tinymce is
   anywhere in the lockfile, and — decisively — **the Ruby renderer already implements five features whose only
   producer is this editor's serializer.** The render path and the editor are already a matched pair.
2. **Adoption is gated on a corpus round-trip test**: parse-and-serialize all corpus files and assert byte
   equality. Until that test passes, the editor does not touch `content`.
3. **Increment one is the textarea upgrade** — preview, toolbar, validation, dirty state, and `dir`. Agent 067 is
   right that this is strictly better than today with zero round-trip risk, and right that it is **not
   sufficient**: it cannot deliver media insertion, required alt text or structured components. So it ships
   first, and it does not end the stream.
4. HTML-storing editors are **disqualified on evidence**, not preference: `commonmarker` with `:DEFAULT` renders
   their output as literally nothing.
5. The two upstream serializer fixes live in a package shared with the agent composer. **Decision: attempt
   upstream first, and if that is not landable in this program's window, pin a vendored fork** — never a silent
   patch. A fork of a package the composer also uses is a Phase 5 ownership entry, not a side effect.
6. The fallback, if both serializer fixes are refused, is agent 067's alternative: a **CodeMirror 6 Markdown
   source editor with a server-rendered preview**, which cannot have a round-trip problem by construction.
7. `article_dashboard.rb:8-10` claims the dashboard editor "produces" the format the renderer consumes. It
   consumes it; it does not produce it. That comment gets corrected.
8. `rows: 28` is **inert** — agent 063 found the Administrate partial passes no options and CSS caps the height.
   My `01-current-system.md` §6 overstated the baseline; the real thing is a browser-default textarea.

## R4 — What counts as normative in a Meta changelog

**Forced by**: 023, which caught `00-program.md` §6.2 calling changelogs normative in one sentence and
observational in another. Six deprecation facts rest only on a changelog.

**Ruling.** A Meta changelog entry is **normative for the fact that a change was announced, and for its date**.
It is **observational for any behaviour it does not spell out**. So "permission X was retired on 2025-01-27" is
publishable from a changelog; "and therefore calls now return code Y" is not, unless a reference page says so.

## R5 — The error taxonomy key

**Forced by**: 001, 005, 011, 017, 025, 007.

Three facts settle it. Meta publishes **no HTTP status** for send failures and says to build on `code` and
`error_data.details`. **`error_subcode` is not returned by Cloud API v16.0+** — so a WhatsApp taxonomy keyed on
subcode is wrong by construction, while Messenger and Instagram still depend on subcodes heavily. And code
**2388103 carries 11 distinct failures** discriminated only by the string Meta tells you not to depend on.

**Ruling.** The taxonomy key is **`(product, code)`**, with `error_data.details` carried as evidence and shown to
operators, never parsed for control flow. Subcode is recorded **per product** — meaningful for Facebook and
Instagram, absent for WhatsApp — and no row may carry an HTTP status unless Meta publishes one. Where one code
covers several distinct remedies (2388103, 132001, 131052, code 200), the article says so plainly instead of
picking one meaning.

And the existing product rule holds, now with evidence behind it: **one article per class of failure, not one per
code.** Agent 005 reproduced ~100 published WhatsApp codes; the corpus has 4. A hundred articles nobody reads is
not coverage. But agent 040's point stands — the current five-article set already mixes codes the product
classifies with codes it only names, so **the admission rule is: a code gets documented when a Lynomia user can
reach it**, whether or not `delivery_failure.rb` classifies it. 131047 and 131026 were observed in production and
get articles.

## R6 — Citing Meta

**Forced by**: 001, 005, 007, 009–014, 016, 018, 027 — every Meta agent hit this.

Meta has moved `/docs/whatsapp/**` to `/documentation/business-messaging/whatsapp/**`. Some pages serve only
from the old path, some only from the new, several 404, and several render only with JavaScript.

**Ruling.** Cite the path that actually serves the page, prefer `/documentation/business-messaging/**` where both
do, and **record per claim: the URL, the date checked, and the API version context.** Never cite a page that
returns only navigation chrome or a title — if that is the only source, the claim is unverified and says so.
Agent 010's technique is adopted program-wide: **append `.md` to any path in
`/documentation/business-messaging/whatsapp/llms.txt` for the verbatim article text.** Every Meta URL already in
the corpus and in code comments is re-checked before Phase 5 ships.

## R7 — When the UI offers what the server refuses

**Forced by**: 029, 031, 032, 033, 035, 051 — the pattern appears at least nine times.

**Ruling.** The corpus documents **what the server actually enforces**, because that is what will happen to the
reader. It does not describe a capability the UI advertises and the API refuses. Every instance goes on the
Phase 5 product-defect list for the owner, and where an article would otherwise have to describe the broken
surface, it is held rather than shipped describing a lie. Documentation does not paper over a defect.

## R8 — Arabic locale resolution is one decision, not three

**Forced by**: 073, 076, 085, 069, 071, 072 — six agents, three symptoms, one cause.

All 494 Arabic internal links resolve to English; every contextual-help click from the dashboard lands in
English; and the portal layout never sets `dir`, so Arabic paints LTR until JavaScript intervenes.

**Ruling.** These are **one Phase 4 contract item**, decided once: a locale-aware link and route resolution rule
(the seeder's own `slug_for(key, locale)` is already the right function — agent 076's recommendation to rewrite
targets through it and raise on an unknown key makes zero-broken-links an invariant of the seed), plus `dir` on
the layout. Nothing about Arabic being "first-class" is true until this lands, and no RTL preview can be built on
a layout with no RTL.

## R9 — Internal-link and corpus integrity validation belongs in CI, not in the deploy

**Forced by**: 076, 079, 087, and my own §8 correction.

The SEO audit is a per-article front-matter check, and three agents showed it cannot see the failure modes this
program will create. File-level checks — broken keys, orphans, the `## Related` convention, absolute URLs, data
URIs, token-shaped strings, tag-shaped tokens outside code spans — are properties of **files**, so they belong in
CI on the pull request, where a human can fix them before merge. Data-level checks stay in the audit.

**Ruling.** Extend the existing corpus spec from per-file to graph invariants, add a CI content gate, and keep
`lynomia:docs:seo_audit` for what only the server can see. The deployment-gate question is separate and waits for
agent 097.
