# Flow template additions

Phase P2, Part C. Two templates, taking the catalogue from six to eight, plus one defect fixed in the shared
builder.

---

## 1. What the contract allows

A flow template's `build(values)` returns a plain `{ nodes, edges }` graph — the same shape the builder saves and
`Flows::GraphValidator` checks. The node types, their outputs, which outputs must be connected and each node's
permitted `data` keys are fixed by `custom/app/services/flows/node_types.rb:9-34` and validated by
`custom/app/services/flows/node_validator.rb`. A template that steps outside it produces a draft nobody can
publish, so `recipes/specs/flowTemplates.spec.js` re-asserts the whole contract against every template in all three
languages: one Start, every edge on an output that exists, every required output connected, no unreachable node, no
loop without a wait, and WhatsApp's text, button and list limits.

A draft is only shape-checked when saved; the full validation runs at **publish**. That is why the spec matters more
than the save call.

## 2. `faq_menu` — the questions you answer every day

9 nodes, 13 edges. `start → list → send_message ×3 → buttons → send_message → end`, with a `handoff` on every exit
anybody might want a person for.

Decisions worth recording:

- **A `list`, not `buttons`.** WhatsApp allows three buttons and ten list rows
  (`node_validator.rb` `check_choices`). An FAQ menu that cannot grow past three options is not an FAQ menu. The
  list's `button_label` is its own short bilingual wording because of the 20-character cap.
- **The "another question" edge goes back to the same menu node**, not to a second copy of it. The loop is safe
  because both ends wait for the customer — `list` and `buttons` are both waiting nodes — which the spec asserts
  directly rather than relying on the generic no-cycle check.
- **Every answer is editable text.** Only the store knows its own delivery times, so each answer says so in both
  languages: "Edit this text to match your store."

## 3. `complaint_intake` — a complaint arrives sorted

7 nodes, 8 edges. `start → add_label → question → buttons → handoff ×3`.

Decisions worth recording:

- **Details first, then the category.** People describe a problem before they classify it. So the question comes
  before the three-way choice, and the choice rides the handoff — one handoff per category, each with its own note
  and the priority the user chose.
- **The label is applied before the question**, so somebody who stops replying still reaches a person with the
  complaint already labelled on the conversation. That is the `ask_details` timeout edge.
- **Labels travel as titles**, which is what `check_labels` matches on (`node_validator.rb`), and which is what the
  wizard's label picker produces.
- **One label set, not three.** Three label inputs would be a six-field wizard; the category is recorded in the
  handoff note and the priority instead. The durable record is the label, which is the point.

## 4. The defect this found

`handoff` is the template helper that builds a handoff node. It destructured `{ team, labels, reason }` — so a
template that passed a `priority` had it **silently dropped**. `complaint_intake` collects a priority, so the bug
would have shipped as "the priority field does nothing". Fixed in `recipes/flowTemplates.js`, with a spec that
asserts all three of that template's handoffs carry the chosen priority, because a silent drop is exactly the
failure a generic contract test does not catch.

## 5. What was not added, and why

- **Anything time-driven.** There is no business-hours or time-of-day node, and no clock anywhere in the engine
  (`01-starter-library-opportunity-study.md` §1). An "after hours" template cannot be built.
- **A lead-capture template.** `question` can store an answer to a contact attribute only when that attribute
  definition already exists (`check_attribute`), and storing to flow context puts the answers somewhere nobody
  reads. Without a destination the template would collect data and lose it.
- **A second commerce template.** The two that exist already cover order lookup, and both now carry a platform note
  (`16-commerce-aware-starters.md`).

## 6. Classification

EXTEND on the existing catalogue. No new node type, no runtime change, no new endpoint: a created template is an
ordinary `AgentBot(bot_type: flow)` with one unpublished draft version, published and edited exactly like a
hand-built flow.
