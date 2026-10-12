# Platform Support Desk — customer experience

> Phase 0. Design intent and the conventions it must follow. No components written.

## 1. Design posture: a portal, not an internal CRM

The tenant side of this module is the one place where a Lynomia customer talks to Lynomia. It should read like
a help portal — reassuring, sparse, one obvious next action — and explicitly **not** like the agent-facing
Support Cases workspace, which is a dense filterable table built for somebody working a queue all day
(`app/javascript/dashboard/components-next/SupportTickets/TicketsTable.vue`).

Concretely, three differences from that workspace:

| | Tenant Support Cases workspace (exists) | Platform Support portal (this module) |
|---|---|---|
| List shape | Table with sortable columns, filter bar, view tabs | A short card list: subject, status chip, last-activity, reply indicator |
| Density | Built for hundreds of rows | Built for the handful an account will ever open |
| Primary action | Filter and triage | **New ticket**, always visible |

## 2. Navigation

`Help & Support` already exists as a sidebar group with a life-buoy icon
(`app/javascript/dashboard/components-next/sidebar/Sidebar.vue:727-745`). Two new children, placed above the
existing external links so the in-product destination is first:

```
Help & Support
  My tickets          -> to: accountScopedRoute('platform_support_index')
  Documentation       -> href (unchanged)
  Contact support     -> href (unchanged)
```

Two hard requirements:

1. **The `.filter(child => child.href)` at `Sidebar.vue:744` must become `child => child.href || child.to`**, or
   the entry is silently dropped. This is the one production change the module cannot ship without
   (`01-architecture.md` §9).
2. `My tickets` carries a **count badge** only when the account has at least one ticket with an unread operator
   reply (§6). No badge otherwise — a permanent "0" trains people to ignore it.

Route: `accounts/:accountId/help/tickets` and `accounts/:accountId/help/tickets/:ticketId`. Deliberately under
`help/`, not `support/`, because `accounts/:accountId/support/cases` is the tenant module's own path
(`app/javascript/dashboard/routes/dashboard/tickets/tickets.routes.js:21`) and the two must not read as
siblings.

Route `meta`: `permissions: ['administrator', 'agent', 'custom_role']`, and **no `featureFlag`**
(`01-architecture.md` §6). The agent/custom-role entries are present because every member may open a ticket;
what they can *see* afterwards is the policy's business, not the route's — the same reasoning the tenant module
recorded for its own route (`tickets.routes.js:8-12`).

## 3. Three screens

### 3.1 My tickets

- Card list, newest activity first. Each card: subject, `LYN-000123`, status chip, category chip, relative
  last-activity, and a dot when an operator has replied since the customer last looked.
- Two groupings, not filters: **Open** and **Closed**. A customer with six tickets does not need a filter bar.
- Empty state is the product's first teaching moment: one line on what this is for ("Questions about Lynomia
  itself — billing, WhatsApp setup, something not working"), one line on what it is not ("For conversations
  with your own customers, use Inbox"), and the New ticket button.
- Pagination appears only past 25 tickets.

### 3.2 New ticket

One page, four fields, in this order:

| Field | Control | Notes |
|---|---|---|
| Category | Select | Eleven options (`02-data-model.md` §6). Required. A one-line hint under each choice is Phase 2 |
| Subject | Text | Required, max 255 |
| Description | Textarea | Required, max 10 000, with a placeholder prompting for what actually helps: what you expected, what happened, when it started |
| Priority | Select | Default `medium`. Labelled honestly — "Urgent" says "service is down for us", not "I would like this faster" |
| Attachments | File picker | Optional, up to 5 files, 10 MB each, with the accepted types listed before the picker, not after a rejection (`03-authorization-security.md` §7) |

On submit: navigate to the new ticket's detail page showing `LYN-000123` and a plain statement of what happens
next ("A Lynomia engineer will reply here. You will get an email when they do."). No modal, no toast-and-stay —
the reference is the receipt and the customer should land on it.

Validation errors come from the server as 422 with a message, rendered inline. The existing
`CustomExceptions` → 422 convention is reused (`custom/app/controllers/api/v1/accounts/support/base_controller.rb:25-28`).

### 3.3 Ticket detail

Top: subject, `LYN-000123`, status chip, category, priority, opened-on, and one sentence of state in plain
language — not an enum name:

| Status | What the customer reads |
|---|---|
| `open` | "Received. A Lynomia engineer will pick this up." |
| `in_progress` | "A Lynomia engineer is working on this." |
| `waiting_on_customer` | "We need something from you — see the latest reply." |
| `waiting_on_lynomia` | "With Lynomia. Nothing needed from you." |
| `resolved` | "Resolved. Reply here if it is not fixed." |
| `closed` | "Closed." |

This mapping is the whole justification for keeping `waiting_on_lynomia` as a distinct status
(`02-data-model.md` §5).

