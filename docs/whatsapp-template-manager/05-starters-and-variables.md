# 05 — Starters, and the variables a template's values can use

What a starter is (and is not), which ones exist and why, and where a Lynomia variable may be used in a template's
parameter values. Read with `01-meta-api-contract.md` for what Meta allows in a template itself.

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

## 3. Variables: three different things that look alike

The brief's distinction, made concrete:

| | What it is | Where it lives | Who fills it |
|---|---|---|---|
| **Placeholder** | `{{1}}` or `{{order_number}}` in the template's text | the template's `components`, at WhatsApp | the template author |
| **Sample value** | what WhatsApp reviews the template with | the component's `example` (`body_text`, `body_text_named_params`, …) | the template author, in the builder |
| **Runtime value** | what the customer actually reads | `template_params.processed_params` on the message or campaign | the send context, at send time |

The builder is explicit about the middle one: "WhatsApp reviews the template with these, and they are never sent to a
customer." A sample is never saved as a production value, and a production value never reaches WhatsApp's reviewer.

---

## 4. The variable registry, and the one it fixed

Runtime values are where a Lynomia variable may appear, and **which variables resolve depends on the send context**
(`00-current-system.md §7`). The ground truth is the Liquid drops in `app/drops/`; `Flows::Variables` is the only
allow-list the server enforces, and it is the flow builder's.

**The defect this phase fixed.** `{{contact.phone}}` was offered by the composer and canned-response pickers
(`shared/constants/messages.js:128`, `@chatwoot/utils` `getMessageVariables`) and resolved **nowhere**: `ContactDrop`
implemented only `phone_number`. In the composer the editor substitutes it client-side, so it looked fine. In a
**campaign** it rendered empty — and a blank render skips the whole recipient
(`Whatsapp::LiquidTemplateProcessorService`), so one offered variable silently dropped an entire audience. `ContactDrop#phone`
now delegates to `phone_number`, so the variable the product has always offered resolves in every context.

**What is still not offered, and why.** `{{abandoned_cart_url}}` and anything like it does not exist in any list or
drop, and no send context could resolve it; `flow.reply`, `flow.<key>` and `flow.order.*` resolve **only** inside a
flow run, which is why they are offered in the flow builder and nowhere else.

**What this phase did not do.** The composer's own variable picker still reads its client-side list. That list is
resolved in the browser before the message is created, so it is not a send-context question, and rewiring it would
change canned responses, macros and every composer surface — well outside a template manager. It is recorded here as
the remaining half of the brief's "one registry" rather than quietly left out.
