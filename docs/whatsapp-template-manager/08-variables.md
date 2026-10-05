# 08 — Variables

Where a Lynomia variable may be used in a template, which ones resolve, and the one that did not. Read with
`07-starter-gallery.md`, whose starters are written against this registry.

---

## 1. Variables: three different things that look alike

The brief's distinction, made concrete:

| | What it is | Where it lives | Who fills it |
|---|---|---|---|
| **Placeholder** | `{{1}}` or `{{order_number}}` in the template's text | the template's `components`, at WhatsApp | the template author |
| **Sample value** | what WhatsApp reviews the template with | the component's `example` (`body_text`, `body_text_named_params`, …) | the template author, in the builder |
| **Runtime value** | what the customer actually reads | `template_params.processed_params` on the message or campaign | the send context, at send time |

The builder is explicit about the middle one: "WhatsApp reviews the template with these, and they are never sent to a
customer." A sample is never saved as a production value, and a production value never reaches WhatsApp's reviewer.

---

## 2. The variable registry, and the one it fixed

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
