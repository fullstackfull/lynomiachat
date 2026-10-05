# 05 — The template builder

The screen where a template is written, what it refuses and when, and why its preview can be trusted. Read with
`01-meta-api-contract.md §2` for the rules it encodes and `07-starter-gallery.md` for what fills it.

---

## 1. One way in

`TemplateBuilderDialog.vue` is the only place a template is authored, and it is the same dialog for a new draft and
for an edit. Not two screens with drifting rules: the form, the validation and the preview are written once, and what
differs between new and edit is which fields are locked.

**Locked on an edit, because Meta does not allow them to change:** the name, the language and the business account.
The name and language are a template's identity at Meta (`01-meta-api-contract.md §2`), and a "rename" is a different
template; the inbox is chosen once because the template is created in that inbox's WABA. The three inputs are
disabled, each with the reason in the hint beneath it, rather than silently dropped from the payload.

**The dialog does not copy Meta Business Manager.** It is the product's own `Dialog`, `Input`, `Select` and `Button`,
laid out as the rest of Lynomia Chat's settings are, with Tailwind utilities and no scoped CSS. What it borrows from
Meta is the rules, not the furniture.

## 2. What the form holds

| Field | Shape | Note |
|---|---|---|
| Inbox | the account's WhatsApp inboxes | determines the WABA the template is created in; the hint says every inbox sharing that account can send it |
| Name | `[a-z0-9_]`, ≤512 | the hint says WhatsApp does not allow it to change later |
| Language | a template language code (`en_US`, `ar`, …) | the hint says this is the template's language, not the dashboard's |
| Category | `UTILITY` / `MARKETING` | the hint says WhatsApp decides the final category and may change it |
| Variables | `POSITIONAL` (`{{1}}`) or `NAMED` (`{{order_number}}`) | the format Meta reviews the examples under |
| Header | none / text / image / video / document | one variable at most in a text header, as Meta allows |
| Body | required, ≤1024 | the only required component |
| Footer | optional, ≤60 | no variables at all, as Meta allows none |
| Buttons | quick reply, URL, phone number, copy code | each with its own fields; add and remove per row |
| Sample values | one per variable found in the text | see §4 |

`AUTHENTICATION` is deliberately absent from the category list: WhatsApp writes an authentication template's body
itself and requires an Android package name and signature hash, so authoring one here would produce a template this
product cannot send (`01-meta-api-contract.md §5`). Carousel, catalogue, product-list and limited-time-offer
components are absent for the same reason.

## 3. Three layers of validation, each with a different job

| Layer | Where | Job |
|---|---|---|
| **In the form, as you type** | `TemplateBuilderDialog.vue` | the inputs' own `maxlength` and types; the preview redrawing; the per-variable sample inputs appearing and disappearing as variables are typed |
| **On the server, before anything leaves** | `Whatsapp::Templates::Validator` | every published WhatsApp rule: lengths, component set, variable numbering and placement, button type counts and grouping, URL variable position, a sample for every variable |
| **At Meta** | Meta's reviewers | everything no public rule covers — tone, accuracy, category fit |

The second layer is the authority for the first two: the builder renders exactly the problems the server returns, by
field and by code, so the message a user reads and the rule a submit enforces can never disagree. A failed save
renders them beneath the fields they belong to, in the user's language, from stable codes — the server never builds an
English sentence.

**The copy never confuses the layers.** The validation summary says, in both languages, that passing these checks is
not approval and that WhatsApp reviews whatever is submitted. A draft that validates is a draft, not a pending
template, and the list says so (`12-regression-results.md §3`).

### Where the builder is deliberately stricter than Meta

`BUTTON_COPY_CODE_MAX` is 15, not Meta's current 20. `Whatsapp::PopulateTemplateParametersService` — the existing send
path, untouched by this phase — still refuses a coupon longer than 15 characters, so a template authored up to 20
would be created at Meta and then fail at send time. The manager holds the stricter of the two until that send-path
constant is raised, and the constant carries the reason in a comment so the two move together.

## 4. Sample values are not production values

Every variable the body or header text contains grows its own sample input, labelled with the variable itself. Meta
requires a sample for each one at create time, under a key that depends on the parameter format
(`body_text`, `body_text_named_params`, `header_text`, `header_text_named_params`), and the builder assembles the
right key from the chosen format.

The explanation beneath them is explicit: **WhatsApp reviews the template with these, and they are never sent to a
customer.** This is the distinction `08-variables.md §1` draws — definition, sample, runtime value — made visible in
the one place a person could confuse them.

## 5. The preview, and why it is honest

The preview redraws from the form on every keystroke and **makes no request at all** — not to Meta, not to Lynomia's
own server. It is a computed value over the form's text, rendered by the product's existing
`components-next/template-preview` bubbles, the same components that render a template everywhere else in the
product. So what the builder shows and what a customer receives are the same renderer, and a change to one cannot
drift from the other.

It shows the header, the body with its variables substituted by their sample values, the footer and the buttons.
Nothing in it is labelled approved, pending or reviewed; it is a drawing of a message, and the state of the template
is the list's job, not the preview's.

**A defect this phase fixed in that shared renderer:** `CallToActionTemplate.vue` drew only the body, so a template
with buttons silently lost its header and footer — in the preview and everywhere else the component is used. Both are
now drawn. It was found in the browser, not by a spec (`12-regression-results.md §3`).

## 6. What saving does

Saving writes a row and nothing else. No Graph call, no submission, no state at Meta: a new draft reads **Not sent to
WhatsApp for approval** the moment it appears in the list. Submitting is a separate, confirmed action
(`06-meta-submit-edit-delete.md §1`).

The dialog stays open while there is something to fix and closes when there is not — which is the behaviour the
browser journey asserts, because a dialog that closes over an unsaved error loses the user's work.
