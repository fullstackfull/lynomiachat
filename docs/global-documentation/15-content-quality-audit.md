# 15 — The content quality audit

Every article in the corpus was re-read against two things before this phase closed: the brief's twelve-section
article contract (Part 5), and the "what must never be claimed" list in
[05-lynomia-capability-doc-map.md](05-lynomia-capability-doc-map.md) §3. This document records what the audit
measured, what it found, what was fixed, and — the part that matters most — where a contract section is
deliberately absent and why.

The audit is reproducible. The script that produced the figures below is in the scratchpad as
`p4-contract-final.txt`; it maps each of the brief's twelve sections onto the heading wording this corpus actually
uses, because the corpus is written in product voice rather than in the brief's shouting capitals.

---

## 1. The corpus, as measured

| | |
|---|---|
| English articles | 43 |
| Arabic articles | 43 |
| Locale parity | 43 keys present in both; none English-only, none Arabic-only |
| Articles with a title and a description | 43 of 43 |
| Articles under 1,200 characters of body | 0 |
| Occurrences of the upstream product name in article content | 0 |
| External links in the corpus | 0 |
| Changelog notes | 1, with no invented version number |

---

## 2. The twelve-section contract

The brief's contract is a list of questions an article should answer, not a list of headings it must carry. The
audit therefore matched **meaning**, mapping each contract section to the headings this corpus uses for it:

| Contract section | What this corpus calls it |
|---|---|
| WHAT IS THIS | the un-headed opening, or `## What a … is`, `## Why WhatsApp has it` |
| WHEN SHOULD I USE IT | `## When to use it`, `## When to use one`, `## Which to use, by case` |
| WHEN SHOULD I NOT USE IT | `## When not to use it`, `## …, and when to do something else` |
| HOW DO I SET IT UP | `## What you need first` |
| STEP-BY-STEP | `## Steps`, `## Creating one`, `## Publishing and editing` |
| EXAMPLE | `## A worked example`, `## Side by side` |
| PERMISSIONS REQUIRED | `## Who can do this`, `## Who can do what`, `## Who can read it` |
| PROVIDER REQUIREMENTS | `## What you need first`, `## Which platforms you can connect at all` |
| KNOWN LIMITATIONS | `## Limits` |
| RELATED FEATURES | `## Related`, `## Next` |
| TROUBLESHOOTING | `## If it does not work` |
| LEARN MORE | `## Related`, `## Next` |

Measured that way:

| Section | Articles carrying it |
|---|---|
| RELATED FEATURES | 43 / 43 |
| LEARN MORE | 43 / 43 |
| WHAT IS THIS | 42 / 43 |
| KNOWN LIMITATIONS | 39 / 43 |
| TROUBLESHOOTING | 39 / 43 |
| PERMISSIONS REQUIRED | 35 / 43 |
| EXAMPLE | 34 / 43 |
| PROVIDER REQUIREMENTS | 26 / 43 |
| STEP-BY-STEP | 26 / 43 |
| HOW DO I SET IT UP | 25 / 43 |
| WHEN SHOULD I USE IT | 15 / 43 |
| WHEN SHOULD I NOT USE IT | 15 / 43 |

### What was fixed

Two articles were genuinely missing a decision section a reader needs, and both were written:

- **[bulk-actions]** gained *When to bulk-act, and when to do something else* — the three-way confusion between a
  bulk action, an import and a shared audience, with the rule stated plainly: a bulk action is for a set that is a
  list, a shared audience is for a set that is a question.
- **[custom-attributes]** gained *When to use one*. It already carried *When not to use one*; half a decision is
  worse than none, because the reader is told what to avoid and not what to do.

Both were written in English and in Arabic.

### Where a section is deliberately absent

`WHEN SHOULD I USE IT` and `WHEN SHOULD I NOT USE IT` sit at 15 of 43, and that is the honest figure rather than a
backlog. The 28 articles without them fall into four groups, none of which has a choice to make:

