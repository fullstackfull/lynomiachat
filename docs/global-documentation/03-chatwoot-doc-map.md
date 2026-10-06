# 03 — The Chatwoot documentation map

A complete inventory of the Chatwoot user guide, and what Lynomia Chat does with each article's **topic**.

Source: <https://www.chatwoot.com/hc/user-guide/en>, walked in full. **143 articles across 15 categories**, verified
two ways — by walking every category page, and by extracting every article link from the index — which agree exactly.
No category paginates. (The per-category counts printed on the index page are unreliable and disagree with the
category pages themselves; the category pages are authoritative.)

---

## 1. The copyright position, which decides everything below

The help centre pages themselves carry **no** licence, no copyright line and no terms link. The parent site does:

> "© 2026 Chatwoot Inc. All rights reserved"

There is **no grant of reuse** — no Creative Commons notice, no documentation licence, nothing. The repository's own
rule therefore applies at its strictest reading:

> Do NOT blindly copy third-party prose verbatim. Before reusing substantial text: verify its reuse/license terms.
> If reuse rights are not clearly established: ADAPT / REWRITE.

Reuse rights are **not** established. So **no sentence of Chatwoot's documentation is reused anywhere in the Lynomia
corpus.** What is taken is *topic coverage* — the knowledge of which questions users of a product like this ask —
which is a fact about users, not a copyrightable expression. Every Lynomia article is written from Lynomia's own
behaviour, verified against this repository.

## 2. What the inventory is used for

Three things, and nothing else:

1. **Coverage.** A question that 143 articles answer is a question Lynomia's users will also ask. The map shows which
   of those questions the Lynomia corpus answers, and which it deliberately does not.
2. **Shape.** Where upstream needs fourteen articles to install one widget, that tells us the shape is wrong for a
   reader, not that we need fourteen.
3. **Difference.** The rows marked LYNOMIA HAS DIFFERENT BEHAVIOR are the ones where following upstream's
   documentation would make a Lynomia user do the wrong thing. Those are the most important rows in the table.

## 3. Totals

| Action | Count | Meaning |
|---|---|---|
| **ADAPT** | 24 | the topic is right; the content is rewritten from Lynomia behaviour |
| **MERGE** | 65 | folded into a broader Lynomia article, because several upstream articles answer one question |
| **SPLIT** | 1 | one upstream article covers two things that are different in Lynomia |
| **LYNOMIA HAS DIFFERENT BEHAVIOR** | 9 | following upstream here would mislead a Lynomia user |
| **NOT RELEVANT** | 44 | the feature, the market or the commercial terms are not this product's |
| | **143** | |

**KEEP TOPIC** and **REPLACE** are not used: nothing is kept as-is (the copyright position forbids it), and
nothing is a straight replacement, because every Lynomia article is written rather than swapped in.

## 4. The nine rows where Lynomia behaves differently

These are worth reading on their own, because each is a place where upstream documentation is actively wrong for this
product:

| Upstream article | What Lynomia does instead |
|---|---|
| How to setup a WhatsApp channel? | `whatsapp/connect-whatsapp` — one Lynomia article covers connection; Lynomia also has coexistence, which upstream does not document |
| How to setup a WhatsApp channel (Embedded signup) | `whatsapp/connect-whatsapp` — one Lynomia article covers connection; Lynomia also has coexistence, which upstream does not document |
| How to setup a WhatsApp channel (Manual flow)? | `whatsapp/connect-whatsapp` — one Lynomia article covers connection; Lynomia also has coexistence, which upstream does not document |
| Synchronize WhatsApp templates using a Business Management token | `whatsapp/whatsapp-templates` — Lynomia manages templates locally as well as syncing them |
| How to use Campaigns? | `audiences-and-campaigns/whatsapp-campaigns` — Lynomia campaigns send to a shared audience, which upstream has no concept of |
| Whatsapp templates | `whatsapp/whatsapp-templates` — Lynomia authors and submits templates; upstream only syncs them |
| Group your contacts into custom segments | `audiences-and-campaigns/labels-or-shared-audiences` — Lynomia has shared audiences, a different and stronger primitive |
| Group chats with filters, save as folders | `audiences-and-campaigns/labels-or-shared-audiences` — Lynomia has shared audiences, a different and stronger primitive |
| How to Segment Contacts in Chatwoot? | `audiences-and-campaigns/shared-audiences` —  |

