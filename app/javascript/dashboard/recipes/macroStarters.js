// Macro starters (docs/product-enablement/17-macro-starters.md).
//
// Why macros are the right place to start a starter library: a macro has no trigger, no clock and no provider.
// An agent clicks it. That sidesteps every constraint the automation and flow catalogues live under, and macros
// are the one object an agent rather than an administrator can create (`MacroPolicy#create?` is unconditional).
//
// What a starter produces is an ordinary Macro created through the ordinary endpoint, with the ordinary policy
// and the ordinary validation. There is no macro runtime here and no second one anywhere.
//
// Three hard constraints from the server, each of which a template gets wrong by default:
//
//   1. `action_params` is ALWAYS a flat array of scalars. The controller permits `action_params: []`
//      (`app/controllers/api/v1/accounts/macros_controller.rb:61`), which silently drops a hash. A single-value
//      action is `[value]`.
//   2. `add_label` and `remove_label` take label TITLES, not ids (`app/services/action_service.rb:37-41`), which
//      is what the wizard's label picker already supplies.
//   3. Only the fifteen action types the builder knows are used. `change_status` is a sixteenth the server
//      accepts, but `MACRO_ACTION_TYPES` has no entry for it, so a macro carrying one cannot be edited
//      afterwards - and "you can edit it afterwards" is the whole promise of a starter.
//
// `send_attachment` is deliberately absent: its parameter is a signed ActiveStorage blob id for a file that has
// actually been uploaded, which a catalogue entry cannot have.

import { CATEGORIES, INPUT_TYPES, REQUIREMENTS } from './index';
import { body } from './starterCopy';

const PREFIX = 'RECIPES.MACRO';

// A private note is text the macro writes, not a key it looks up: `build` is pure and has no translator, and
// the note is stored on the macro as a literal string. So the wording lives here, written by hand in both
// languages like the flow templates' copy, and the agent edits it afterwards like any other macro.
const NOTES = {
  ESCALATED: {
    ar: 'تم تصعيد هذه المحادثة. يرجى المراجعة والرد.',
    en: 'This conversation has been escalated. Please review and reply.',
  },
  HANDED_TO_TEAM: {
    ar: 'أُحيلت هذه المحادثة إلى الفريق. يرجى متابعتها من هنا.',
    en: 'Handed to the team. Please pick this one up from here.',
  },
  STORE_ISSUE: {
    ar: 'سؤال يخص طلبًا أو متجرًا ويحتاج من يستطيع فتح المتجر.',
    en: 'An order or store question that needs someone who can open the store.',
  },
};

const action = (name, params = []) => ({
  action_name: name,
  action_params: params,
});

// `add_label` takes label titles, and always a list of them, which is the shape the wizard's label picker produces.
const labels = (key, required = true) => ({
  key,
  type: INPUT_TYPES.LABELS,
  required,
});
const team = (key, required = true) => ({
  key,
  type: INPUT_TYPES.TEAM,
  required,
});

const starter = ({ id, category, requires = [], inputs = [], build }) => ({
  id,
  type: 'macro',
  version: 1,
  name: `${PREFIX}.${id.toUpperCase()}.NAME`,
  description: `${PREFIX}.${id.toUpperCase()}.DESCRIPTION`,
  category,
  requires,
  inputs,
  build,
});

export const MACRO_STARTERS = [
  // Escalation is the single most repeated manual sequence in support, and every agent does it slightly
  // differently. Four actions, all channel-agnostic.
  starter({
    id: 'escalate_conversation',
    category: CATEGORIES.SUPPORT,
    requires: [REQUIREMENTS.TEAM, REQUIREMENTS.LABEL],
    inputs: [team('team'), labels('labels')],
    build: values => ({
      actions: [
        action('change_priority', ['high']),
        action('assign_team', [values.team]),
        action('add_label', values.labels),
        action('add_private_note', [body('both', NOTES.ESCALATED)]),
      ],
    }),
  }),

  // "This one is mine." `assign_agent` with the literal string 'self' is a macro-only sentinel the executor
  // swaps for the clicking agent (`app/services/macros/execution_service.rb:26`), so this starter needs no
  // account resource at all and works for an agent on their first day.
  starter({
    id: 'take_conversation',
    category: CATEGORIES.SUPPORT,
    requires: [],
    inputs: [],
    build: () => ({
      actions: [
        action('assign_agent', ['self']),
        action('change_priority', ['medium']),
      ],
    }),
  }),

  // Closing with a reason, so the resolved queue can be read afterwards. A label is the only way a resolution
  // reason is recorded anywhere.
  starter({
    id: 'resolve_with_reason',
    category: CATEGORIES.SUPPORT,
    requires: [REQUIREMENTS.LABEL],
    inputs: [labels('labels')],
    build: values => ({
      actions: [
        action('add_label', values.labels),
        action('resolve_conversation'),
      ],
    }),
  }),

  // Handing a conversation to the team that owns it, with the context the next person needs.
  starter({
    id: 'hand_to_team',
    category: CATEGORIES.SUPPORT,
    requires: [REQUIREMENTS.TEAM],
    inputs: [team('team')],
    build: values => ({
      actions: [
        action('assign_team', [values.team]),
        action('remove_assigned_agent'),
        action('add_private_note', [body('both', NOTES.HANDED_TO_TEAM)]),
      ],
    }),
  }),

  // Waiting on the customer. Snoozing without a label leaves no trace of why, which is why the two go together.
  starter({
    id: 'waiting_on_customer',
    category: CATEGORIES.OPERATIONS,
    requires: [REQUIREMENTS.LABEL],
    inputs: [labels('labels')],
    build: values => ({
      actions: [
        action('add_label', values.labels),
        action('snooze_conversation'),
      ],
    }),
  }),

  // An order question an agent cannot answer from the panel. Deliberately NOT a Commerce macro: a macro cannot
  // read or change an order - no commerce action exists in the macro allow-list and the executor's ancestry
  // carries none. What it can do is route the question to whoever can, which is the honest version.
  starter({
    id: 'store_issue_handoff',
    category: CATEGORIES.ECOMMERCE,
    requires: [REQUIREMENTS.TEAM, REQUIREMENTS.LABEL],
    inputs: [team('team'), labels('labels')],
    build: values => ({
      actions: [
        action('add_label', values.labels),
        action('change_priority', ['high']),
        action('assign_team', [values.team]),
        action('add_private_note', [body('both', NOTES.STORE_ISSUE)]),
      ],
    }),
  }),
];
