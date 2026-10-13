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

---

## Post-merge corrections — two defects the merged release candidate carried

Found by an adversarial audit of the frozen diff, run **after** `6232d783` had already been merged into
`lynomia-custom` as `2a5cc568`. Both are mine, both are recorded rather than quietly fixed, and both are proven
both ways.

### C1 — R1.3 left a stale spec red, and the gate could not see it

`spec/config/markdown_embeds_spec.rb` asserted the exact 11-provider key set and iterated a `test_cases` hash
that still contained `wistia` and `github_gist`. After R1.3 removed those two providers it failed twice:
`match_array` reporting `the missing elements were: ["github_gist", "wistia"]`, and
`NoMethodError: undefined method '[]' for nil` at line 92 where `config['wistia']` is indexed. Reproduced:
**5 examples, 2 failures**. Green before the change, red after — a regression, not a pre-existing failure.

Worse than the failure: **the release candidate shipped two specs asserting contradictory contracts** about the
same file, since `markdown_renderer_security_spec.rb` asserts the 9-provider set.

And the gate reported green. `scripts/documentation_gate.sh` selected 38 files by subject pattern; the pattern
was `markdown_renderer`, and the stale spec's path contains `markdown_embeds`. The repository's real CI runs
every spec (`.github/workflows/run_foss_spec.yml:131` is `find spec -name '*_spec.rb'`), so this was red on the
mainline, not merely latent.

Fixed: the spec now asserts the 9 remaining providers, with a comment saying adding one must fail the
assertion, plus a new example that no template contains `<script`. **6 examples, 0 failures.**

#### The gate now has two independent selectors, and the second needs nobody to pick a good pattern

This is the **second** time gate selection has been wrong in the same way — round one was a *directory* named
where a sibling *file* mattered (the 500 on the documentation home page, §M5 of the P0 report); round two was a
subject pattern one token too narrow. Widening the token to `markdown` fixes this instance and does nothing
about the next one, so the script gained a selector that does not depend on pattern choice at all:

| Selector | Mechanism |
|---|---|
| 1. Subject patterns | the documentation subsystem by subject, derived from the filesystem as before (`markdown`, not `markdown_renderer`) |
| 2. **Changed-file coverage** | for every source file the branch changes, **any** spec anywhere under `spec/` whose basename matches is added to the run. No mapping table, no directory assumptions: `config/markdown_embeds.yml` finds `spec/config/markdown_embeds_spec.rb` by name alone |

Selector 2 deliberately over-selects — several specs can share a basename. Over-running is the correct bias for
a gate; under-running is what shipped a 500 and a red mainline.

**Proven, not asserted.** Narrowing selector 1 back to the old `markdown_renderer` token and running with the
pre-change baseline, selector 2 found the file on its own and labelled it:

```
spec/config/markdown_embeds_spec.rb
(39 spec files; baseline 46836de0)
added by changed-file coverage, not by any subject pattern:
  spec/config/markdown_embeds_spec.rb
```

When no baseline ref resolves, the script says so loudly on stderr and names `GATE_BASE_REF` rather than
silently dropping a selector — a gate that quietly loses coverage is the whole bug.

### C2 — the WhatsApp tile gating was wrong at the premise, and I shipped it

**Withdrawn: §N.5 of the P0 report.** It said WhatsApp "was the one OAuth/SDK provider offered
unconditionally" and applied the three conditions `useChannelConfig` uses. That reasoning treats the WhatsApp
tile as an entry to Meta embedded signup. It is not.

The tile opens a **provider selection page** (`settings/inbox/channels/Whatsapp.vue:98-125`) offering:

| Provider | Needs the Meta app id / configuration id? |
|---|---|
| WhatsApp Cloud — description switches to *manual setup* when embedded signup is unavailable | **No** |
| Twilio | **No** |
| WhatsApp Business App (Meta embedded signup) | Yes — and the page already omits it unless `canUseEmbeddedSignup` |

So the page already degraded correctly on its own. Gating the tile removed the only route to the two
Meta-independent flows: an installation running **Twilio or manual Cloud API** — the normal state when
`WHATSAPP_CONFIGURATION_ID` was never set, since `config/installation_config.yml:175-178` declares no default
— had **no UI path to create a WhatsApp inbox at all**. The onboarding wizard already filters the channel for
the same reason (`useChannelConfig.js:21-29`, pre-existing, not introduced here), and
`ChannelList.vue:108` is the single `router.push` to that route, so nothing else reached it.

