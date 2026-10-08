# P7 — Test coverage backfill

Measured first, then written. The brief named "the Template Manager's 13 services, Documentation services, /docs
and /changelog", on the premise that none of them had specs. Half of that premise was wrong, and measuring was
what made the work small enough to finish properly.

## What the premise got wrong

The 13 template services have no spec files of their own, and ten of the thirteen are not named in any spec. But
`spec/controllers/api/v1/accounts/whatsapp/message_templates_controller_spec.rb` drives the whole stack through
real requests, and SimpleCov puts that at **92.34% (398/431 lines)** across all thirteen before a line was
written. Absence of a spec file is not absence of coverage.

So the backfill was 33 lines, not 13 services — and because they were measured rather than guessed at, each one
could be read and judged on whether being wrong there would be silent.

The documentation side was the opposite: the gap was real and larger than stated.

| Area | Before | After |
| --- | --- | --- |
| the 13 WhatsApp template services | 92.34% (398/431) | **100% (431/431)** |
| `Documentation::ContentSeeder` | 32.8% | **100%** |
| `DocumentationController` (`/docs`, `/changelog`) | 70.6% | **100%** |
| `Documentation::Library` | 88.9% | **100%** |

## The template services

`spec/custom/services/whatsapp/templates/validator_spec.rb` — 25 examples. The validator is the authority both
the builder and the submit path read, and the 20 lines the controller spec never reached were all rules whose
absence is silent: a template Meta will reject gets submitted, or one Meta would accept gets blocked.

- the header, entirely: an unsupported format, a text header over sixty characters, more than one variable, a
  missing sample value, and a media header with and without its uploaded handle
- a phone-number button over twenty characters
- a copy-code button with no coupon code, and one longer than the **send path** accepts — held at 15 rather than
  Meta's 20 on purpose, because a template authored up to 20 would be created at Meta and then fail to send
- named variables: a name that is not lowercase letters, digits and underscores, and the same name used twice
- positional sample values read out of Meta's nested array, and out of the flat shape, and reported missing when
  fewer are given than the text needs
- a parameter format Meta does not offer

Writing these found a rule worth its own examples: **a variable at the very start or end of the text is refused**.
Three drafts failed on `variable_at_edge` before anything else, which is correct behaviour and was not obvious
from the uncovered-line list. It now has three examples of its own.

`operation_error_mapping_spec.rb` — 9 examples. What a Graph refusal becomes for the person who caused it, reached
through an edit and a delete, which the controller spec does not exercise. A duplicate name, a dead token, a 429,
a 5xx and everything else map to five distinct codes; Meta's own end-user sentence is passed through where it
wrote one and omitted where it did not; the error a caller sees carries no raw body or trace id; and a refused
edit leaves the local row describing what Meta still holds rather than the attempted change.

`query_spec.rb` — 6 examples. The deliberate difference this service exists to hold: management reads reconciled
rows, while "what can this inbox send" reads the channel's own synced snapshot, so a send never depends on a
projection having run. An authentication template is excluded from **selection** even though a send would accept
it, which is today's product rule made explicit.

`duplication_spec.rb` — 3 examples. A copy of a template carrying one of Meta's pre-2022 categories starts as
UTILITY, because a user may not author the old one; and a copy brings no id, no status and a new name, because
Meta blocks a deleted approved template's name for thirty days.

## The documentation services

`spec/custom/services/documentation/content_seeder_spec.rb` — 17 examples, against a temporary corpus rather than
the shipped one, so they assert the seeder's behaviour instead of restating the contents of
`custom/db/documentation`.

The one that matters most: **running it again changes nothing.** `created=2` on the first run, then
`created=0 updated=0 unchanged=2` on the second and the third. That is the property that makes
`rails documentation:content` safe to run on every deploy, it is the whole reason the corpus lives in source
control, and nothing asserted it — it had only ever been proved by hand. Also covered: a changed file updates
rather than duplicating, a new file leaves the others alone, the slug is derived from the file name with a
per-locale suffix, the key is stored in `meta`, the translation is linked to the default-locale article, the
category is created per locale at its manifest position, `publish: false` leaves drafts, an explicit
`seo_description` wins over the description, only the portal's allowed locales are seeded, and the two ways a bad
file fails loudly (no front matter, no title) rather than seeding a corpus with a hole in it.

`spec/requests/documentation/entry_points_spec.rb` — 10 examples. `/docs` and `/changelog` are the stable
addresses the product links to, and **nothing asserted that they redirect at all.** They now have: each goes to
its portal's public renderer, neither carries a locale of its own (the portal's own redirect decides that), a
contextual help link resolves a published article by its key and 404s for a key no article carries, and all three
addresses say "not set up" with the translated string rather than redirecting into nothing when a platform portal
is missing. `Documentation::Library.docs_portal!` and `changelog_portal!` raise rather than returning nil, because
routing around a missing portal would hide the setup bug.

## Gates

| Gate | Result |
| --- | --- |
| the four new template spec files | 43 examples, 0 failures |
| template services, line coverage | 100% (431/431), measured with SimpleCov |
| the two new documentation spec files | 27 examples, 0 failures |
| documentation services and controller, line coverage | 100% (108/108) |
| the whole documentation suite including the corpus gates | 341 examples, 0 failures |
| `rubocop` on all six new spec files | no offenses |

## What is not claimed

- **This is line coverage, not branch coverage.** A line can be covered by one of its two outcomes. Where a
  branch mattered, both sides were written deliberately — the copy-code limit, the media header handle, the
  nested and flat sample shapes — but the number above is lines.
- **No spec here calls Meta.** Every Graph interaction is stubbed; the real-provider UAT remains a separate,
  externally gated item.
- **Coverage of these four areas says nothing about the rest of the suite.** The measurement was scoped to the
  files the brief named.