| Group | Articles | Why there is no "when to use it" |
|---|---|---|
| **The article *is* the decision** | `automation-or-flow-builder`, `macros-or-automation`, `labels-or-shared-audiences` | the whole article answers when to use which; a section repeating it would be the article's own summary |
| **A rule, not a feature** | `the-whatsapp-24-hour-window`, `whatsapp-template-lifecycle`, `whatsapp-business-coexistence`, `roles-and-permissions`, `commerce-provider-support` | WhatsApp's window is not something you choose to use. The reader needs to know how it behaves, not when to adopt it |
| **A procedure with one way through it** | `connect-whatsapp`, `connect-salla`, `connect-shopify`, `connect-woocommerce`, `connect-zid`, `connect-your-first-channel`, `set-up-an-inbox`, `set-up-your-account`, `invite-your-team`, `whatsapp-templates`, `whatsapp-troubleshooting`, `troubleshooting` | the choice is *which platform*, and it is answered once in `commerce-provider-support` rather than five times |
| **A landing or orientation page** | `welcome-to-lynomia-chat`, `work-in-the-inbox`, `your-first-conversation`, `contacts`, `integrations`, `audit-logs`, `customer-360`, `assign-and-prioritise`, `canned-responses` | "when should I use contacts" is not a question anyone has. These articles explain what exists and how it behaves |

`PROVIDER REQUIREMENTS` sits at 26 of 43 for the same kind of reason: a label has no provider. It is present in
every channel and commerce article, which is where a provider exists to have requirements.

`HOW DO I SET IT UP` and `STEP-BY-STEP` are absent from the articles that describe something with nothing to set
up — a rule, a concept, or a decision between two features.

### The one decision taken on the contract itself

**`LEARN MORE` and `RELATED FEATURES` are served by one section.** The corpus contains **zero external links**, and
that is a policy rather than an oversight: every "read more" in this documentation points at another article in this
documentation, because that is the only destination whose accuracy this repository controls. Part 27's instruction
not to invent a support destination applies with equal force to a reading destination. Where a reader needs an
authority outside the product — WhatsApp's own messaging policy, a store platform's API terms — the article says so
in words and names the authority, without a link that will rot.

If an external-links policy is adopted later, `## Related` is the single section every article already has, and the
change is additive.

---

## 3. The confusion pairs (Part 6)

**All ten pairs are covered.** Three have a dedicated article; seven are answered by an explicit decision section
inside the article the pair belongs to.

| Pair | Where it is answered |
|---|---|
| LABEL vs SHARED AUDIENCE | dedicated article — `labels-or-shared-audiences` |
| AUTOMATION vs FLOW BUILDER | dedicated article — `automation-or-flow-builder` |
| MACRO vs AUTOMATION | dedicated article — `macros-or-automation` |
| AGENT BOT vs FLOW | `automation/agent-bots.md` § *Agent bot or flow?* — side-by-side table and a recommendation |
| CAMPAIGN vs AUTOMATION | `audiences-and-campaigns/whatsapp-campaigns.md` § *Campaigns or automation?* |
| COMMERCE CUSTOMER 360 vs CONTACT | `commerce/customer-360.md` § *Customer 360 or a contact?* |
| VISIBLE SPEND vs LIFETIME VALUE | `commerce/customer-360.md` § *Visible spend is not lifetime value* |
| CONTACT FILTER vs SHARED AUDIENCE | `audiences-and-campaigns/shared-audiences.md` § *Personal or shared* |
| WHATSAPP TEMPLATE vs NORMAL MESSAGE | `whatsapp/the-whatsapp-24-hour-window.md` § *What changes when it closes* — a row-by-row table of what sends and what does not |
| LOCAL DRAFT vs META APPROVED | `whatsapp/whatsapp-template-lifecycle.md` § *The states, and what you can change in each* |

### A correction worth recording

