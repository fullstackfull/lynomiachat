# Macro starters

Phase P2, Part B. Six starters, and the first starter gallery an agent rather than an administrator can reach.

---

## 1. Why macros first

`01-starter-library-opportunity-study.md` §1 named a macro starter pack the highest-value, lowest-risk unlock in the
whole library, for three reasons that still hold:

- **A macro has no trigger, no clock and no provider.** An agent clicks it. That sidesteps every constraint the
  automation and flow catalogues live under.
- **It is the one object an agent can create.** `MacroPolicy#create?` is unconditionally `true`; the flow and
  automation galleries are administrator-only routes.
- **The recipe architecture could not express one**, which is a small, contained EXTEND: a new catalogue array and a
  `type: 'macro'`, nothing else.

## 2. The three server constraints a template gets wrong by default

1. **`action_params` is always a flat array of scalars.** The controller permits `action_params: []`
   (`app/controllers/api/v1/accounts/macros_controller.rb:61`), which silently **drops a hash**. A single-value
   action is `[value]`. The automation-only `send_email_to_team` shape cannot be expressed in a macro at all.
2. **`add_label` and `remove_label` take label titles**, not ids (`app/services/action_service.rb:37-41`) — which is
   what the wizard's label picker already produces.
3. **Only the fifteen action types the builder knows are used.** `change_status` is a sixteenth the server accepts
   (`app/models/macro.rb:33-35`) but `MACRO_ACTION_TYPES` has no entry for it, so a macro carrying one cannot be
   edited afterwards — and "you can edit it afterwards" is the whole promise of a starter.

`send_attachment` is deliberately absent: its parameter is a signed ActiveStorage blob id for a file that has
actually been uploaded, which a catalogue entry cannot have.

`recipes/specs/macroStarters.spec.js` asserts all of this against every starter: every action is in the server
allow-list, every parameter is a scalar, only builder-known types are used, every account resource is declared as an
input, and no literal id is embedded.

## 3. The six

| id | What it does | Needs |
|---|---|---|
| `escalate_conversation` | priority high, assign a team, label, private note | a team, a label |
| `take_conversation` | assign to the clicking agent, priority medium | **nothing** |
| `resolve_with_reason` | label, then resolve | a label |
| `hand_to_team` | assign a team, unassign the agent, private note | a team |
| `waiting_on_customer` | label, then snooze | a label |
| `store_issue_handoff` | label, priority high, assign a team, private note | a team, a label |

`take_conversation` is the one an agent can use on their first day: `assign_agent` with the literal string `'self'`
is a macro-only sentinel the executor swaps for the clicking agent
(`app/services/macros/execution_service.rb:25-28`), so the starter needs no account resource at all.

`store_issue_handoff` is deliberately **not** a commerce macro. A macro cannot read or change an order: no commerce
action exists in the allow-list and the macro executor's ancestry carries none — the one commerce-aware override in
the repo is prepended onto `AutomationRules::ActionService`, a sibling class, and macros run their own
`send_webhook_event`. What a macro can do is route the question to whoever can open the store, which is the honest
version.

## 4. Visibility

`Macro#set_visibility` forces `:personal` for an agent whatever was asked for, and does it by **overwriting, not
rejecting** — an agent posting `visibility: 'global'` gets a 200 and a personal macro, with no 422 and no warning.
So the page sends `global` for an administrator and `personal` otherwise, rather than sending `global` and letting
the server quietly disagree.

## 5. The entry point

The macros index creates on a separate page (`macros_new` → `MacroEditor.vue`), not in a dialog like automation and
flows. So "start from nothing" is a router push and the from-scratch control is the unchanged `router-link` it
always was — Part M parity. "Start from a starter" sits beside it and in the empty state, and after creating, the
page opens the editor on the result, because a starter is a starting point.

## 6. A defect this found

`INPUT_TYPES.LABEL` was declared in the recipe contract but **nothing rendered it**: `RecipeInputs` handles `LABELS`
and falls through to a URL field for anything else, so a macro starter asking for one label offered the user a URL
box. Every label action takes a list of titles, so `LABELS` is the only shape needed; `LABEL` is gone, and
`components-next/recipes/specs/RecipeInputs.spec.js` now asserts that every value in `INPUT_TYPES` renders as
something other than the URL fallback — the guard that would have caught it.

## 7. Classification

EXTEND. A starter produces an ordinary `Macro` through the ordinary endpoint, with the ordinary policy, the ordinary
validation and the ordinary visibility rule. There is no macro runtime here and no second one anywhere.
