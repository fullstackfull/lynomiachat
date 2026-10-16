# The Lynomia design system, decided

The plan this redesign is built to, written before the code and reviewed against the brief before building.
Phase A (`00-visual-baseline.md`) measured what is wrong; this says what replaces it and why each choice is
a choice rather than a default.

---

## 1. Subject

Lynomia Chat is where a Gulf business's customer conversations arrive — WhatsApp, Instagram, website chat,
email, SMS, Telegram — into one inbox a team answers from, in Arabic. The reader is an operations or support
lead at a Saudi, Kuwaiti or Emirati company who currently has several phones on a desk. The page's job is to
make them believe those conversations can land in one place, and that the product is built by people who
know the market.

**The most characteristic thing in that world is an Arabic message arriving.** Not a chart, not an abstract
gradient. That is what the hero opens with.

---

## 2. Colour

The brief names the family — electric blue, royal blue, indigo, restrained pink/magenta — and all four
already exist somewhere in the product. They are now one ramp in `theme/colors.js` under `lyn`, and **each
one has a job that comes from contrast rather than taste**:

| token | hex | job | contrast |
| --- | --- | --- | --- |
| `lyn-ink` | `#0A1733` | body text, and the one dark field | 17:1 on white |
| `lyn-ink-soft` | `#2A3A5C` | secondary text | 10:1 on white |
| `lyn-royal` | `#1D3FA8` | links and text accents on paper | 9:1 on white |
| `lyn-blue` | `#0090FF` | focus rings, live dots, accents **on the dark field only** | 3.3:1 on white — so never body text, never a link on paper |
| `lyn-indigo` | `#5B5BF0` | the primary action, on every surface | white on it: 4.9:1 |
| `lyn-magenta` | `#D6246E` | one bold note per page | white on it: 4.9:1 |
| `lyn-paper` / `lyn-mist` / `lyn-line` | `#FFFFFF` / `#F3F5FB` / `#E2E7F3` | surfaces and hairlines | — |

Two of those are worth defending.

**Indigo as the primary action** is not a taste call. The Flutter app's primary is already `#6366F1`
(`lib/shared/styles/themes.dart`), and the `ui-ux-pro-max` design-system query for this brief returned
`#6366F1` independently. It is the one colour the website and the phone app can share, which is what
"unified identity" has to mean in practice.

**Electric blue is deliberately restricted.** `#0090FF` is only 3.3:1 on white and would fail AA as a link
colour — which is why `lyn-royal` does that job and `lyn-blue` is kept for focus rings, the live dot, and
accents on `lyn-ink`, where the contrast runs the other way.

The ramp is **additive**: nothing in the dashboard changes colour until a call site asks for `lyn-*`.

---

## 3. Type

Two families, one per script, which is the cleanest possible reading of "one family or two, and if two, make
them clearly distinct".

- **Arabic → IBM Plex Sans Arabic**, four weights, self-hosted (`app/javascript/marketing/fonts/`).
- **Latin → Inter**, the variable file this repository already ships.

They live in one Tailwind stack, `font-lyn`, and the Arabic `@font-face` rules carry a `unicode-range`, so
the browser picks the family per codepoint. An Arabic page sets `واتساب` in Plex and `WhatsApp` in Inter from
one class with no locale branch in any template, and an English page downloads no Arabic file at all.

**Why this mattered more than it sounds.** Until now the marketing site's `fontFamily.sans` was the system
stack — `-apple-system, …, Tahoma, Arial`. The primary market's language was being set in whatever font the
visitor's operating system happened to ship. Plex Arabic was chosen over Noto Sans Arabic, which is the
default answer and the one the design tool proposed: Plex is a contemporary, slightly technical Arabic face
that suits messaging infrastructure and is not the font every Arabic site already uses.

Scale and leading: hero 2.25rem → 3.5rem, section head 1.5rem → 1.875rem, body 1.0625rem, all with
`leading-[1.85]` on body copy and `leading-[1.3]` on display. **Arabic gets more leading than a Latin page
would** — the script's ascenders, descenders and diacritics need it, and the old `leading-relaxed` (1.625)
was set for Latin.

No ALL-CAPS anywhere; it carries no meaning in Arabic and is one of the commonest generated-page tells.

---

## 4. Layout and the rules the page is held to

1. **One magenta per page**, in the hero, as a block behind a phrase of the headline — never as coloured
   type, which is the "accent one word" tell. The operator names the phrase (`hero.highlight`), so the
   emphasis can move to wherever the sentence turns in each language.
2. **No two consecutive sections may take the same form.** The home page now runs: hero → specification row →
   rule-separated channel list → feature card grid → help cards on mist → one dark field. Before, three
   consecutive sections were the same bordered-white-card grid.