---

## 5. The full inventory

### Chatwoot 101 (9)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| Chatwoot Glossary | ADAPT | `getting-started/welcome-to-lynomia-chat` | the terms differ; a glossary becomes the welcome article plus the comparison articles |
| Getting Started with Chatwoot | ADAPT | `getting-started/welcome-to-lynomia-chat` | — |
| Lesson 1: Your first Chatwoot conversation | ADAPT | `getting-started/your-first-conversation` | — |
| Lesson 2: Dashboard Basics | ADAPT | `conversations/work-in-the-inbox` | — |
| Lesson 3 (a): Mastering core features | MERGE | `conversations/*` | split across the conversations section |
| Lesson 3 (b): Working with Customer Context | MERGE | `contacts/contacts, commerce/customer-360` | — |
| Lesson 4: Automation and Routing | ADAPT | `automation/automation-rules` | — |
| Lesson 5: AI Actions | NOT RELEVANT | — | AI; out of phase |
| Lesson 6: Reports and Metrics | NOT RELEVANT | — | reports; deliberately not documented yet (06 section 4) |

### Other channels (15)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| How to setup a Facebook channel? | MERGE | `workspace/set-up-an-inbox` | one article covers the channels this product actually offers |
| How to setup an Instagram channel (via Facebook login)? | MERGE | `workspace/set-up-an-inbox` | one article covers the channels this product actually offers |
| How to setup a Twitter channel? | MERGE | `workspace/set-up-an-inbox` | one article covers the channels this product actually offers |
| How to setup a WhatsApp channel? | LYNOMIA HAS DIFFERENT BEHAVIOR | `whatsapp/connect-whatsapp` | one Lynomia article covers connection; Lynomia also has coexistence, which upstream does not document |
| How to setup an SMS channel? | MERGE | `workspace/set-up-an-inbox` | one article covers the channels this product actually offers |
| How to setup an Email channel? | MERGE | `workspace/set-up-an-inbox` | one article covers the channels this product actually offers |
| How to setup a Telegram channel? | MERGE | `workspace/set-up-an-inbox` | one article covers the channels this product actually offers |
| How to setup a Line channel? | MERGE | `workspace/set-up-an-inbox` | one article covers the channels this product actually offers |
| How to create an API channel inbox? | MERGE | `workspace/set-up-an-inbox` | one article covers the channels this product actually offers |
| How to Set Up a WhatsApp Channel with Twilio? | NOT RELEVANT | — | Twilio WhatsApp is not the Lynomia path |
| How to setup an Instagram channel? | MERGE | `workspace/set-up-an-inbox` | one article covers the channels this product actually offers |
| How to setup a WhatsApp channel (Embedded signup) | LYNOMIA HAS DIFFERENT BEHAVIOR | `whatsapp/connect-whatsapp` | one Lynomia article covers connection; Lynomia also has coexistence, which upstream does not document |
| How to setup a WhatsApp channel (Manual flow)? | LYNOMIA HAS DIFFERENT BEHAVIOR | `whatsapp/connect-whatsapp` | one Lynomia article covers connection; Lynomia also has coexistence, which upstream does not document |
| How to setup a TikTok channel? | MERGE | `workspace/set-up-an-inbox` | one article covers the channels this product actually offers |
| Synchronize WhatsApp templates using a Business Management token | LYNOMIA HAS DIFFERENT BEHAVIOR | `whatsapp/whatsapp-templates` | Lynomia manages templates locally as well as syncing them |

### Setup account (7)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| Creating a Chatwoot Account | ADAPT | `getting-started/set-up-your-account` | — |
| Customizing your personal profile | MERGE | `getting-started/set-up-your-account` | — |
| Setting up notifications | MERGE | `getting-started/set-up-your-account` | — |
| Updating your Account settings | ADAPT | `getting-started/set-up-your-account` | — |
| How to invite agents and manage your support team? | ADAPT | `getting-started/invite-your-team` | — |
| What is a channel? What is an inbox? | ADAPT | `workspace/set-up-an-inbox` | a genuinely useful question; Lynomia answers it in its own words |
| A complete guide to teams in Chatwoot | ADAPT | `workspace/teams-and-agents` | — |

### Voice Channels (3)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| Voice Calling in Chatwoot | NOT RELEVANT | — | voice is not in this documentation set (06 section 4) |
| Connecting Twilio voice channel | NOT RELEVANT | — | voice is not in this documentation set (06 section 4) |
| Connecting WhatsApp voice channel | NOT RELEVANT | — | voice is not in this documentation set (06 section 4) |

