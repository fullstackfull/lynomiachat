# 03 — Competitive analysis

**Date:** 2026-10-14 · Five sites analysed read-only (`GET` only): `karzoun.chat`, `respond.io`, `wati.io`,
`sleekflow.io`, `chatwoot.com`.

## The boundary, stated before anything else

**Only information architecture transfers.** Which pages exist, how they group, how deep the coverage goes, and
what a reader of a given page type expects. **No design, layout, colour, typography, illustration, icon,
screenshot, logo, brand name, slogan, headline, sentence, testimonial, customer name, statistic or claim from any
competitor may be copied, adapted or closely paraphrased.** Every word and image on a Lynomia page must come
from Lynomia's own verified features (`02-verified-feature-inventory.md`) and must be independently
substantiable.

Where a page count below is given it was counted from the site's own published sitemap; where a structure is
described it was read from the fetched document. Search-volume figures are **not** given anywhere in this
document, because no keyword-volume data source was available — the priority ranking in §5 is reasoning from
observed competitor investment, not measurement.

---

## 1. karzoun.chat — the closest competitor, and the clearest opening

Karzoun is **also a Chatwoot derivative**: its feature vocabulary maps one-to-one onto Chatwoot's (shared inbox,
labels, canned responses, macros, auto-assignment, teams, private notes, business hours, command bar, keyboard
shortcuts, CSAT, agent/team/label/inbox reports). Lynomia and Karzoun are selling adjacent forks of the same
engine into the same market, which makes Karzoun's IA the single most relevant benchmark.

**What it does well:** Arabic-first and genuinely native — `<html dir="rtl" lang="ar">` on every page, Arabic
slugs, Arabic support sold as a feature; one page per feature including per-report-type pages; a help centre on
the marketing domain with deep inline linking from page bodies; WhatsApp-first conversion (a `wa.me` header CTA
and a WhatsApp sales number); a verifiable Meta partner listing; a local legal entity and Gulf phone numbers.

**Every weakness is an opening:**

| Weakness | Measured |
|---|---|
| **No English site at all** | zero `hreflang` elements; zero `/en/` or `lang=en` URLs in any of its three sub-sitemaps; `GET /en/` and `/en` → 404 |
| Very small crawlable surface | ~120 URLs total |
| Feature pages are thin | ~120 words, no how-it-works steps, no FAQ, no screenshots, no related links |
| Navigation promises it does not keep | nine mega-menu tiles dead-ending at a generic docs hub, and **five service items with `href="#"`** — including Meta business verification, an intent it advertises and does not answer |
| **No pricing page at all** | not even the URL |
| Missing families | no blog, no per-channel pages, no industry pages, no comparison pages, no changelog, no customer stories, no free tools, no security page |
| Technical debt visible to a buyer | five `<h1>`s on the homepage; 19 duplicate docs copies competing with the canonical `/docs/` articles; two parallel checkout systems, one of them a raw Stripe link on a third domain; live **Turkish** orphan pages (`/anasayfa/`, `/kvkk/`) and a Turkish App Store link; `©2023`; typos in an `<h1>` and a pricing bullet |

---

## 2. The three international sites — what depth looks like

**respond.io — the best navigation model.** Its product menu is organised by buyer journey — *Capture Leads* →
*Convert Leads* → *Retain Customers* — rather than by module name, and the homepage repeats the same spine. It
publishes a sitemap index, 45 integration pages, 21 two-level industry pages, five alternatives pages, and a
help centre of **~313 articles across 12 locales** (including Arabic) — the largest content investment measured
anywhere in the set. Its feature pages lack an FAQ and lack deep links into specific help articles.

**wati.io — the widest programmatic surface.** WhatsApp-first. Its largest family is **111**
`/whatsapp-template/*` pages (template examples), plus 20 integration pages, 11 comparison pages — including a
`wati-vs-chatwoot` page — a pricing page plus two separate comparison pages, a glossary with its own sitemap,
and a `trust.wati.io` subdomain. Notable defect worth not repeating: its Arabic handling is a translation on an
LTR document with no `hreflang`.

**sleekflow.io — the combination-matrix model.** 146 canonical paths dominated by programmatic combinations (68
`/channels-integrations/*` including pair pages), the most elaborate locale handling of the five (including
`/ar-ae/pricing`, the only Arabic pricing page found anywhere), a trust centre, and versioned archived legal
terms. Its `/solutions/*` namespace collapses industries, teams, jobs and product topics together — **the
anti-pattern to avoid**.

**chatwoot.com — the most relevant feature taxonomy.** **53 feature pages** in nine groups, **34 comparison
pages**, 20 industry pages, use-case pages kept separate from solutions pages, a changelog, a security page, a
transparent pricing model with quotas as the differentiator and a second URL for self-hosted plans. Since
Lynomia's feature list is substantially the same one Chatwoot sustains 53 pages with, this is the proof that the
page family is viable — but **membership must come from Lynomia's verified inventory**: Lynomia has Campaigns,
Audiences, WhatsApp template management, Flow Builder, Commerce, Support Desk and Operations surfaces Chatwoot
does not, and Chatwoot has Captain, voice and TikTok pages **Lynomia must not imply**.

**Lynomia's feature-page count today: zero.**

---

## 3. Patterns worth adopting

1. **A per-feature page family, grouped.** The highest-value item: each page is an independent entry point.
   Group headings in Lynomia's own wording; membership from `02-verified-feature-inventory.md` §8.
2. **A feature-page template better than all five.** Promise → capability map with in-page anchors → three
   numbered how-it-works steps *each with a real screenshot of Lynomia's own UI* → use-case cards linking to
   sibling features → benefit recap → **FAQ** (none of the five puts one on a feature page) → **related
   features** → **a deep link to the specific `/docs/:article_slug`** (respond.io and SleekFlow have neither).
