# 07 — The starter catalogue

What a starter is (and is not), which ones exist, and which deliberately do not. Read with
`01-meta-api-contract.md` for what Meta allows in a template itself, and `08-variables.md` for the values a template
can carry.

---

## 1. A starter is a starting point, not a template

A starter fills the builder's form with a draft to edit. It is **not** a template, not something WhatsApp has seen, and
not approved by anyone. Choosing one creates no record and sends nothing: the user edits it, saves it as their own
draft, and WhatsApp reviews it exactly as it would a template written from scratch.

Three consequences, all enforced by where the code lives:

- **Source-controlled, like every other starter in this product.** `app/javascript/dashboard/recipes/templateStarters.js`,
  beside the automation recipes and flow templates P2 added. No table, no API, no sharing between accounts — so there
  is no second template marketplace, and none of the user-shared library the brief rules out.
- **Updating a starter never touches anyone's template.** A draft is a row; a starter is a constant. Changing the
  constant changes what the *next* person starts from and nothing else.
- **The copy never claims approval.** The builder says, above the starters: "They are not WhatsApp templates and
  nothing here is approved: WhatsApp reviews whatever you submit."

They live **inside the builder** rather than in a gallery of their own, which is the smallest honest shape: one way in
to a new template, with a row of starting points at the top of it.

Each starter carries its own text per template language, because a template's language is the customer's, not the
dashboard's. `en_US` and `ar` are written out; anything else falls back to `en_US` and the user edits.

---

## 2. Which starters exist, and which deliberately do not

**HIGH — implemented.** Each is a message a Gulf commerce or support business sends every day, is UTILITY or plainly
transactional MARKETING, and uses only components Lynomia Chat can actually send.

| Starter | Why it earns its place |
|---|---|
| `order_shipped` | the single most-sent WhatsApp template in commerce; carries a tracking URL button |
| `order_delivered` | closes the loop and invites a problem report, with two quick replies |
| `delivery_delayed` | the message a business most often has to write in a hurry |
| `appointment_reminder` | services and clinics; confirm/reschedule quick replies |
| `payment_due` | invoice reminder with a link to the invoice |
| `back_in_stock` | the one marketing message customers ask for, with an unsubscribe footer |
| `support_follow_up` | reopens a conversation outside the 24-hour window, which is what templates are for |
| `welcome_message` | the first reply, and the easiest first template for a new account |

**MEDIUM — not implemented, each for a stated reason.**

| Not implemented | Reason |
|---|---|
| Abandoned cart | no send context resolves a cart URL (`00-current-system.md §7`), and cart persistence is explicitly out of this phase |
| Promotional discount | the copy is the business's own; a starter would be putting words in their mouth, and marketing copy is where WhatsApp rejections concentrate |
| Feedback survey | CSAT owns that template and its versioned lifecycle (`03-sync-and-lifecycle.md §5.5`) |
| Loyalty points, event invite | no product surface produces the values they would need |

**LOW — not implemented.** One-time passcodes (WhatsApp writes an authentication template's body itself and needs an
Android package name and signature hash, `01-meta-api-contract.md §5`), and anything built from a catalogue, carousel,
product list or limited-time-offer component — Lynomia Chat cannot send those, so authoring them would create
templates the product could never use.

---
