# P10.4 / P10.5 — Omnichannel Customer 360 and the cross-channel agent experience

What this document is for: what an agent can see and do about one customer across channels, what P10 added, and
— at least as important — what was already there and was therefore left alone.

---

## 1. What was already true

Before adding anything, each part of "Customer 360" was traced to the thing that already answers it:

| the agent wants | where it already is |
| --- | --- |
| every conversation this customer has had, on any channel | the contact's **History** tab, `GET /contacts/:id/conversations` |
| everything that happened, in order, across channels | the contact's **Activity** tab — P8's `Contacts::ActivityTimelineQuery`, filtered by `Conversations::PermissionFilterService` |
| this customer's open support cases | the contact's **Cases** tab — P9, with the support module's own visibility rule |
| this customer's orders across connected stores | `Commerce::Customer360`, in the conversation panel |
| attachments the customer sent | the **Media** tab |
| notes about the customer | the **Notes** tab |
| which channels I can start a conversation on | the new-conversation composer, which calls `Contacts::ContactableInboxesService` and renders an `InboxSelector` |

So the cross-channel history, the cross-channel timeline and the honest channel chooser all existed. P10 added
**one** thing, because it was the only thing missing: the set of values that resolve to this customer.

**On the "message on any channel" control the brief warns about.** The product does not have one and P10 did not
add one. `ComposeNewConversationForm` asks the server which inboxes this contact is contactable on and offers
only those; `Api::V1::Accounts::ContactsController#contactable_inboxes` filters the service's answer through
`policy(inbox).show?`, which is `Current.user.assigned_inboxes.include?(record)`. An inbox-restricted agent is
therefore offered only their own inboxes, and an inbox with no way to initiate (Facebook, Instagram, Telegram,
LINE, TikTok, X) is not offered at all because the service has no branch for it. That is already the honest
behaviour the brief asks for, verified rather than assumed.

## 2. What P10.4 added: the Identities tab

One tab in the contact view, `IDENTITIES`, offered only when the account has the `lynomia_unified_identity`
feature — the same `when:` mechanism the Cases tab uses, so an account without the module never sees a tab whose
endpoint answers 404.

Two sections, from two sources, deliberately **not** merged into one list:

- **Primary** — `contacts.phone_number` and `contacts.email`. Unique per account, and what an outgoing
  conversation uses.
- **Also reachable at** — the rows in `contact_identities`, each labelled with where it came from: *Linked by an
  agent* or *From a merge*.

Saying which is which is the point, and the panel's own description says it in one sentence: *"A primary number
or address is what an outgoing conversation uses; a linked one is matched when a message arrives."* That is the
honest boundary of what P10 built — see §4.

**Permissions.** Reading follows the contact: anyone who may open it sees the list, like the notes and the
attachments. Linking and unlinking follow the merge: administrator, or an agent whose custom role grants
`contact_manage`. The tab is therefore visible to everyone who can open the contact, and the controls appear
only for those who may use them — `canManage` gates the add form and the unlink buttons, and a spec asserts
that a viewer without the permission sees no buttons at all.

**Refusals are shown, not translated into an offer.** When a value already belongs to another contact the server
answers 422 naming that contact, and the panel renders that sentence. It does not offer to merge, does not
suggest a candidate and does not retry. That is the same stance the server takes
(docs/p10/03-unified-customer-identity.md §4.1).

## 3. What it reuses

- `ContactAPI`, three new methods on the existing client — no new API layer.
- `Button`, `Input` and `Spinner` from the existing design system; Tailwind utilities and design tokens only, no
  custom CSS and no new frontend dependency.
- The existing tab mechanism in `ContactManageView.vue`, including its `when:` feature gate.
- `usePolicy().checkPermissions`, the repository's own permission check.
- `useAlert` for the success toast.
- Composition API with `<script setup>`, i18n for every string, `bdi dir="auto"` on each value so an Arabic
  interface renders a `+965…` number the right way round, and static i18n keys rather than interpolated ones so
  the linter can check them.

English and Arabic keys were added together; both carry all fifteen.

## 4. What P10 deliberately did NOT do here

**A linked identity is not an outbound target.** The composer still uses the contact's primary number or
address. Offering each linked value as a separate destination would mean changing the shape of
`contactable_inboxes` — one entry per (inbox, identity) pair instead of per inbox — on an endpoint the composer,
the inbox selector and the contact selector all consume, and the failure mode of getting it wrong is a message
sent to the wrong number. Inbound matching is the half that removes duplicates and it is solved; outbound target
selection is a convenience, and it is not worth that risk in this phase. The panel says so to the agent rather
than leaving them to find out.

**No duplicate of the conversation list or the timeline.** The panel shows identities. "Which channels has this
customer used" is the History tab and the Activity timeline, both of which already span channels and both of
which already apply the conversation permission filter. Rendering a third version of the same data in the
identity panel would be the second contact system this phase exists to avoid.

**No duplicate-suggestion UI.** Nothing proposes "these two contacts might be the same person". That would need
the probabilistic matching B1 forbids.

**No new panel in the conversation sidebar.** The conversation's own `ContactPanel` already carries the contact
attributes, labels, notes, cases and commerce. Adding identities there as well would be two places to keep in
step for a fact an agent consults when they are looking at the customer, not at the message.