3. **Four taxonomies kept apart:** `/features` (capability), `/use-cases` (job), `/solutions` (buyer), and
   industries — with a small set of pillar pages above them. Do not collapse them into one namespace.
4. **Journey-based grouping in the product menu**, after respond.io's structure: capture → convert → retain.
5. **Per-channel pages**, one per channel Lynomia can truthfully claim — nine, with TikTok named as beta — each
   stating its condition where one exists. Karzoun has none; this is a direct advantage.
6. **An integrations directory with one page per provider.** Lynomia's honest scope is four commerce providers,
   three of them off by default with order actions PRE-UAT-locked. Compete on **depth per provider** — the real
   setup path and the real limits — not on catalogue size.
7. **Comparison pages as permanent IA**, factual, sourced and dated. 53 exist across four competitors, and
   **nobody has Arabic comparison pages against the Arabic incumbent.**
8. **A pricing page with the unit named.** All five publish something; Karzoun publishes tier *structure* with
   no figures, which is the available fallback. **Hard gate:** `02-verified-feature-inventory.md` §4 — no plan,
   price or tier exists in the repository, so v1 is a quote-request page with published comparison dimensions.
9. **Free tools as acquisition pages** (WhatsApp pricing calculator, `wa.me` link generator, QR generator, chat
   button generator). All four non-Karzoun sites have them; the entire Arabic surface has none.
10. **Trust artefacts as linkable pages** — security page, status page, fair-use policy behind any "unlimited",
    sub-processor list, DPA, archived legal versions, public changelog. **Built strictly from
    `02-verified-feature-inventory.md` §6.1**, never from what competitors assert: Chatwoot links "SOC 2 Type
    II" to its security page, and Lynomia holds no certification.
11. **Help content deep-linked from page bodies**, which Karzoun does well and the others do weakly. Lynomia's
    `/docs` and `/docs/:article_slug` routes already exist and are live with 75 articles.

---

## 4. The Arabic opportunity is the strategic finding

Reading the Arabic column across all twenty intent clusters analysed: **the Arabic surface for this category is
thin and uneven.** Karzoun, the only Arabic-native site, has no pricing page, no blog, no industry pages, no
comparison pages, no per-channel pages, no free tools, no customer stories and no security page; 30 help
articles; feature pages of ~120 words; and an advertised service behind a dead anchor. The three international
sites have Arabic *translations* of an English-first IA — one of them on an LTR document with no `hreflang`.

**So the opportunity is not "translate the English site".** It is to be the first site in this category whose
Arabic tree is complete, correct and not an afterthought: every launch and parity page existing in Arabic at
true parity, `dir="rtl"` at the document level, reciprocal `hreflang`, Arabic technical terminology decided
deliberately, and Gulf conversion devices native to the Arabic tree rather than bolted on.

Lynomia starts with two structural advantages for this: the documentation corpus is already bilingual by
construction (`custom/app/services/documentation/library.rb:14`), and the application already has working
`lang`/`dir` helpers and RTL Tailwind variants. The website is the only part of the system that is not properly
bilingual today (`01-current-state-audit.md` §8).

Unserved Arabic intents worth naming, each observed as a gap rather than a volume estimate: WhatsApp pricing
calculation; "multiple agents on one WhatsApp number"; comparison/alternative pages; industry pages; free
utilities; a technical glossary; a trust/security page; and **Meta business verification** — which Karzoun
advertises in its own navigation and does not answer.

---

## 5. Candidate page list

Priority bands: **P0** cannot launch without · **P1** competitive parity · **P2** depth and long tail.
Every page is **EN + AR**. The IA and URL map are fixed in `04-information-architecture.md`; the verification
reference for each page's content is `02-verified-feature-inventory.md`.

**P0 — launch set (~20 pages × 2 languages):** home; `/pricing` (quote-request, per §4 of doc 02);
`/features` index; unified inbox; WhatsApp pillar; `/channels` index with honest per-channel states; campaigns;
audiences; WhatsApp templates; automation; flow builder (conditional); analytics; AI assistance (conditional,
written from doc 02 §3); security & trust (written from doc 02 §6.1); FAQ; request-a-demo; contact (with a Gulf
WhatsApp path); documentation hub (**route exists**); changelog (**route exists**); and the legal set — privacy,
terms, data deletion, plus fair use if "unlimited" is ever used.

**P1 — parity set (~30 pages × 2):** the nine channel pages; the conversation-management family (labels,
private notes, teams, assignments, priority, read receipts, filters); the productivity family (canned responses,
macros, bulk actions, keyboard shortcuts, command bar); routing and business hours; contacts, custom attributes,
multi-channel identity and Customer 360; CSAT; API & webhooks; the support desk; `/integrations` plus four
provider pages; and the first comparison pages.

**P2 — depth:** industry pages; use-case pages; free tools; glossary; customer stories once real ones exist.

**Explicitly excluded from every band**, because the product cannot support them: AI agents/copilot,
conversation SLA, Twitter/X, voice, 360dialog, analytics export, revenue reporting, campaign suppression lists,
and commerce order actions.

---

## 6. What was not established

- **No keyword-volume data** was available. Nothing in this document is a traffic or ranking forecast.
- Page counts come from each site's published sitemaps at the time of fetch; a site may hold unlisted pages.
- Two sites returned 403 to some user agents, so a small number of pages were analysed from their sitemaps and
  raw responses rather than from rendered documents; those are the only places where structure is inferred from
  URL patterns rather than read from a page.
- No competitor's pricing figures are recorded here, deliberately: they change, and Lynomia's pricing decision
  is gated on its own plan data existing at all.
