# Pre-deploy condition 2 — licence closure

Two licence items were left open by P-FINAL. Both are closed here, by measurement.

**This document is not a legal opinion and claims no legal clearance.** It records what was measured, where the
evidence came from, and what remains open. Whether this repository's overall distribution satisfies every
obligation that applies to it is a question for a licence review.

---

## 1. The Inter fonts — CLOSED

### 1.1 What was open

`docs/p-final/02-license-audit.md` §5.1 and `07-release-gate.md` #53 recorded it bluntly: 38 `.woff2` binaries
under `app/javascript/shared/assets/fonts/{Inter,InterDisplay}/` are redistributed with **no OFL text anywhere
in the tree**. The SIL Open Font License obliges a redistributor to carry the copyright notice and the licence
text with every copy. `NOTICE.md` recorded the obligation and deliberately did not reproduce the licence from
memory, because an approximate copy of a licence is worse than a pointer to the real one. The remaining step
needed a network fetch P-FINAL could not make.

### 1.2 Identifying exactly what is bundled

Read out of the font files' own `name` table with `fontTools`, not from a changelog. **All 38 files agree on
every value.**

| name ID | field | value |
|---|---|---|
| 5 | version | `Version 4.000;git-a52131595` |
| 0 | copyright | `Copyright 2016 The Inter Project Authors` |
| 13 | licence | `This Font Software is licensed under the SIL Open Font License, Version 1.1.` |
| 14 | licence URL | `http://scripts.sil.org/OFL` |
| 9 | designer | `Rasmus Andersson` |
| 11 | vendor URL | `https://rsms.me/` |

The version string names its own upstream commit, `a52131595`, which is what made a version-exact fetch
possible rather than a best guess at the release.

**One correction to the earlier record.** `NOTICE.md`'s table named Rasmus Andersson in the **licence** column.
He is the designer (name ID 9); the copyright **holder** is "The Inter Project Authors" (name ID 0), and that is
the name an OFL notice has to carry. The table now has both, in the right columns.

### 1.3 The licence text, fetched byte for byte

| | |
|---|---|
| source | `https://raw.githubusercontent.com/rsms/inter/a52131595/LICENSE.txt` |
| cross-check | the `v4.0` tag returns a **byte-identical** file — same SHA-256 |
| SHA-256 | `262481e844521b326f5ecd053e59b98c8b2da78c8ee1bdbb6e8174305e54935a` |
| size | 4380 bytes, 92 lines, ASCII, LF endings |
| committed as | `app/javascript/shared/assets/fonts/OFL.txt` |
| verified after copying | same SHA-256; `cmp` reports identical |

Its first line is `Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter)` — the same
copyright holder the binaries carry, which is what ties the licence text to these specific files rather than to
Inter in general.

Nothing was written from memory, paraphrased or reconstructed. The fetch was from the commit the fonts
themselves name, not from upstream's current default branch.

### 1.4 A measurement that changed the wording

`NOTICE.md` said all 38 files are "served to every browser that loads the dashboard or the widget". Counting
the `@font-face` rules shows that is not quite right:

- **18 of 38 are served.** `inter.scss` (2 rules), `InterDisplay/inter-display.scss` (9) and
  `widget_fonts.scss` (7) carry 18 rules between them, covering `InterVariable`, `InterVariable-Italic`, seven
  static `Inter` weights and nine static `InterDisplay` weights.
- **20 are committed and referenced by nothing** — the static italics, plus some unused static weights.

The licence applies to all 38 either way: committing them to a distributed repository is distribution. Which
ones reach a browser only changes who else receives them. `NOTICE.md` now says this.

### 1.5 `THIRD_PARTY_NOTICES.md`

**There is no such file in this repository**, and one was not created. The only root-level licence file is
`LICENSE`. This repository's convention for third-party assets is a `NOTICE.md` beside the assets, which is
what `app/javascript/shared/assets/fonts/NOTICE.md` is and what P-FINAL established. Creating a new
repository-wide third-party notices file would mean tallying 381 resolved gems and 1,144 locked JavaScript
packages — the full licence audit this condition was told not to open (`07-release-gate.md` #52, which stays
OPEN).

### 1.6 Recommended follow-up, as its own change

`@fontsource/inter` would put the same fonts under a package manager, with the licence included and
version-pinned. That is the better long-term answer and it is a **build** change: it moves every `@font-face`
`src` in three stylesheets, all of which are on the critical rendering path of the dashboard and the widget.
It also makes the 20 unreferenced files a question somebody has to answer. It does not belong in a
pre-deployment pass.

---

## 2. The unmeasured gem licences — CLOSED

### 2.1 What was open

`07-release-gate.md` #51 was OPEN with two parts: "two production gems declare none in their gemspec; **ten
development and test gems were never measured**, because their group is excluded from this container's bundle."
`.bundle/config` excludes the `development` group, so those ten have no installed gemspec to read.

### 2.2 Method

Not guessed, and not read from my own knowledge of these gems. For each of the ten, the published `.gem` for
the **exact locked version** was fetched with `gem fetch`, and its licence read from its own gemspec with
`gem specification <file> licenses`. Each was then cross-checked against
`https://rubygems.org/api/v2/rubygems/<name>/versions/<version>.json`, and the downloaded artifact's SHA-256
compared with the `sha` the registry publishes for that version — so the file read is provably the published
artifact.

**Two independent sources agree on all ten, and all ten artifact hashes match.**

### 2.3 The ten development-group gems

All ten are in the single `group :development do` block, `Gemfile`:228–245. None is in `:test`.