3. **The hero contains the product**, drawn in HTML in the page's own language, never an image of a
   dashboard.
4. **Arabic is designed first**; English is the flip. The layout is built from `start`/`end` logical
   utilities, so it is one piece of markup.
5. **Motion is one orchestrated moment** — the hero's entrance — behind `motion-safe:`. Nothing else moves
   on load.

### Reviewed against the brief before building

Three parts of the first plan were defaults rather than decisions, and were changed:

- **A gradient wash behind the hero** — cut. Gradient-as-decoration is a generated-page tell, and the page
  now has exactly one coloured field (the closing CTA), which is where the weight belongs.
- **Three big numbers for the stats** — demoted to a rule-separated specification row. Large figures under a
  headline compete for the same glance, and these three (`9 / 50+ / API`) are specification, not a boast.
- **Two floating pills over the panel** — reduced to one, moved below the card. Overlapping pills are what
  the old static page did, but its panel had no readable content underneath; this one does, and the pills
  were covering the first message and the composer. Depth now comes from a second plate offset behind the
  card instead.

Kept deliberately, against the usual advice: **the asymmetric hero with a product panel**, because the brief
names it as the old page's strength to preserve, and **the magenta highlight**, for the same reason — built
as a block rather than as coloured type.

---

## 5. What a reader is not allowed to lose

The site keeps every word of its honesty. Each channel still states what you must supply — *"تحتاج إلى: حساب
واتساب للأعمال"* — and still flags what is not ready (`يحتاج إعدادًا`, `تجريبي`). The redesign moved the
prerequisite **up** in the hierarchy rather than down: on a card it now sits on its own strip at the foot,
and in the channel list it is the second line of the row.

96 pages, two locales, the CMS, the canonical URLs, hreflang, breadcrumbs, structured data and the sitemap
are untouched. `spec/requests/marketing` and `spec/models/site_page_spec.rb` — 150 examples — pass.

---

## 6. What the audit found, and the five calls that were mine

Six reviewers went over the first milestone and every finding was handed to a separate agent told to refute
it. 59 survived — 14 blocking. They are fixed. Five needed a decision rather than a patch.

**The Arabic typeface was never loading.** `url('marketing/fonts/…')` copied `inter.scss`'s shape, but that
file's path resolves through a Vite ALIAS (`shared`, in `vite.shared.ts`). There is no `marketing` alias, so
the URL passed through untouched and 404'd. Every Arabic page was still on `Tahoma, Arial`. A screenshot
could not catch it — the page had changed size, weight and leading, so it looked different — and fetching the
asset could. Fixed to `./fonts/…`, verified in dev (200, 42,848 bytes, `font/woff2`) and in a production
build (four hashed `.woff2` in `assets/`, referenced by the built CSS).

**No h2 was added to /faq.** The audit read "one H1 then twelve `dt`s" as two defects. The missing RULE was
real and is fixed in `_section_head`, which now draws its line whether or not a section has a heading. The
missing H2 is not a defect: `h1` → `dl` skips no level, and the page has one section, so a heading for it
could only restate the H1 two lines below it.

**The duplicate strings were not just paraphrased.** Two proposed keys were byte-identical to existing FAQ
strings — four strings for two meanings, which drift. The link labels got their own copy instead. The home
help cards got bodies of their own rather than /support's lede repeated on the front page.

**The availability badge moved out of the `<h1>`.** Survivable at 30px, not at the new 48px display step,
where `items-center` hung a 12px chip in the middle of a headline. It is also not part of a page's NAME. It
is rendered through `capture` so the row is drawn only when the badge has something to say — the partial
stays the single place that decides which states those are.

**Arabic validation messages were showing English diagnostics.** `config/application.rb:40` enables only
`:pluralization` from rails-i18n, so its `ar` ActiveModel catalogue never loads and a failed quote submission
printed `Translation missing: ar.errors.messages.blank` on the primary market's most important conversion
page. Pre-existing — the error summary already did this — but per-field errors multiply it. Fixed under
`models.site_quote_request` in `marketing.ar.yml`, so no other model in the application changes:
`enabled_modules` is an infrastructure decision, not a marketing-site one, and `config/locales/ar.yml` is
Crowdin-managed.

### The marketing stylesheet: 1,539,855 → 42,034 bytes

It was generated from the config whose `content` globs reach every Vue file in the dashboard, so a site of
twenty ERB partials shipped the agent console's utilities and seven icon collections. It uses four icons.
`tailwind.marketing.config.js` imports the shared theme — the ramp, the type scale and the spacing ladder
must not fork — and narrows only `content` and the safelist, reached by `@config` from the marketing
stylesheet alone. **Proof nothing was dropped**: every class on all 98 pages was extracted from the rendered
HTML and looked up in the built stylesheet. 221 distinct classes, 0 without a rule.