Body: the thread — public messages and customer-visible events in one chronological list, oldest first, with
the newest reply in view. Author shown as the person's name for the customer's own side and as **"Lynomia
Support"** for the operator side; the individual operator's name is never shown (`03-authorization-security.md`
§1). Attachments render as named rows with a download action, never as a bare URL.

Footer: a reply box, always available — including on a `resolved` ticket, where replying reopens it. No reply
box on `closed`; instead, a "Open a new ticket" link that pre-fills the category.

What the detail page **never** contains: internal notes, operator names, SLA targets or countdowns, assignment
history, priority changes, linked resources, `metadata`, or anything about another account.

## 4. What the customer must never see — and where that is enforced

The brief's list, mapped to its enforcement point rather than to a UI rule:

| Must never see | Enforced at |
|---|---|
| Another account's ticket | `PlatformSupport::TicketPolicy::Scope` adds `where(account_id:)` itself (`03-authorization-security.md` §2) |
| Lynomia internal notes | A separate table with no tenant-reachable association (`02-data-model.md` §7) |
| Private operator metadata | `events.metadata` absent from the tenant serializer; `assigned`/`priority_changed` absent from `CUSTOMER_VISIBLE_EVENT_TYPES` (`02-data-model.md` §9) |
| Another customer's details | Nothing in the tenant response references another account |
| Raw provider errors / secrets | Nothing is auto-copied into a ticket at all (`03-authorization-security.md` §11) |
| Internal Operations data | The tenant serializer has no `links` key (`02-data-model.md` §11) |

None of these is a front-end rule, which is the point.

## 5. Arabic and RTL, from the first commit

Not a later pass. The repository's standing expectations:

- **Both locale files, together.** `app/javascript/dashboard/i18n/locale/en/` and `…/ar/` each hold 53 files
  and the tenant support module has a sibling in both (`en/supportTickets.json`, `ar/supportTickets.json`). A
  new `platformSupport.json` ships in both in the same commit. Only `en.json`/`en.yml` are edited for source
  strings per CLAUDE.md; Arabic is added here because a Lynomia-owned module's Arabic is Lynomia's
  responsibility, not Crowdin's.
- **Logical Tailwind utilities only** — `ms`/`me`/`start`/`end`, never `ml`/`mr`/`left`/`right`. The status
  chip, the reply indicator dot, the attachment rows and the card chevrons are all direction-sensitive.
- **No bare strings in templates.** Every label, placeholder, status sentence in §3.3, category name, error
  message and empty state goes through `t()`.
- **The status sentences are the translation risk.** They are prose, not enum labels, and a literal Arabic
  translation of "With Lynomia" is meaningless. They need a translator's judgement, not a dictionary — flagged
  in `09-implementation-plan.md` as part of Phase D rather than treated as mechanical.
- **Relative timestamps and numerals** use the existing shared helpers so Arabic-Indic digits and RTL date
  ordering follow the installation's existing behaviour rather than being re-derived here.

## 6. The unread indicator, without a notification row

The reply dot and the sidebar badge are derived, not stored:

```
unread  =  last_operator_message_at.present? &&
           (customer_last_viewed_at.nil? || last_operator_message_at > customer_last_viewed_at)
```

`customer_last_viewed_at` is stamped when a tenant user opens the detail page. All three columns are on
`platform_support_tickets` (`02-data-model.md` §2), so the badge is a count over an indexed account scope and
is always consistent with the thread — it cannot drift the way a denormalized feed row can, and it needs no row
in the `notifications` table whose read-time narrowing passes non-Conversation actors through unauthorized
(`06-sla-notifications.md` §4).

Known limitation, stated rather than hidden: the stamp is per-account, not per-user, so in an account with two
administrators the first to open the ticket clears the dot for both. A per-user read marker is a second table
and is Phase 2. For a vendor desk where a ticket is usually one person's, the simpler column is the right first
answer.

## 7. Components and where they live

Per CLAUDE.md, `components-next/` only, Composition API with `<script setup>`, Tailwind utilities only, no
scoped CSS, no inline styles.

```
app/javascript/dashboard/routes/dashboard/help/
  help.routes.js
  pages/PlatformSupportIndexPage.vue
  pages/PlatformSupportDetailPage.vue
  pages/PlatformSupportNewPage.vue
app/javascript/dashboard/components-next/PlatformSupport/
  TicketCard.vue  StatusChip.vue  ThreadMessage.vue  ThreadEvent.vue
  ReplyBox.vue    AttachmentList.vue  NewTicketForm.vue
app/javascript/dashboard/api/platformSupport.js
app/javascript/dashboard/composables/usePlatformSupport.js
app/javascript/dashboard/i18n/locale/{en,ar}/platformSupport.json
```

Reuse rather than rebuild: the existing design-system `Button`, `Input`, `Select`, `Dialog` and skeleton
primitives; typography utilities instead of hand-rolled font styles; the shared request-cancellation utility
instead of a local `AbortController`; and the existing relative-time helper. `StatusChip` is a thin wrapper
over the design system's badge with the status→intent map, mirroring how `TicketEnumLabel.vue` already does it
for the tenant module.
