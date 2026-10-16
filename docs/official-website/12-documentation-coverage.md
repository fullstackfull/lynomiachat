# What the documentation covers, and what it does not

This is the inventory. It is written so that the next person can tell, without reading 182 files, which
part of the product has an article, which has a picture, and which has neither.

Counts are of the corpus in this repository (`custom/db/documentation/<locale>/<section>/<slug>.md`), which
is what `bundle exec rails documentation:content` publishes.

## The corpus

**91 articles in English, 91 in Arabic — 182 in all.** Every English article has an Arabic sibling; the
seeder reports any that does not.

| Section | Articles | Added by this release |
| --- | --- | --- |
| Getting started | 5 | — |
| Conversations | 6 | — |
| Channels | 8 | **8** |
| Contacts | 4 | — |
| Audiences and campaigns | 5 | — |
| WhatsApp | 6 | — |
| WhatsApp errors | 14 | — |
| Automation and bots | 5 | — |
| Analytics and reports | 9 | **9** |
| Commerce | 7 | — |
| Support cases | 2 | **2** |
| Workspace and team | 7 | **3** |
| Integrations | 4 | — |
| Administration | 2 | — |
| Troubleshooting | 7 | — |

The 22 new articles per locale are the three areas that had no documentation at all — every channel but
WhatsApp, the whole of Analytics and Reports, and the support desk — plus assignment policies, saved views
and search, and profile security.

## The figures

Thirteen figures, in both locales — **twenty-six published images**, from thirteen genuine captures per
locale. Each one is registered in `docs/screenshots/library.json` with the screen it is of, the environment
it was captured in, the command that produced it and the article that uses it.

| Figure | What it shows | Article |
| --- | --- | --- |
| `channels/inbox-new-*` | the channel picker, with the channels this installation has not configured greyed out | Connect your first channel |
| `channels/website-script-*` | the install snippet, with the website token covered | Website live chat |
| `channels/website-bubble-*` | the chat bubble on a demo shop | Website live chat |
| `channels/website-widget-open-*` | the widget open, with availability and Start Conversation | Website live chat |
| `channels/website-arrival-*` | that message, in the agent's inbox | Website live chat |
| `channels/website-prechat-*` | the pre-chat form settings | Website live chat |
| `channels/website-configuration-*` | Allowed Domains and the masked secret key | Website live chat |
| `analytics/analytics-overview-*` | the Analytics overview counters and the range controls | Analytics overview |
| `analytics/reports-overview-*` | the Reports live counters and the traffic heatmap | Reports |
| `analytics/analytics-tickets-*` | the support case analytics counters | Support case analytics |
| `support/support-cases-*` | the support case list with its SLA states | Support cases |
| `conversations/inbox-filters-*` | the conversation list's filters (shipped earlier) | Work in the inbox |
| `conversations/assign-agent-*` | the assignment panel (shipped earlier) | Assign and prioritise |

**The website-chat pair is the one to look at.** The visitor's half and the agent's half are two captures of
the same real message: the widget capture sends it from a demo shop, and the dashboard capture opens the
conversation it created, addressed by that conversation's own id. Neither half is a mock-up.

## What has an article but no figure

Most of the corpus. An article without a figure is not a defect — a page of plain instructions is often the
right thing, and a screenshot of a form with three fields in it teaches nothing. The articles where a figure
would earn its place, and does not yet exist, are:

- **Connect WhatsApp** — the provider choice screen and the QR step.
- **Flow builder** — a flow on the canvas.
- **WhatsApp templates** — the template manager and the builder.
- **Commerce** — a connected store and the order panel inside a conversation.
- **Customer 360** — the contact panel with identities and order history.

All five are capturable with the pipeline as it stands: add a page to the `docs` set in
`tools/visual/capture.mjs`, a spec under `docs/screenshots/specs/`, and an entry in `library.json`.

## What has neither an article nor a figure

Stated plainly, with the reason:

| Capability | Why not |
| --- | --- |
| **Billing and usage** (`Settings → Billing`) | what a reader sees depends on the plan their installation sold them; an article written against one plan shape would be wrong for the others. Needs the operator's own commercial model to be written against. |
| **Custom roles** | a Lynomia module that is off for most accounts, and whose capability list changes with the plan. |
| **Operations Control Center** | an operator surface, not a customer one. It belongs in the operator runbooks under `docs/`, not in the customer help centre. |
| **Captain / AI assist settings** | availability is installation-level and the feature set is still moving. Writing it now would date within a release. |
| **Voice and WhatsApp calling** | marked beta in the product and gated per account. Documenting a beta as though it were shipped is the kind of claim this project exists to avoid. |
| **Agent capacity policies** | the premium half of assignment. Named in [Assignment policies](../../custom/db/documentation/en/workspace/assignment-policies.md) as a premium feature rather than documented as though every reader has it. |

## How to add to this

1. **Write the article in both locales.** `custom/db/documentation/{en,ar}/<section>/<slug>.md`, with
   `title`, `description`, `position` and `seo_description` in the front matter. The Arabic slug is derived
   by the seeder (`<slug>-ar`); do not set it.
2. **If it needs a figure**, add the screen to the `docs` set in `tools/visual/capture.mjs`, capture it,
   write a spec, register it in `library.json`, and run `node tools/visual/build-annotations.mjs`.
3. **Reference it** as `![alt](media:<section>/<name>-<locale>.png)`. Alt text is required — it is the
   public search snippet as well as the accessible name, and the seeder refuses an empty one.
4. **Publish**: `bundle exec rails documentation:content`. A file on disk is not an article.

## Verifying it published

```
bundle exec rails documentation:content          # preflight refuses the whole run on any defect
curl -sI https://chat.lynomia.com/docs/website-live-chat      | head -1
curl -sI https://chat.lynomia.com/docs/website-live-chat-ar   | head -1
```

A committed Markdown file is not a published article, and a committed PNG is not a published figure. The
URLs above are the proof.