The audit's first pass reported **seven of these pairs as missing**. That was wrong, and the mistake is worth
keeping in the record because it is the kind that looks like a finding. The first pass searched for a *dedicated
article slug* per pair (`campaigns-or-automation.md` and so on) rather than for the decision itself. Searching the
corpus for decision headings instead found all seven, at the file and line above.

Had the first result been acted on, the corpus would have gained six redundant articles, each repeating a section
that already existed in the article a reader is actually in when the question occurs to them. Fragmenting the
information architecture to satisfy a grep would have made the documentation worse.

A pair belongs in a dedicated article when the two things it compares are **peers a reader chooses between before
doing anything** — label or audience, macro or automation rule. It belongs inside an article when one side is the
subject of that article and the other is its near neighbour — Customer 360 and the contact record, a template and a
plain message.

---

## 4. Accuracy against the capability map

Every article was re-read against §3 of the capability map, the list of things a reader could reasonably assume that
this product does not do. The check was both manual and mechanical: each never-claim line was turned into a search
over the corpus.

**Result: no overclaims.** Specifically verified absent from the corpus:

- No article promises abandoned-cart detection, a cart event, a cart condition or cart recovery.
- No article promises real-time or push-driven commerce automation; the commerce articles say what the webhook
  actually signals and that the payload is discarded.
- No article attributes to Salla an order write action, a `paid` payment status, a spend figure, or order lookup by
  order number. `commerce-provider-support` states each of these as a limit of that platform.
- No article attributes shipped or delivered statuses, tracking numbers or carts to WooCommerce.
- No article describes a business-hours or time-of-day condition, a priority escalation engine, a flow entered from
  a store event or a schedule, or a flow on any channel other than WhatsApp Cloud.
- No article describes article revision history, Help Center folders, portal members, a template quality dashboard,
  a WhatsApp catalogue or carousel component, a commerce report, or a third campaign type.
- No article tells a reader they can add chosen contacts to a shared audience. `bulk-actions` and
  `labels-or-shared-audiences` both state the opposite, and say to use a label, which is the available answer.
- No article describes a custom-role permission the product does not have; `roles-and-permissions` lists the seven
  that exist and says everything else is administrator-only.

Where a capability is real but partial, the article says which part. The clearest example is
`commerce-provider-support`, which is a matrix of what each of the four platforms *cannot* do — written that way
because the interesting information for a reader choosing a platform is the limit, not the feature list.

### One capability-map line was corrected

§3 carried a line asserting that no in-product documentation link and no contextual-help registry exist. That
described the state before this phase, and this phase built both. The line is now struck through in place, with what
replaced it named, and with the one part of it that still holds — the sidebar changelog card still fetches the
external hub feed — kept as a live statement. A never-claim list that has gone stale is worse than no list, because
the next writer trusts it.

---

## 5. Arabic quality

- **Nothing was machine-translated.** Each Arabic article was written against the same repository facts as its
  English counterpart, in the product's own Arabic vocabulary, and the two new decision sections in §2 were written
  in both languages in the same pass.
- **The product's own terms are used**, matching the dashboard's Arabic: جمهور مشترك for a shared audience, وسم for
  a label, قاعدة أتمتة for an automation rule, قالب for a template, مسوّدة for a draft.
- **Machine-readable identifiers are left in Latin script** — slugs, OAuth scopes, API field names, status values
  such as `paid` and `UTILITY`, and the product name in code contexts — per the project's translation rules.
- **Article links resolve within the locale.** An Arabic article's links point at Arabic articles; the resolver
  falls back to English only if a key has no Arabic article, which at present never happens.

---

## 6. What this audit does not cover

- **Reading-level and tone consistency across 86 files** was reviewed by reading, not measured. There is no
  readability score in this record because one would be a number without a baseline.
- **Screenshots.** The corpus has none. Adding them means owning their staleness, and no article currently depends
  on one to be followable.
- **Whether the articles answer the questions real users ask.** That needs users, and it is the first thing to
  revisit once the documentation has search logs of its own.
