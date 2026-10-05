# 09 — The content master map

Every article in the Lynomia Chat documentation set: where its topic came from, what it says that is specific to this
product, and its status.

Sources are abbreviated **CW** (Chatwoot user guide topic coverage — `03`), **KZ** (Karzoun — `04`),
**LYN** (this repository — `05`), and **NEW** where no source has an equivalent at all.

---

## 1. How to read the "Lynomia-specific" column

It is the reason the article could not have been adapted from anywhere. Where it says *everything*, no upstream
equivalent exists and the whole article is written from the code. Where it names one thing, that is the sentence a
reader coming from another product would otherwise get wrong.

## 2. Getting started

| Key | Source | Lynomia-specific |
|---|---|---|
| `welcome-to-lynomia-chat` | CW glossary + CW 101 | the three independent languages — dashboard, account, template — kept apart from the first page |
| `set-up-your-account` | CW setup account | — |
| `invite-your-team` | CW + KZ (both invite before connecting a channel) | the real role list, not an assumed one |
| `connect-your-first-channel` | CW "what is a channel? what is an inbox?" | which channels this product actually offers |
| `your-first-conversation` | CW Lesson 1 | — |

## 3. Conversations

| Key | Source | Lynomia-specific |
|---|---|---|
| `work-in-the-inbox` | CW Lesson 2 + filters + shortcuts | folders are saved filters, not folders |
| `assign-and-prioritise` | CW assignment + priority + round-robin | — |
| `labels` | CW "how to add labels" | **when *not* to use a label** — the audience distinction upstream has no concept of |
| `canned-responses` | CW canned responses | variables here are not template variables |
| `macros` | CW macros | — |
| `macros-or-automation` | **NEW** | a comparison upstream never draws |

## 4. Contacts

| Key | Source | Lynomia-specific |
|---|---|---|
| `contacts` | CW "understanding contacts" | **phone numbers are unique per account** — a Lynomia constraint added in an earlier phase |
| `custom-attributes` | CW custom attributes | — |
| `import-contacts` | CW (none — upstream documents no import) | the paste-a-list flow and the duplicate rule, both Lynomia-only |
| `bulk-actions` | **NEW** | the vocabulary is exactly three operations, the 10,000 ceiling, and that bulk actions are not audited |

## 5. Audiences and campaigns

| Key | Source | Lynomia-specific |
|---|---|---|
| `shared-audiences` | **NEW** | everything. An audience is a saved query re-answered on use; there is no membership table |
| `labels-or-shared-audiences` | KZ (which conflates labels and segments) | everything |
| `whatsapp-campaigns` | CW "how to use campaigns" — **different behaviour** | everything: recipients come from audiences, only an APPROVED template may be sent, an empty variable skips the contact, and there are exactly two campaign types |

## 6. WhatsApp

| Key | Source | Lynomia-specific |
|---|---|---|
| `connect-whatsapp` | CW ×3 + KZ's four most-read articles | one path, not three |
| `whatsapp-business-coexistence` | **NEW** | everything, including its readiness state |
| `the-whatsapp-24-hour-window` | KZ (its top-read topic) | written for an owner, not an administrator |
| `whatsapp-templates` | CW "Whatsapp templates" — **different behaviour** | upstream only syncs templates; this product authors and submits them |
| `whatsapp-template-lifecycle` | **NEW** | everything: draft versus approved, what each state allows, the 30-day name lockout, name and language immutable |
| `whatsapp-troubleshooting` | CW "common WhatsApp issues" | — |

## 7. Automation and bots

| Key | Source | Lynomia-specific |
|---|---|---|
| `automation-rules` | CW "how to use Automation" | the commerce triggers, and that a new rule starts switched off |
| `flow-builder` | **NEW** | everything, including **WhatsApp Cloud only** and entry from a conversation message only |
| `automation-or-flow-builder` | **NEW** | everything |
| `agent-bots` | CW agent bots | that the page hides flow bots |

## 8. Commerce

| Key | Source | Lynomia-specific |
|---|---|---|
| `commerce-overview` | **NEW** | everything |
| `commerce-provider-support` | **NEW** | everything — the capability matrix is the single most load-bearing table in the corpus |
| `connect-woocommerce` / `-salla` / `-zid` / `-shopify` | **NEW** (CW has a Shopify integration article, unrelated) | everything, including each provider's real limits |
| `customer-360` | **NEW** | everything, including visible spend versus lifetime value |

## 9. Workspace and team

| Key | Source | Lynomia-specific |
|---|---|---|
| `set-up-an-inbox` | CW ×15 channel guides, merged | one article, the real channel list |
| `teams-and-agents` | CW "complete guide to teams" | — |
| `roles-and-permissions` | CW role-based permissions | **the real permission list**, which does not include inboxes, campaigns, templates, flows or audiences |
| `your-own-help-centre` | CW Help Center ×5, merged | that it is the tenant's own, separate from this documentation |

## 10. Platform

| Key | Source | Lynomia-specific |
|---|---|---|
| `integrations/integrations` | CW apps and integrations ×9, merged | which of them this product actually has |
| `integrations/webhooks` | CW "how to use webhooks" | — |
| `administration/audit-logs` | CW audit logs | what is and is not recorded |
| `troubleshooting/troubleshooting` | CW "other topics" ×14, merged | — |

---

## 11. Totals

| | Count |
|---|---|
| Articles | 43 |
| Sections | 11 |
| Languages | 2 (English, Arabic) |
| Files | 86 |
| Articles with **no** upstream equivalent (NEW) | 15 |
| Articles where upstream behaviour **differs** | 3 |
| Upstream articles whose topic is covered | 99 of 143 (the other 44 are NOT RELEVANT — see `03 §3`) |

**No article's prose is adapted from either external source.** The sources decided *which* articles exist; the code
decided what they say.

## 12. The changelog

Release notes are seeded separately (`08-changelog-design.md`). They are built **only** from product work evidenced
in this repository — the phase documents under `docs/` and the commits behind them. Where a release date cannot be
established from the repository it is **not invented**: the changelog starts from the first release that can be
supported, and says so on its first entry.
