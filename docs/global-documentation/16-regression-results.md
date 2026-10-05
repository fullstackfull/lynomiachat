# 16 — Regression results

Every gate in this document was run against the phase's own head, on the same machine and the same database as the
phase before it, so the numbers are comparable rather than merely green. The baseline throughout is the
WhatsApp Template Manager phase (P3) at `53dd50b8`, recorded in
`docs/whatsapp-template-manager/FINAL-CHECKPOINT.md` items 64–67.

---

## 1. The gates, against the P3 baseline

| Gate | P3 baseline | This phase | Reading |
|---|---|---|---|
| Full RSpec | 10,635 examples, **2 failures**, 67 pending | *see §2* | *see §2* |
| Full Vitest | 492 files, 5,170 tests, **0 failures** | **493 files, 5,177 tests, 0 failures** | +1 file, +7 tests — exactly this phase's `featureHelper.spec.js` |
| ESLint | **0 errors**, 510 warnings | **0 errors, 510 warnings** | identical. No warning sits in any file this phase touched |
| RuboCop | 3,442 files, **0 offences** | **3,458 files, 0 offences** | +16 files — this phase's own Ruby |
| Production asset build | clean | *see §4* | |
| Documentation browser journey | — | **22 / 22** | new to this phase |
| Ownership and tenancy request spec | — | **25 examples, 0 failures** | new to this phase |

---

## 2. RSpec

*(Filled in from the completed run; see the run log in the scratchpad as `p4-rspec-full.txt`.)*

The P3 baseline's two failures are both pre-existing and were already pre-existing at P2:

- `spec/builders/agent_builder_spec.rb:47`
- `spec/enterprise/services/voice/call_transcription_service_spec.rb:77`

Neither is in a file or a subsystem this phase touches. **A failure beyond that pair is a regression**, and is treated
as one rather than as a flake — the rule this project has used since P2 is that a failure is reproduced in isolation
and root-caused before it is characterised at all.

### Specs this phase changed, and why

Three model specs were edited, and in each case the edit records a genuine change to the association contract rather
than accommodating a broken test:

| Spec | Change | Why |
|---|---|---|
| `spec/models/portal_spec.rb` | `belong_to(:account)` → `.optional` | a platform portal belongs to no account; the association genuinely became optional |
| `spec/models/category_spec.rb` | same | a platform category inherits that |
| `spec/models/article_spec.rb` | same | a platform article inherits that |

One upstream spec was rewritten because it asserted a defect:

| Spec | Was | Now |
|---|---|---|
| `spec/controllers/public/api/v1/portals/articles_controller_spec.rb` — *does not increment the view count if the article is not published* | expected a **2xx** for an unpublished article, and only asserted the view count had not moved | expects **404** |

That spec was the reason the defect survived: a draft article was publicly readable, with its full content, because
`set_article` resolved against `@portal.articles` rather than `@portal.articles.published`. The spec's own name said
the article was not published; its expectation said the response was a success. Fixing the controller made the old
expectation fail, which is how the defect surfaced. Both are in §3 of
[14-security-and-tenancy.md](14-security-and-tenancy.md).

---

## 3. What was proven in a browser, not asserted

### The documentation journey — 22 / 22

`/opt/node-tools/p4-docs.mjs`, Chromium, against the production-mode server on this machine.

| | Check |
|---|---|
| 1 | the `/docs` address lands on the documentation |
| 2 | the eleven sections are all there |
| 3 | it is branded as Lynomia Chat, with no upstream brand in the chrome |
| 4 | a contextual help key opens its article |
| 5 | the article explains the rule, not the buttons (5,409 characters of body) |
| 6 | no upstream brand in the content |
| 7 | the provider matrix states what each platform cannot do |
| 8 | search finds the audience articles |
| 9 | the Arabic documentation is in Arabic (`lang=ar`) |
| 10 | and lays out right to left (`dir=rtl`) |
| 11 | it uses the product's own Arabic words |
| 12 | Arabic search finds an Arabic article |
| 13 | the `/changelog` address lands on the changelog |
| 14 | with a release note that says where the history starts |
| 15 | an article that does not exist fails safely (404, not 500) |
| 16–19 | the documentation fits 390 / 768 / 1024 / 1280 px with no sideways scroll |
| 20 | the first tab stop is reachable and named |
| 21 | every link and button has an accessible name (0 unnamed) |
| 22 | no request the documentation makes fails |

### Draft visibility — 9 / 9

Part 10 asks that a draft never appear publicly and that a Super Admin be able to preview one before publishing.
That was proven against the running installation with a real draft article, rather than only in a request spec:

| | Check | Result |
|---|---|---|
| 1 | anonymous read of the draft | **404** |
| 2 | anonymous read through the `/docs/:slug` help link | **404** |
| 3 | the draft is absent from public search | **absent** |
| 4 | the draft is absent from the public index | **absent** |
| 5 | a Super Admin reaches the article list | **200** |
| 6 | a Super Admin previews the unpublished draft | **200, and the draft body is rendered** |
| 7 | the same URL stays refused for an anonymous visitor | **404** |
| 8 | after publish, anonymous read succeeds | **200** |
| 9 | after unpublish, anonymous read is refused again | **404** |

The draft was deleted afterwards. The script is in the scratchpad as `p4-draft-proof.sh`.

### Contextual help resolution — 43 / 43

Every key in `documentationLinks.js` was resolved against the running installation. All 43 redirect (302) to a
published article; none 404s. A dead help link is the failure mode a registry is supposed to prevent, so it is
checked mechanically rather than by reading the file.

---

## 4. Sanitization

The documentation renders Markdown through the same `ChatwootMarkdownRenderer` the tenant Help Center uses. Five
payloads were rendered and the output inspected:

| Payload | Result |
|---|---|
| `<script>alert(1)</script>` | neutralised |
| `<img src=x onerror="alert(1)">` | neutralised |
| `[click](javascript:alert(1))` | neutralised |
| `<a href="#" onclick="alert(1)">x</a>` | neutralised |
| `<iframe src="…"></iframe>` | neutralised |

Two reflected paths were checked live: the public search parameter is HTML-escaped in the page, and an article's
`meta.description` is escaped in the `<meta>` tag (an apostrophe arrives as `&#39;`).

This is the renderer's existing behaviour, not something this phase added. It is recorded because the documentation
portal is the first portal whose content is authored by the platform and read by everyone, so the question is worth
answering with output rather than with trust.

---

## 5. What was not run, and why

- **Real-provider verification of anything.** This phase adds no provider integration.
- **A load test on documentation search.** Public search is portal-scoped and uses the existing pg_search index; the
  corpus is 86 articles. There is nothing here that the tenant Help Center does not already do at larger scale.
- **Accessibility audit beyond the journey's two checks.** The journey asserts a reachable, named first tab stop and
  zero unnamed links and buttons across the documentation pages. A full audit of the Help Center layout is upstream
  surface that this phase did not change.