### Website live chat (14)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| Website live chat settings explained | MERGE | `workspace/set-up-an-inbox` | — |
| How to install live chat using Google Tag Manager? | MERGE | `workspace/set-up-an-inbox` | fourteen near-identical install recipes become one |
| How to install live chat on a Docusaurus website? | MERGE | `workspace/set-up-an-inbox` | fourteen near-identical install recipes become one |
| How to install live chat on a Webflow website? | MERGE | `workspace/set-up-an-inbox` | fourteen near-identical install recipes become one |
| How to install live chat on a Gatsby website? | MERGE | `workspace/set-up-an-inbox` | fourteen near-identical install recipes become one |
| How to install live chat on a WordPress website? | MERGE | `workspace/set-up-an-inbox` | fourteen near-identical install recipes become one |
| How to install live-chat on a React Native app? | MERGE | `workspace/set-up-an-inbox` | fourteen near-identical install recipes become one |
| How to install live-chat on a Next.js app? | MERGE | `workspace/set-up-an-inbox` | fourteen near-identical install recipes become one |
| How to install live-chat on a Vue.js app? | MERGE | `workspace/set-up-an-inbox` | fourteen near-identical install recipes become one |
| How to send additional user information to Chatwoot using SDK? | MERGE | `contacts/contacts` | — |
| How to continue conversations through email? | NOT RELEVANT | — | widget detail below the level this set covers |
| How to enable identity validation in Chatwoot? | MERGE | `contacts/contacts` | — |
| How to enable dark mode on live-chat widget? | NOT RELEVANT | — | widget detail below the level this set covers |
| Understanding Contact Identity and Identity Validation in Chatwoot | MERGE | `contacts/contacts` | — |

### Features explained (14)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| How to add labels? | ADAPT | `conversations/labels` | Lynomia adds the label-versus-audience distinction upstream does not have |
| How to use Agent bots? | ADAPT | `automation/agent-bots` | — |
| Understanding Contacts | ADAPT | `contacts/contacts` | — |
| How to create saved reply templates with Canned Responses? | ADAPT | `conversations/canned-responses` | — |
| How to create and use custom attributes? | ADAPT | `contacts/custom-attributes` | — |
| How to enable CSAT surveys? | MERGE | `conversations/work-in-the-inbox` | Lynomia has its own CSAT template lifecycle; covered where it is used |
| How to assign a priority | MERGE | `conversations/assign-and-prioritise` | — |
| How to use omnichannel message signature? | MERGE | `getting-started/set-up-your-account` | — |
| Preventing Agent Collision | MERGE | `conversations/assign-and-prioritise` | — |
| Manage team access control with flexible role-based permissions | ADAPT | `workspace/roles-and-permissions` | — |
| WhatsApp CSAT Surveys using Templates | MERGE | `conversations/work-in-the-inbox` | Lynomia has its own CSAT template lifecycle; covered where it is used |
| Review Notes for CSAT | MERGE | `conversations/work-in-the-inbox` | Lynomia has its own CSAT template lifecycle; covered where it is used |
| Multi-Factor Authentication (MFA) in Chatwoot | MERGE | `getting-started/set-up-your-account` | — |
| Business Hours and Auto-Responder | MERGE | `workspace/set-up-an-inbox` | — |

