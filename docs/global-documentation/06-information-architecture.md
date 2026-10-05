# 06 — Information architecture

How the Lynomia Chat documentation is organised, and the reasoning behind each decision.

---

## 1. What the structure is derived from

Three inputs, in order of authority:

1. **The repository.** Every section exists because a product area exists. Nothing is documented that is not
   built (`05-lynomia-capability-doc-map.md`).
2. **The questions real users of a product like this ask**, read off the Chatwoot user guide's shape — 143 articles
   across 15 categories (`03-chatwoot-doc-map.md`). This is *topic coverage*, not content: it tells us people ask how
   to connect a channel, what a label is for, and why a WhatsApp message did not send.
3. **How an Arabic-first product explains these ideas**, from Karzoun (`04-karzoun-doc-map.md`).

**The structure deliberately does not mirror Chatwoot's.** Chatwoot's tree is organised around *where a feature lives
in its codebase* — "Features explained" and "Advanced features explained" are the two largest categories, and the
split between them is not something a user can predict. Lynomia's is organised around **what someone is trying to
do**.

## 2. The tree

| # | Section | What it answers | Who reads it |
|---|---|---|---|
| 1 | **Getting started** | "I have just been given a Lynomia Chat account." | a new admin, in their first hour |
| 2 | **Conversations** | "Someone has messaged us. Now what?" | every agent, every day |
| 3 | **Contacts** | "Who are these people, and how do I organise them?" | admins and agents |
| 4 | **Audiences and campaigns** | "How do I reach a group of them on purpose?" | marketing and owners |
| 5 | **WhatsApp** | "How do I run WhatsApp properly?" | the whole business — it is the main channel |
| 6 | **Automation and bots** | "How do I stop doing this by hand?" | admins |
| 7 | **Commerce** | "How do I see what a customer bought?" | agents on a store |
| 8 | **Workspace and team** | "Who can do what, and where do messages land?" | admins |
| 9 | **Integrations** | "How do I connect this to something else?" | admins and developers |
| 10 | **Administration** | "What happened, and who did it?" | owners |
| 11 | **Troubleshooting** | "Why isn't this working?" | anyone, at the worst moment |

### Why these eleven and not Chatwoot's fifteen

| Chatwoot category | Lynomia | Reason |
|---|---|---|
| Chatwoot 101 (9 lessons) | **Getting started** | the lesson sequence is the right idea; its content is Chatwoot's product |
| Setup account | Getting started + Workspace and team | first-run setup and ongoing administration are different readers |
| Other channels (15) | WhatsApp + Workspace and team | WhatsApp is not "another channel" in this product, it is the product's centre of gravity |
| Website live chat (14, mostly per-framework install recipes) | Workspace and team, one article | fourteen near-identical snippets is a reference, not a guide |
| Features explained / Advanced features explained (34) | spread across 2, 3, 6, 8, 10 | the split is not meaningful to a reader |
| Voice channels | — | see §4 |
| Captain (11) | — | see §4 |
| Reports (7) | — | see §4 |
| Migrations (4: Intercom, Front, Freshdesk, Zendesk) | — | competitor-switch marketing, not product documentation |
| How To (6: licences, coupons, free-trial limits) | — | Chatwoot's own commercial terms |
| Help Center (5) | Workspace and team, one article | tenants can run their own help centre; it is a feature, not a section |
| Best practices (5) | folded into the relevant guides | advice reads better next to the thing it is advice about |
| Other topics (14) | Troubleshooting | — |
| — | **Audiences and campaigns** | Lynomia-only. No Chatwoot equivalent exists |
| — | **Commerce** | Lynomia-only |

## 3. Within a section: the article contract

Every substantive article answers the P4 §5 questions in this order, skipping any that do not apply rather than
padding them:

**What is this → When to use it → When *not* to use it → What you need first → Steps → An example → Who can do it →
Limits → Related → If it does not work.**

Two of those are the ones that make documentation worth reading and are usually missing:

- **When not to use it.** Every confusion pair in §5 is really a "when not to use it" answer.
- **Limits.** Provider capability differences, Meta's approval rules, the 24-hour window, anything PRE_UAT. These are
  written where the UI hides them, which is the point.

## 4. What is deliberately not documented

| Area | Why |
|---|---|
| **Captain / AI** | P4 §43 forbids starting AI work, and documentation of a feature is part of the feature |
| **Voice channels** | present in the codebase but outside the phases that built this product's story; documenting it would set an expectation the product has not earned |
| **Reports** | the screens exist; what each number means deserves its own pass with the people who read them |
| **Per-framework widget install recipes** | fourteen snippets that differ by three lines; one article covers installing the widget |
| **Migrations from competitors** | not product documentation |
| **Chatwoot's commercial terms** | licences, coupons, free-trial limits, AI credits — none of them are Lynomia's |

Each is recorded here rather than silently dropped, so the gap is a decision and not an oversight.

## 5. The articles that exist because people get these wrong

P4 §6 names the distinctions to prioritise. Each is a real article, not a paragraph inside another one, because each
is the thing someone searches for at the moment they are stuck:

| Article | The confusion |
|---|---|
| Labels or shared audiences? | a label is a tag you put on; an audience is a question the system keeps answering |
| Automation or flow builder? | one reacts to an event with actions; the other is a conversation that waits for replies |
| Macros or automation? | one is run by a person on a conversation; the other runs itself |
| Agent bots or flows? | one is code you host; the other is built in the canvas |
| Campaigns or automation? | one goes out to a list you chose; the other reacts to what someone did |
| WhatsApp templates or normal messages? | the 24-hour window decides which one you are allowed to send |
| A draft or an approved template? | a draft exists only in Lynomia; only WhatsApp can approve it |
| A contact filter or a shared audience? | one is a view you are looking at; the other is a saved, reusable audience |
| Customer 360 or a contact? | one is the person; the other is what the store knows about them |
| Visible spend or lifetime value | what Lynomia can actually see, and why it is not the same number |

## 6. Languages

Every article exists in **English and Arabic**. They are separate `Article` rows sharing a slug within their locale,
linked as translations, exactly as the Help Center already models translations — not a runtime translation layer.

**The template language is not the dashboard language**, and neither is the documentation language: all three are
independent, and the WhatsApp articles say so explicitly, because conflating them is a common and expensive mistake.

Arabic is authored, not machine-translated and left (P4 §11). Where a term has an established Arabic form in this
market, that form is used (`04-karzoun-doc-map.md`); where a term is a product or brand name, an OAuth scope, an API
value or anything else machine-readable, it stays as it is — the same rule the rest of this repository follows.

## 7. Ordering

Within each section, articles are ordered by `position`, set in the content manifest rather than by creation order,
so the reading sequence is a decision in source control. The documentation portal uses `article_order: position`;
only the changelog uses `release_date` (`08-changelog-design.md`).