| gem | locked version | licence | source | classification | redistribution relevance | action |
|---|---|---|---|---|---|---|
| `annotaterb` | 4.20.0 | **BSD-2-Clause** | gemspec + registry; artifact SHA-256 matches | development | none | none |
| `bullet` | 8.0.7 | MIT | gemspec + registry; SHA matches | development | none | none |
| `letter_opener` | 1.10.0 | MIT | gemspec + registry; SHA matches | development | none | none |
| `meta_request` | 0.8.5 | MIT | gemspec + registry; SHA matches | development | none | none |
| `rack-mini-profiler` | 4.0.1 | MIT | gemspec + registry; SHA matches | development | none | none |
| `scss_lint` | 0.60.0 | MIT | gemspec + registry; SHA matches | development | none | none |
| `squasher` | 0.7.2 | MIT | gemspec + registry; SHA matches | development | none | none |
| `stackprof` | 0.2.25 | MIT | gemspec + registry; SHA matches | development | none | none |
| `tidewave` | 0.2.0 | **Apache-2.0** | gemspec + registry; SHA matches | development | none | none — see §2.4 |
| `web-console` | 4.2.1 | MIT | gemspec + registry; SHA matches | development | none | none |

Eight MIT, one BSD-2-Clause, one Apache-2.0. **Zero indeterminate. Zero LEGAL REVIEW REQUIRED.**

**What "redistribution relevance: none" rests on, stated so it can be checked.** All ten are in the
`development` group, which `.bundle/config` excludes, so they are not installed by a production bundle; and
none is a dependency of any production gem. Two caveats, both recorded rather than glossed:

- `Rails.groups` is **not** simply `[:default, Rails.env]` — `railties/lib/rails.rb:106-115` also concatenates
  `ENV["RAILS_GROUPS"]`, so a host that set `RAILS_GROUPS=development` would require the group if it were
  installed. Nothing in this repository sets it, and `.bundle/config`'s exclusion means there would be nothing
  to require, but the claim is "excluded by configuration", not "impossible".
- This is a self-hosted application, not a published package. "Redistribution" here means the artefact a
  customer receives, and a development-group gem is not in it. If that ever changes — a distributed appliance,
  a published image — the licences above are already measured, which is the point of measuring them.

### 2.4 The one Apache-2.0 obligation worth checking

Apache-2.0 §4(d) imposes an extra obligation on a redistributor **only if** the work includes a `NOTICE` file:
that file's attribution notices must travel with derivative works. `tidewave` 0.2.0's own archive was listed:
it ships a `LICENSE` and **no `NOTICE`**. So §4(d) adds nothing here, and this is recorded so the next reader
does not have to re-derive it. It is moot in any case — the gem is not redistributed.

### 2.5 The two production gems — and the earlier record was right about the gemspec

| gem | locked | gemspec `licenses` | what the gem actually ships | classification |
|---|---|---|---|---|
| `ai-agents` | 0.12.0 | **`[]` — empty** | a verbatim **MIT License**, 21 lines, "Copyright (c) 2025 Chatwoot Inc.", at `ai-agents-0.12.0/LICENSE` | runtime (production) |
| `gmail_xoauth` | 0.4.3 | **`[]` — empty** | the **Unlicense** public-domain dedication, 23 lines, "This is free and unencumbered software released into the public domain.", at `gmail_xoauth-0.4.3/LICENSE` | runtime (production) |

`rubygems.org` agrees with the gemspecs: `licenses: []` for both, and no `metadata.license`. So #51's claim —
"declare none in their gemspec" — was **accurate**, and an earlier attempt in this work that reported them as
MIT and Unlicense from metadata was reading the shipped `LICENSE` file, not metadata. The distinction matters
enough to state: the **metadata** is empty, the **artifact** is unambiguous.

Both are therefore determinate, from the file the gem itself ships. These two are the only ones here with any
redistribution relevance, since both are production dependencies.

**Recommended follow-up, not a blocker:** both gems should declare `spec.license` in their gemspec. `ai-agents`
is published by Chatwoot, so that one is a one-line upstream pull request the team that maintains this fork can
open directly.

---

## 3. Summary

| # | item | before | now |
|---|---|---|---|
| 1 | Inter OFL text present with the fonts | **OPEN** — no OFL anywhere in the tree | **CLOSED** — `OFL.txt`, byte-identical to the upstream release the binaries name, SHA-256 recorded |
| 2 | The bundled Inter version identified | not recorded | **CLOSED** — 4.000, `git-a52131595`, read from all 38 binaries |
| 3 | Copyright holder named correctly | **wrong** — designer in the licence column | **CLOSED** — The Inter Project Authors, with the designer kept separately |
| 4 | Ten development-group gem licences | **OPEN** — never measured | **CLOSED** — 8 MIT, 1 BSD-2-Clause, 1 Apache-2.0; two sources each; artifact hashes verified |
| 5 | Two production gems with empty licence metadata | **OPEN** | **CLOSED** — MIT and Unlicense, read from the `LICENSE` file each gem ships; the empty metadata is confirmed, not contradicted |
| 6 | `tidewave` Apache-2.0 `NOTICE` obligation | not considered | **CLOSED** — no `NOTICE` in the gem, so §4(d) adds nothing |
| 7 | Transitive licence tally (381 gems, 1,144 packages) | **OPEN** | **STILL OPEN** — out of scope by instruction; `07-release-gate.md` #52 |
| 8 | The repository's own licence position | **RULE** | **STILL A DECISION** — see `02-product-decisions.md`, RULE 4 |

Items 7 and 8 are the only licence items still open. 7 is a scoping decision; 8 is one of the six product rules
and is the owner's to take.
