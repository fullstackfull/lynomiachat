# Documentation V2 — Phase 2: implementing the orchestrator rulings

Phase 2 implements `08-orchestrator-rulings.md` (R1–R12). This file records what has landed, what each
decision rests on, and — where a ruling turned out to be partly unachievable as written — says so rather than
reporting it done.

Branch `claude/documentation-v2`. Nothing merged, nothing deployed, no production data or Meta configuration
touched.

---

## R1 — Sanitization and the embed providers

| Item | State | Evidence |
|---|---|---|
| R1.1 — one sanitization pass inside `render_as_html_safe` | **NOT DONE — next unit, and it needs the allowlist derived first** | See R1.1 below |
| R1.2 — keep `:DEFAULT` | **Satisfied** | `lib/chatwoot_markdown_renderer.rb:8,15` unchanged; both `render_doc` calls still pass `:DEFAULT`, so raw author HTML is still omitted |
| R1.3 — remove `github_gist` and `wistia` | **DONE** | `config/markdown_embeds.yml` |
| R1.4 — XSS regression tests for the named cases | **DONE** | `spec/lib/markdown_renderer_security_spec.rb`, `spec/helpers/documentation_helper_spec.rb` |
| R1.5 — `?show_plain_layout=true` must stop deleting `X-Frame-Options` without a `frame-ancestors` replacement | **INVESTIGATED, NOT IMPLEMENTED — the ruling is not achievable as written. Finding below** | `app/controllers/public/api/v1/portals/base_controller.rb:67-69` |

### R1.3 — what was removed and why the cost is nil

`wistia` and `github_gist` were the **only two** providers whose template emitted a `<script src>`. Every
remaining one renders an `<iframe>` (8 providers) or a `<video>` (`mp4`), which the browser isolates. A
`<script src>` runs third-party code **with this product's origin**, on a public page, chosen by whoever wrote
the article — and Gist content is attacker-authored.

The corpus uses zero embeds, so no article changed. Three call sites followed the config:

- `app/javascript/dashboard/helper/markdownEmbeds.js` — the `NON_PREVIEWABLE_EMBEDS` set existed solely to keep
  `github_gist` out of the editor preview (gists use `document.write`). With the provider gone the set was dead
  code, so the helper is now a plain map.
- `app/javascript/dashboard/components/widgets/WootWriter/VideoEmbedInput.spec.js` — the wistia row removed.
- `app/javascript/dashboard/i18n/locale/en/components.json` — the hint string no longer advertises Wistia.
  English only; the other locales go through Crowdin.

**Two pre-existing specs asserted the Wistia embed was produced** (`custom_markdown_renderer_spec.rb:213`,
`chatwoot_markdown_renderer_spec.rb:84`) and the gate caught both. They are **inverted, not deleted**: the URL
still parses, so the assertion that now matters is that it renders as an ordinary link and emits no `<script>`.
Deleting them would have removed the only coverage of that URL shape.

### R1.4 — the named cases, and one spec that proved nothing

R1.4 named six cases. Raw HTML, `javascript:` and `data:` were already covered by the P0 suite. Added:

- **an `onerror` attribute** — asserted structurally (`parsed.css('[onerror]')` empty, no `img` element at
  all), because author HTML is omitted rather than escaped.
- **`</script>` in a title reaching JSON-LD** — `spec/helpers/documentation_helper_spec.rb`, which is also the
  **first spec this helper has ever had**; §N.8 of the P0 report recorded that gap. Both the article schema and
  the breadcrumb schema are covered, plus the byline rule (`author` is the Organization, never the person) and
  the cross-portal crumb rule.
- **each remaining embed provider** — 9 examples, each asserting the **exact element list** a browser builds.

> **The first draft of those nine examples was vacuous and said so only after it was checked.** They rendered
> `"\n\n<url>\n\n"` and asserted "no script element". Every one passed — while producing a single `<p>` and no
> embed at all, because `render_article` is built with `extensions: [:table]` and **not** `:autolink`, so a bare
> URL is plain text. The examples would have passed just as well with the embed system deleted. They now use
> explicit `[text](url)` syntax and pin the exact element list (`%w[p div iframe p]`, or `%w[p video source]`
> for mp4), so a provider that silently stops matching fails instead of passing. Caught by rendering each
> provider through a `rails runner` and reading the output rather than trusting the green.