Reverted. `whatsapp` is back in the unconditional list, with a comment at the site saying why it is not
analogous to facebook/instagram/tiktok. The problem the gate was meant to solve is already solved where it
belongs: `useWhatsappEmbeddedSignup` refuses **before loading the SDK** with a named error instead of sending
`config_id: undefined` to Meta. That guard stays — it is the part of §N.4 that was right.

The five examples now assert the tile **stays enabled** with the credentials absent, blank, `'none'`, or with
no installation config at all. Against the gated version: **5 failures**. With the revert: **10/10**.

### What these two have in common, and the rule they produce

Both come from reasoning about a shared surface from one caller's point of view. R1.3 changed a config file
without asking which specs read it; §N.5 gated a tile without opening the page behind it. The P0 report's §N.8
already recorded three over-broad greps with the same shape. The rule, now encoded rather than intended:
**before changing a shared file, enumerate its readers — specs included — and open the surface it feeds.** The
gate's selector 2 enforces the first half mechanically.

---

## R1.1 — boundary derived, proposal REJECTED by its own adversarial pass, one new finding

The owner's condition was: prove the selected boundary preserves all legitimate existing renderer output before
committing. Five independent inventories were run — four static readings and one that **measured** rather than
read — then a design pass, then three refuters. **No sanitizer code is committed.** The design is rejected on
its own evidence, and the exercise produced one finding worth more than the sanitizer would have been.

### What the measurement settled: one shared profile is not available

Rendering a 23-case corpus plus all 126 real articles through both public methods and taking the
`Nokogiri::HTML5` union:

| | `render_article` | `render_message` |
|---|---|---|
| Elements | **32** | **20** |
| Distinct `style` values | **18** | **2** |
| Only on this path | `iframe`, `video`, `source`, `table`, `thead`, `tbody`, `tr`, `th`, `td`, `colgroup`, `col`, `div`, `sup` | `del` |

Neither set contains the other, so a single safelist must be their union — which would permit
`iframe[src,allow,allowfullscreen,…]`, `video`, `source` and `div[style]` on **every conversation message and
every outbound email**, including contact-authored incoming content replayed into agent notification mail. That
is precisely the "dangerous universal safelist" the owner's instruction names. `height: Npx;` is
**message-only** (`lib/base_markdown_renderer.rb:29-30` honours `cw_image_height`;
`lib/custom_markdown_renderer.rb:131-133` reads width only), so even the `style` policies differ by path.

Two further measured facts, recorded because they will matter whenever this is picked up again:

- **`Rails::HTML5::SafeListSanitizer` delegates `style` to Loofah's global CSS safelist with no per-call
  override** (`rails-html-sanitizer-1.7.1/lib/rails/html/sanitizer.rb:160-171`). It scrubs declarations
  individually, and `position`, `top`, `left`, `table-layout`, `box-sizing`, `border` and `max()` are not
  permitted — so a naive safelist silently degrades every embed aspect-ratio box and both table-sizing modes.
  Widening those gem constants is global and would also change `app/models/channel/telegram.rb:150` and
  `app/services/data_imports/importer.rb:804`.
- The way around it needs **no gem patch**: `sanitize` with `options[:scrubber]` does `fragment.scrub!(scrubber)`
  and nothing else, so an application-owned `Loofah::Scrubber` owns the whole policy and `style` values survive
  byte-for-byte. Verified independently by two agents against the vendored source.

### Why the proposal was rejected

A prototype was built and measured: 28 fidelity cases with 0 losses, all 126 corpus files unchanged, 20 attack
payloads neutralised (including `:UNSAFE`-simulated `script`/`svg`/`form`/`srcdoc`/mXSS, `javascript:` hrefs, a
`position:fixed` overlay and CSS `url()` exfiltration), and 266 consumer examples passing unchanged. It still
fails, on three findings I accept:

| | Finding | Why it is disqualifying |
|---|---|---|
| **A1 — fatal** | The profile pins `iframe@src` to 7 derived hosts, and one of them is **`codepen.io`, whose product is to execute the author's own JavaScript**. See K18 below | The control presented as the answer to "an attacker host" blesses a host that runs attacker code. Internally inconsistent with R1.3, which removed `github_gist` because its content is attacker-authored — a Gist *renders* attacker text, a pen *runs* attacker script |
| **A2** | The iframe attribute **names** are a hardcoded 15-item list with no `sandbox`, `referrerpolicy` or `csp`; attribute **values** are auto-derived from the YAML | Fail-open for widening, fail-closed for hardening. It would silently delete a security attribute a future developer adds to a template, and the fix would work in the editor preview and not in production |
| **A3** | `permitted_style?` tests one **element-agnostic** exact set, so the embed wrapper's `position: absolute; top: 0; left: 0; width: 100%; height: 100%;` is accepted on `div`, `img`, `table` **and** `iframe` alike | Hands back the overlay primitive the sanitizer is partly there to remove |

A second refuter found one **false positive** that is not fatal but is a real regression of a shipped feature:
the article profile strips `style` from a **resized mp4 `<video>`**, because `apply_embed_width`
(`lib/custom_markdown_renderer.rb:178-186`) mutates `fragment.elements.first` — the wrapper `<div>` for the 8
iframe providers, but the `<video>` itself for `mp4`, whose template has no `style`. The existing spec that pins
that value drives `CustomMarkdownRenderer` directly rather than `render_as_html_safe`, so it would have kept
passing and the regression would have shipped silently. That is the fourth gate-blindness of this program and
the same shape as the others.

The third refuter attacked the **shape** and could not break it: one module beside the two that already own this
boundary, one pass at the existing choke point, `:DEFAULT` untouched, no parallel system, no gem patch, complete
entry-point coverage (the only three construction sites are `lib/chatwoot_markdown_renderer.rb:7,14` and
`app/services/messages/markdown_renderer_service.rb:44`, the third proven to be an independent path rather than
a duplicated backup guard). So **the shape survives and the policy does not**. The next iteration keeps
two application-owned profiles at that choke point and must: derive iframe attribute names from the templates
the same way values are derived; key the `style` policy per element; fix `apply_embed_width` so the width lands
on the wrapper rather than the root; and settle K18 first, because an iframe host policy is meaningless while a
blessed host executes author code.

### K18 (new, open) — `codepen` renders author-controlled JavaScript in an un-sandboxed frame on a public page

**This is reachable today. It needs no `:UNSAFE`, no sanitizer, and no change from this program.** One markdown
link in an article body —

```
[v](https://codepen.io/attacker/pen/EvilPen)
```

— expands through `config/markdown_embeds.yml` into an `<iframe src="https://codepen.io/attacker/embed/EvilPen">`
on the public, unauthenticated article page. Verified in the repository: **no template in that file sets
`sandbox` or `referrerpolicy`** (grep count: 0), and the live CSP is only `object_src :none` + `base_uri :self`
(`config/initializers/content_security_policy.rb:14-17`) — there is no `frame-src` and no `script-src`, and
ruling item R1.5 defers that CSP to a later contract. Without `sandbox`, a cross-origin frame may navigate the
**top-level** page, so the consequence is a silent redirect of a Lynomia documentation URL to a phishing clone.

**Severity, stated honestly.** The attacker must be a **Lynomia Super Admin content author** — tenants cannot
author documentation at all, by the owner's product rule. So this is insider threat and defence in depth, not a
path for an untrusted user. It is recorded as a finding rather than silently fixed because the two candidate
fixes are not mine to choose:

1. **Remove the provider**, exactly as R1.3 did to `github_gist` on exactly this rationale. Cost is **nil on
   content** — the corpus uses zero embeds — and the change is one config block plus one spec line. It is
   consistent, needs no browser, and is trivially revertible. It goes one step beyond R1.3's letter, so it is
   the owner's call.
2. **`sandbox` the iframe templates.** Correct in principle and the general fix, but which `sandbox` tokens let
   each of the 9 providers still play is **not verifiable without a browser**, and shipping it unverified would
   break video playback on the documentation pages. Needs per-provider verification first.
3. Treat it as subsumed by the deferred `frame-src`/`script-src` CSP work, accepting the exposure until then.

**I also corrected my own false comment.** The header I added to `config/markdown_embeds.yml` in the R1.3 commit
argued the remaining templates are safe because an iframe is "isolated in its own origin". That is true and it
is **not a sufficient safety argument** — origin isolation stops the frame reading this page's DOM and cookies;
it does not stop top-level navigation and it does not make the framed content non-executable. The comment now
says so and points here, rather than being quietly deleted. A false safety claim beside a security rule is what
makes the next reader trust the wrong thing.
