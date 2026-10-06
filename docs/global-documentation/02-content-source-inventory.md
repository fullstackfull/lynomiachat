# 02 — Content sources, and what may be taken from each

Three sources, one rule, and the evidence behind it.

---

## 1. The rule

| Source | Status | What is taken | What is never taken |
|---|---|---|---|
| **This repository** | the source of truth | every factual claim | — |
| **Chatwoot user guide** | © all rights reserved, no reuse grant | topic coverage, article shape, the questions users ask | any sentence, any phrase |
| **Karzoun help centre** | © all rights reserved, no reuse grant | which questions an Arabic audience asks, in what order; which Arabic words this market uses | any sentence, any phrase, any branding |

The brief's instruction is conditional: reuse substantial third-party text only after **verifying its reuse terms**,
and otherwise adapt or rewrite. Both sources were checked. Neither grants reuse. So the condition is not met for
either, and **no third-party prose appears in the Lynomia corpus** — not a paragraph, not a sentence, not a
step list.

What *is* taken from both is knowledge about **readers**: that the most-read page on an Arabic Chatwoot-based
product is "what is an official WhatsApp Business account", that fourteen articles on installing a widget means the
shape is wrong, that people confuse labels with segments. Those are facts about users, not expression.

## 2. The evidence

### Chatwoot

The help centre pages themselves carry no licence, no copyright line and no terms link; the parent site carries:

> "© 2026 Chatwoot Inc. All rights reserved"

No Creative Commons notice, no documentation licence, nothing granting reuse. Full inventory and per-article
classification: `03-chatwoot-doc-map.md` — **143 articles across 15 categories**.

### Karzoun

> "جميع الحقوق محفوظة ©2023" — site-wide footer

plus an intellectual-property clause in its terms of service reserving ownership of the site and its content. Full
inventory: `04-karzoun-doc-map.md` — about **29 articles in five sections**, reconstructed from archive snapshots
because the live paths sit behind a bot challenge, and cross-checked against a live 2026 page.

### This repository

`05-lynomia-capability-doc-map.md` — **50 user-facing areas**, each read from the code rather than from the phase
documentation, with the five places where the existing documentation is now out of date, and a list of things the
product does **not** do that must never be claimed.

## 3. Why the third source outranks the other two

The two external sources describe *a* product. This repository describes *this* product, and the differences are not
cosmetic:

- Shared audiences, the flow builder, commerce and the WhatsApp template manager have **no upstream equivalent at
  all** — nothing to adapt from, everything written from the code.
- Several things upstream documents behave **differently** here. Following upstream's template documentation, for
  instance, would tell a Lynomia user that templates can only be synced, when this product authors and submits them.
- Several things upstream documents **do not exist** here, and several things a reader would reasonably assume do not
  exist either — a Salla order cannot be acted on, a WooCommerce order has no shipped status, a flow runs on WhatsApp
  Cloud only. Those are in `05 §3`, and they are the sentences that save a reader an afternoon.

## 4. What this means for anyone maintaining the corpus later

- **Write from the code.** If you cannot find it in `app/`, `enterprise/` or `custom/`, do not write it.
- **Re-read `05 §3` before publishing.** It is the list of claims that are false in this product however true they
  are elsewhere.
- **Do not paste from the two external sources.** Their position has not changed, and a line copied in is a line that
  has to come out later.