### Advanced features explained (20)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| How to use Conversation Filters? | MERGE | `conversations/work-in-the-inbox` | — |
| How to use pre-chat forms? | MERGE | `workspace/set-up-an-inbox` | — |
| How to use Campaigns? | LYNOMIA HAS DIFFERENT BEHAVIOR | `audiences-and-campaigns/whatsapp-campaigns` | Lynomia campaigns send to a shared audience, which upstream has no concept of |
| How to create interactive messages? | MERGE | `whatsapp/whatsapp-templates` | — |
| How to use Automation? | ADAPT | `automation/automation-rules` | — |
| How to setup a WebSocket connection? | NOT RELEVANT | — | developer topic outside this set |
| How to use template variables? | SPLIT | `whatsapp/whatsapp-templates, conversations/canned-responses` | variables mean different things in a template and in a canned response |
| How to use Macros? | ADAPT | `conversations/macros` | — |
| How to use Audit Logs? | ADAPT | `administration/audit-logs` | — |
| Wildcard URL support in website live-chat campaigns | NOT RELEVANT | — | website campaigns are not the Lynomia campaign product |
| Service Level Agreements | NOT RELEVANT | — | SLA expansion is explicitly out of this phase |
| How does sorting work? | MERGE | `conversations/work-in-the-inbox` | — |
| Setting per-agent conversation caps with Agent Capacity Policies | MERGE | `conversations/assign-and-prioritise` | — |
| What is Human Agent tag in Instagram/Messenger channel | NOT RELEVANT | — | Instagram/Messenger specific |
| Whatsapp templates | LYNOMIA HAS DIFFERENT BEHAVIOR | `whatsapp/whatsapp-templates` | Lynomia authors and submits templates; upstream only syncs them |
| Twilio content templates | NOT RELEVANT | — | Twilio is not the Lynomia path |
| Setting up SAML Authentication | NOT RELEVANT | — | not configured in this product |
| Common WhatsApp issues and how to fix them | ADAPT | `whatsapp/whatsapp-troubleshooting` | — |
| Required Conversation Attributes | MERGE | `contacts/custom-attributes` | — |
| Advanced Assignment Policies | MERGE | `conversations/assign-and-prioritise` | — |

### Apps and Integrations (9)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| How to bring your Dialogflow chatbot to Chatwoot? | NOT RELEVANT | — | not offered |
| How to use webhooks? | ADAPT | `integrations/webhooks` | — |
| How to answer conversations from Slack? | MERGE | `integrations/integrations` | one article lists what this product actually integrates with |
| How to use Dashboard Apps? | MERGE | `integrations/integrations` | one article lists what this product actually integrates with |
| How to enable video calls with Dyte integration? | MERGE | `integrations/integrations` | one article lists what this product actually integrates with |
| How to translate messages with Google Translate? | MERGE | `integrations/integrations` | one article lists what this product actually integrates with |
| How to enhance conversations with OpenAI integration? | MERGE | `integrations/integrations` | one article lists what this product actually integrates with |
| How to track Issues and Features with Linear Integration? | MERGE | `integrations/integrations` | one article lists what this product actually integrates with |
| How to enable video calls with Cloudflare RealtimeKit? | MERGE | `integrations/integrations` | one article lists what this product actually integrates with |

### Reports (7)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| How to read Overview Reports (realtime)? | NOT RELEVANT | — | reports are deliberately not documented yet (06 section 4) |
| How to read CSAT Reports? | NOT RELEVANT | — | reports are deliberately not documented yet (06 section 4) |
| How to read Conversations Reports? | NOT RELEVANT | — | reports are deliberately not documented yet (06 section 4) |
| How to read Bot Reports? | NOT RELEVANT | — | reports are deliberately not documented yet (06 section 4) |
| How to read SLA Reports? | NOT RELEVANT | — | reports are deliberately not documented yet (06 section 4) |
| Reading Conversations, Agents, Labels, Inbox, and Team Reports. | NOT RELEVANT | — | reports are deliberately not documented yet (06 section 4) |
| How to read the SLA Reports | NOT RELEVANT | — | reports are deliberately not documented yet (06 section 4) |

### Help Center (5)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| How to set up a Help Center? | MERGE | `workspace/your-own-help-centre` | a tenant's own help centre is one article |
| How to setup an SSL certificate for your Help Center's custom domain? | MERGE | `workspace/your-own-help-centre` | a tenant's own help centre is one article |
| Embedding videos in Help Center | MERGE | `workspace/your-own-help-centre` | a tenant's own help centre is one article |
| Connect analytics to your help center | MERGE | `workspace/your-own-help-centre` | a tenant's own help centre is one article |
| Recommend categories and articles | MERGE | `workspace/your-own-help-centre` | a tenant's own help centre is one article |

### Best practices (5)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| Assigning conversations in a round-robin fashion | MERGE | `conversations/assign-and-prioritise` | — |
| Working with command bar | MERGE | `conversations/work-in-the-inbox` | — |
| Working with keyboard shortcuts | MERGE | `conversations/work-in-the-inbox` | — |
| Group your contacts into custom segments | LYNOMIA HAS DIFFERENT BEHAVIOR | `audiences-and-campaigns/labels-or-shared-audiences` | Lynomia has shared audiences, a different and stronger primitive |
| Group chats with filters, save as folders | LYNOMIA HAS DIFFERENT BEHAVIOR | `audiences-and-campaigns/labels-or-shared-audiences` | Lynomia has shared audiences, a different and stronger primitive |

