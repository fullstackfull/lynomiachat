# 05 — Design and content specification

**Date:** 2026-10-14 · Binding on W2–W5. Companion to `04-information-architecture.md`.

## 1. Identity: keep it, systematise it

The existing page already has a coherent identity, defined as CSS custom properties. It is **kept** and moved
into Tailwind tokens rather than redesigned — the brief is a durable site, not a new brand.

| Token | Value | Use |
|---|---|---|
| `--primary` | `#2f6fe4` | primary actions, links |
| `--primary-deep` / `--primary-navy` | `#194689` / `#122b5d` | gradients, dark sections |
| `--chat` | `#DB2777` | the accent that carries the "Chat" half of the brand; used sparingly |
| `--wa` | `#25d366` | WhatsApp only, never as a generic success colour |
| `--ink` / `--ink-soft` / `--ink-faint` | `#0f1b30` / `#3d4961` / `#6c7891` | text hierarchy |
| `--paper` / `--card` / `--line` | `#f8fafd` / `#fff` / `#e3e8f1` | surfaces |
| radii | `22px` / `14px` / `9px` | cards / controls / chips |

**Type:** IBM Plex Sans Arabic + IBM Plex Sans + IBM Plex Mono, already in use. They must be **self-hosted**
rather than loaded from Google Fonts: the current page's only render-blocking request is that stylesheet, and a
third-party font host on an Arabic-market site is both a performance and a privacy cost. Weights 300–700.

**Accent discipline:** one accent per section maximum. The current page's strength is restraint; the rebuild
keeps it.

## 2. Page templates

Five templates cover the whole site. Each is a sequence of named sections, which is what makes them
CMS-editable (`SitePage#sections`, D10).

### T1 — Home
Hero (headline, sub, two CTAs, product visual) → channel strip → problem/solution → three-step how it works →
feature groups with links → WhatsApp block → AI-assist block (with its prerequisite stated) → campaigns and
audiences → teams and productivity → analytics → commerce and integrations → solutions by business type →
security → documentation and support → FAQ → closing CTA.

### T2 — Feature page (the template none of the five competitors fully implements)
H1 + one-sentence promise → the business problem → how Lynomia solves it → capability list with in-page anchors
→ **three numbered how-it-works steps, each with a real screenshot** → prerequisites and limits, stated plainly
where the feature is CONDITIONAL or BETA → use-case cards → **related features** → **deep link to the specific
documentation article** → **FAQ block** → CTA → breadcrumbs.

### T3 — Channel page
Same as T2 plus: what the channel can carry (message types, media, templates), what the customer must supply
(credentials, provider account), setup outline linking to the documentation, and the channel's availability
state. A channel that is CONDITIONAL says so above the fold, not in a footnote.

### T4 — Solution page
Who it is for → the three jobs they need done → how the product does each, linking to the feature pages →
a realistic scenario → documentation links → CTA. **No invented customer names or numbers.**

### T5 — Utility page
`/contact`, `/demo`, `/pricing` (quote request), `/faq`, `/support`, legal. Short, single-purpose, one action.

## 3. Content rules

1. **Every claim traces to `02-verified-feature-inventory.md`.** A sentence that cannot be traced does not ship.
2. **State the condition where one exists.** "Flow Builder (available on request — requires a WhatsApp Cloud
   inbox)" is honest; omitting the condition is not.
3. **No numbers without a source.** No uptime, no performance percentages, no customer counts, no "X% faster".
   Counts of things that exist and can be checked (nine channels, five AI assist actions, 50+ interface
   languages) are fine.
4. **AI wording is fixed:** "assist for your agents", never "AI agent", "chatbot", "resolves on its own" or
   "24/7 AI". Always with the prerequisite: your own OpenAI key, enabled per account.
5. **Arabic is written, not translated.** Gulf business Arabic, no machine-translation artefacts; English is a
   sibling original. Both get the same review.
6. **Every page answers one search intent** and says so in its H1. No page exists only to hold keywords.
7. **Screenshots are real UI** with customer data removed; illustrations are visibly illustrations.

## 4. Accessibility and RTL — the gaps the current page has

Non-negotiable, because the audit found all of these missing (`01-current-state-audit.md` §7):

- Landmarks: `<header>`, `<nav>`, `<main>`, `<footer>`, plus a skip link.
- One `<h1>` per page and a heading order that does not skip levels.
- Visible focus on every interactive element (`:focus-visible`, 3px outline — already in the identity).
- Any dialog is a real dialog: `role="dialog"`, `aria-modal`, focus trap, Escape to close.
- All interactive controls reachable and operable by keyboard; the mobile menu included.
- `prefers-reduced-motion` honoured (already is).
- Contrast ≥ 4.5:1 for body text, ≥ 3:1 for large text — checked, not assumed.
- `alt` on every meaningful image; decorative SVG gets `aria-hidden="true"`.
- **RTL through logical properties** (`ms`/`me`/`start`/`end`), never `left`/`right`, so one stylesheet serves
  both directions. Directional glyphs mirror; logos and screenshots do not.

## 5. Performance budget

Measured against the current page: 100 KB of HTML with all CSS inline, uncacheable, plus two cross-origin
images and a render-blocking font stylesheet.

| Budget | Target |
|---|---|
| HTML per page | ≤ 40 KB |
| CSS | one cacheable bundle, ≤ 60 KB compressed, shared across pages |
| JS | ≤ 30 KB compressed; the marketing entrypoint must **never** load the dashboard bundle |
| Images | AVIF/WebP with explicit `width`/`height`; `loading="lazy"` below the fold |
| Fonts | self-hosted, `font-display: swap`, subset to Arabic + Latin |
| Requests before first render | ≤ 3 |

The dashboard build already emits a 15.9 MB `DashboardIcon` chunk; a separate entrypoint is what keeps that
away from a marketing page.

## 6. What the operator edits vs what is code

| Operator edits (Super Admin) | Code |
|---|---|
| Section copy, headings, CTA labels and targets | page templates and layout |
| Images and alt text | design tokens and components |
| Navigation and footer links | routing, host scoping, locale resolution |
| FAQ entries | structured-data emitters |
| SEO fields, canonical override, index/noindex | sitemap generation, hreflang pairing |
| Publication state, preview | redirect handling |

Rule: an operator can change **what a page says**, never **what a page is allowed to claim** — the content
rules in §3 are enforced in review, and the inventory is the reference.
