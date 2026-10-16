# What was verified, and how

Every line below is a check that was run against the running application on a development host, with the
seeded demo account. Where a check found something, it says what, and what was done about it.

Nothing here was run against production. Production is changed only by the steps in
`11-publishing-procedure.md`, each of which an operator takes deliberately.

## The marketing site

| Check | How | Result |
| --- | --- | --- |
| All 48 slugs are published in both locales | `bundle exec rails marketing:verify` | pass — "all 96 pages are published" |
| Every page answers 200 at phone and desktop width | `node tools/visual/marketing-gate.mjs` — 48 slugs x 2 locales x 2 viewports | pass, 192 renders |
| Arabic is RTL and English is LTR | the gate reads `<html dir>` and `<html lang>` on every render | pass |
| One `<h1>` per page, and a non-empty `<title>` | the gate counts them | pass |
| No missing translations | the gate looks for "Translation missing" in the rendered text | pass |
| No horizontal overflow | the gate measures `documentElement.scrollWidth` at 390 and 1440 | pass |
| Every documentation link is in the reader's language | the gate reads every `/docs/` href and checks the `-ar` suffix against the page's locale | pass, after the fix below |
| Every documentation link resolves | the gate asks the local server for the article each one names | pass |
| Pricing renders published plans, in both languages | `curl /pricing` and `/en/pricing` | pass — three plans, named limits, named channel chips, the quote form kept as the secondary path |
| The figures published on the homepage match their sources | `node tools/visual/crop.mjs --check` | pass (4 figures; they were stale against the re-captured sources and were regenerated) |
| The new detail-page sections apply cleanly | `bundle exec rails marketing:enrich:plan` | pass — 32 declared, 0 with a problem |

### What the gate caught

**Every Arabic marketing page linked into the English documentation.** A catalogue entry declares a `docs`
slug, and the detail page handed it straight to the route helper. But that string is the article's **key**,
not its slug: the Arabic row's slug carries an `-ar` suffix. Eleven detail pages, in Arabic, sent the reader
to an English article.

`MarketingHelper#marketing_docs_article` now resolves the key through
`Documentation::Library.article_for(key, locale:)` — the resolver the product's own contextual-help links
already use, which falls back to the default locale when a language has no translation — and the page draws
the link only when a published article answers it. The gate checks it on all 96 pages so it cannot come back.

## The documentation

| Check | How | Result |
| --- | --- | --- |
| The corpus applies cleanly | `bundle exec rails documentation:content` — its preflight reads every file and writes nothing on any defect | pass, after two fixes below: 44 created, 65 updated, 73 unchanged, 0 untracked |
| Every figure rebuilds from its source | `node tools/visual/build-annotations.mjs` | pass, 26 images from 26 captures |
| The figures attach and nothing is orphaned | the seeder's own media pass | 22 attached, 2 replaced, 2 unchanged; sweep 0 purged, 0 unreferenced |
| Both languages have the same articles | the seeder's own parity check | pass — 91 and 91, 182 published |
| Every article URL answers | all 182 slugs, `curl -o /dev/null -w %{http_code}` | pass — 182 of 182 returned 200 |
| Every published figure answers | every `<img src>` the 182 pages render | pass — 26 of 26 returned 200 |
| The Arabic article links to Arabic articles | read the rendered `href`s on `website-live-chat-ar` | pass — every one carries `-ar` |

### Two things the preflight caught

**A description with a colon in it is not YAML.** `description: Decide how conversations are handed out: in
turn...` parses as a nested mapping and the file is dropped from the plan. Two files, both quoted now. The
preflight named them; nothing was written.

**Every Arabic cross-link went to the English article.** An article links to another with a bare slug, and
the browser resolves that against `/docs/<slug>` — but every locale except the default suffixes its slug,
so `[اربط أول قناة](connect-your-first-channel)` in an Arabic article opened the English one. 672 links in
86 articles, silently, with no 404 to notice it by.

Fixed in the corpus, and the seeder now refuses it: `Documentation::ContentSeeder::Corpus#link_problems`
checks every bare relative target against the slugs of the article's **own** locale.

## The screenshots

| Check | How | Result |
| --- | --- | --- |
| Every published figure comes from a real capture | `docs/screenshots/library.json` names the source, the screen, the environment and the command for each | 26 images from 13 captures |
| No credential is published | the install-snippet figure covers the website token with a redaction drawn in the annotation layer; the capture itself is unedited | pass |
| The Arabic figures are the Arabic interface | captured with `accounts.locale = 'ar'`, not mirrored from English | pass |
| The widget pair is one real message | the widget capture sends it; the dashboard capture opens the conversation it created, by that conversation's id | pass |

### What the captures found

**A published screenshot was of the wrong screen.** The homepage hero opened whichever conversation sat at
the top of the list, which in this seed is a Facebook thread: it carries the "you cannot reply due to 24
hour message window restriction" banner, and the composer is locked to Private Note. The shot now opens a
conversation on a named channel and presses Reply, and both are asserted after the clicks.

**Every widget screenshot was taken in the away state**, because the seeded website channel has no members
and the widget asks which agents of *that channel* are online. The fixture gives it three, and
`tools/visual/agent_presence.rb` holds their presence up for the length of a capture run.

**255 of the seeded conversations had no messages.** The fixture cloned conversation rows without their
messages, so the conversation list in the homepage hero read "No Messages" 235 times. The clone now copies
the messages.

### Two things the Arabic figures caught in the annotator

**Every Arabic figure drew its number underneath its own label.** The numbered dot is positioned with
`transform: translate(-50%, -50%)` and no `left`, so it fell at its *static* position — and that position is
direction-dependent: under `dir="rtl"` a box is placed by its right edge, which put the dot a whole width to
the left of the control it points at, behind the label. `tools/visual/annotate.mjs` now anchors the dot with
`left: 0` on the zero-sized marker, so the translate is the only thing that moves it, in either direction.

**Every Arabic label landed on the side with less room.** The automatic side choice reads a physical
position (`x > 55`) and its answer was then mapped back through the reading direction, which negated it a
second time. The named `side` in a spec is still a reading side — `start` is the left in English and the
right in Arabic — but the automatic choice is now physical. The four figures that name `side` explicitly are
unchanged by this; they were written around the defect and still render identically.

## Found, and deliberately not fixed here

**Relative times in the Arabic dashboard are in English.** `dynamicTime` in
`app/javascript/shared/helpers/timeHelper.js` calls date-fns `formatDistanceToNow` without a `locale`, so an
Arabic reader sees `الاستحقاق in 1 day` on a support case's SLA badge — the sentence is Arabic and the
interval inside it is English. It is one call site with 58 callers across the dashboard, and it is visible in
the published `support/support-cases-ar` figure, which shows the Arabic interface as it actually is rather
than a corrected one.

This is dashboard i18n, not marketing or documentation, and the brief for this release says not to merge
dashboard work into it. It is recorded here so it is a decision rather than an oversight.