### Captain (11)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| Introduction to Captain | NOT RELEVANT | — | AI is explicitly out of this phase |
| Creating an assistant with Captain | NOT RELEVANT | — | AI is explicitly out of this phase |
| Creating a document in Captain | NOT RELEVANT | — | AI is explicitly out of this phase |
| Creating an FAQ with Captain | NOT RELEVANT | — | AI is explicitly out of this phase |
| How to use Captain Memories? | NOT RELEVANT | — | AI is explicitly out of this phase |
| How to use Captain Copilot? | NOT RELEVANT | — | AI is explicitly out of this phase |
| How to enable Captain on self-hosted installations? | NOT RELEVANT | — | AI is explicitly out of this phase |
| How AI Credits work in Captain? | NOT RELEVANT | — | AI is explicitly out of this phase |
| Updating robots.txt to Allow Chatwoot Assistant to Crawl Your Website | NOT RELEVANT | — | AI is explicitly out of this phase |
| How to Set Up Custom Tools for Captain? | NOT RELEVANT | — | AI is explicitly out of this phase |
| Control who Captain replies to and when | NOT RELEVANT | — | AI is explicitly out of this phase |

### Migrations (4)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| How to migrate from Intercom to Chatwoot? | NOT RELEVANT | — | competitor-switch marketing, not product documentation |
| How to migrate from Front to Chatwoot? | NOT RELEVANT | — | competitor-switch marketing, not product documentation |
| How to migrate from Freshdesk to Chatwoot? | NOT RELEVANT | — | competitor-switch marketing, not product documentation |
| How to migrate from Zendesk to Chatwoot? | NOT RELEVANT | — | competitor-switch marketing, not product documentation |

### Other topics (14)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| Which cookies are used by Chatwoot? | NOT RELEVANT | — | legal copy, not documentation |
| Mobile app for Android | MERGE | `getting-started/welcome-to-lynomia-chat` | mentioned only where true for this product |
| Mobile app for iOS | MERGE | `getting-started/welcome-to-lynomia-chat` | mentioned only where true for this product |
| Enterprise Edition | NOT RELEVANT | — | upstream's own commercial terms |
| Languages supported in Chatwoot | MERGE | `getting-started/set-up-your-account` | — |
| What we don't cover in Chatwoot Free Trial | NOT RELEVANT | — | upstream's own commercial terms |
| How to enable push notifications in your browser | MERGE | `troubleshooting/troubleshooting` | — |
| How to hard-reload on most browsers | MERGE | `troubleshooting/troubleshooting` | — |
| How to Use Your Coupon Code on Chatwoot? | NOT RELEVANT | — | upstream's own commercial terms |
| Inconsistencies for WhatsApp Numbers in Brazil and Argentina | NOT RELEVANT | — | not this market |
| Troubleshooting: Why am I not receiving notifications? | MERGE | `troubleshooting/troubleshooting` | — |
| Migrate a WhatsApp Embedded Signup inbox to manual setup | ADAPT | `whatsapp/whatsapp-troubleshooting` | — |
| WhatsApp usernames and Business-Scoped User IDs in Chatwoot | ADAPT | `whatsapp/whatsapp-troubleshooting` | — |
| Troubleshoot WhatsApp onboarding issues | ADAPT | `whatsapp/whatsapp-troubleshooting` | — |

### How To (6)

| Article | Action | Lynomia destination | Note |
|---|---|---|---|
| Purchasing a Paid Self-Hosted Chatwoot License: A Step-by-Step Guide | NOT RELEVANT | — | upstream's own commercial terms |
| How to Find Your Personal Access Token in Chatwoot | MERGE | `integrations/integrations` | — |
| How to Embed Your Help Center Articles in the Live Chat Widget | MERGE | `workspace/your-own-help-centre` | — |
| How to Change Your Email Address in Chatwoot | MERGE | `getting-started/set-up-your-account` | — |
| How to Remove the Free Usage Limit Exceeded Message in Chatwoot | NOT RELEVANT | — | upstream's own commercial terms |
| How to Segment Contacts in Chatwoot? | LYNOMIA HAS DIFFERENT BEHAVIOR | `audiences-and-campaigns/shared-audiences` | — |