Also added: a capture-group injection case. The provider regexes exclude `&`, `/` and `?` from an id but **not**
`"` or `<`, and the captures land inside `src` attributes. `render_embed_from_match` runs each through
`CGI.escapeHTML`; the example proves the payload stays data and the parser builds no script element.

Durable guards, not just point assertions: one example pins the **exact provider key set**, so adding any
provider fails until the test is updated deliberately; another asserts **no template contains `<script`**.

### R1.1 — why the sanitizer is not in this commit

The ruling says to add one pass inside `ChatwootMarkdownRenderer#render_as_html_safe`. That method is
(`lib/chatwoot_markdown_renderer.rb:26-30`) nothing but `html.html_safe` — so R1.1 is adding a control where
none exists, which is correct. But that method is shared by `render_article` **and** `render_message`, i.e.
every conversation message in the product, and the HTML it carries legitimately includes iframes from 8
providers, a `<video>`, `<colgroup>`/`<col>` with inline `style`, `<sup>`, and `<img>` with a bounded inline
`style`. An allowlist written from memory would silently strip one of those.

So the next unit derives the allowlist from what the renderers actually emit — enumerated from
`CustomMarkdownRenderer`, `BaseMarkdownRenderer`, the embed templates and the corpus — and gates adoption on
the existing 68-example security suite plus a corpus round-trip. R1.3 landing first is what makes this
tractable: with no provider emitting `<script>`, the allowlist never has to permit one.

### R1.5 — the finding: a meaningful `frame-ancestors` is not available from this controller

`base_controller.rb:67-69` deletes `X-Frame-Options` for any `?show_plain_layout=true` request and sets
nothing in its place, so any site can frame a documentation page. The obvious fix — the pattern
`widgets_controller.rb:79-86` already uses — is to send `Content-Security-Policy: frame-ancestors <allowlist>`.

**It does not transfer, and shipping it would break the product.** `frame-ancestors` is evaluated against the
**entire** ancestor chain, and the plain layout has three consumers:

| Consumer | Ancestor chain | Needs |
|---|---|---|
| `widget/.../ArticleContainer.vue:39-49` — the live-chat article viewer | **the customer's own website** → widget iframe (this origin) → article viewer | every domain any customer embeds the widget on |
| `dashboard/.../ArticleSearch/SearchPopover.vue:52` | this origin | `'self'` |
| `portal/portalHelpers.js:146` — public portal search | this origin, or the portal's custom domain | `'self'` + custom domain |

The widget case means `frame-ancestors 'self'` would stop the article viewer rendering on every customer site.
The allowlist that would satisfy it is per-inbox (`@web_widget.allowed_domains`) and is not knowable in a
portal controller, which has no inbox.

What the exposure actually is: the plain documentation layout is public read-only content with no authenticated
action and no form, so there is nothing for a framing attacker to redress. Severity is low, which is why this
is recorded with a proposal rather than patched blind — a wrong fix here is a production outage on every
customer's website, and this phase has already shipped two confident fixes that broke things.

**Proposal for the owner, to be taken as its own decision:** serve the plain layout at a route the widget
requests with the inbox context it already has, so the response can carry that inbox's
`frame-ancestors`, and keep the dashboard/portal callers on `'self'`. That is a routing change, not a header
change, and it belongs with R12 rather than inside a ruling about sanitization.

---

## Gates run for this unit

| Gate | Result | Exit |
|---|---|---|
| `scripts/documentation_gate.sh` (derived; now **38** spec files — it picked up the new helper spec with no edit, which is the property it exists for) | 1074 examples, 0 failures | **0** |
| `spec/lib` + `spec/helpers` — the embed/render blast radius | 803 examples, 0 failures | **0** |
| RuboCop on every changed Ruby file | no offenses detected | **0** |
| eslint on both changed JS files | 0 errors | **0** |
| vitest — `VideoEmbedInput` and all of `dashboard/helper` | 50 files, 1219 tests passed | **0** |
