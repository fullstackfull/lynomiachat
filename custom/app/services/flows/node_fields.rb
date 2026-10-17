# The SHAPE of each node type's `data`, for a builder to render a configuration form from.
#
# WHY THIS EXISTS. Flows::NodeTypes says WHICH keys a node type has; Flows::NodeValidator says what each one may
# CONTAIN, and until now that was knowable only by reading its Ruby. A builder therefore had to carry its own copy
# of "reply_type is one of these five", "a button title is at most 20 characters", "max_attempts is 1 to 5" -- and
# the Phase 4A capability review named exactly this as the drift that offers a merchant a field the server will
# reject. Served, there is one answer and the client cannot hold a stale one.
#
# EVERY LIMIT IS READ FROM THE VALIDATOR'S OWN CONSTANT, never written out again here. If
# Flows::NodeValidator::REPLY_TYPES gains a value or ChannelCapabilities::WHATSAPP changes a ceiling, this moves
# with it in the same deploy. That is the whole point: a second copy of a number is a number that will disagree.
#
# NO HUMAN TEXT. No label, no hint, no placeholder -- structure only. The words belong to the client, in the
# merchant's own language, which is also the rule that keeps Lynomia's English out of an Arabic interface.
#
# KINDS, and what a client is expected to render for each:
#   text            a message body. `max`, `variables` -- a variable picker belongs here
#   line            one line. `max`, `variables`
#   number          `min`, `max`, `default`
#   boolean         a tri-state: unset, yes, no (`end.resolve` is nil / true / false)
#   select          one of `values`, `default`
#   words           a list of short strings. `max_items`, `max_length`
#   options         the choices of a Buttons or List node. `max_items`, `title_max`, `description_max`
#                   (`description_max` 0 means the channel has no description -- do not offer the field)
#   conditions      Lynomia Automation conditions. `max_items`, `scope`
#   labels          this account's labels. `max_items`
#   agent / team    one of this account's members / teams
#   attribute       a custom attribute key of `model`
#   store_target    where a Question keeps the answer: a contact or conversation attribute, or a run value
#   node            another node of this same graph
#   template        a WhatsApp template; the flow's own sendable templates are served alongside the graph
#   template_language / template_params   set by the template picker, not edited on their own
#   url             an http(s) address. `max`
#
# `required_when` / `shown_when` are the two conditional rules the validator actually applies -- a Question's
# keywords matter only for a keyword reply, and a Commerce lookup's number only when it is looking one up by
# number. They are named here rather than inferred, because a client guessing at them shows a required field that
# is not and hides one that is.
module Flows::NodeFields
  CAPS = Flows::ChannelCapabilities::WHATSAPP
  V = Flows::NodeValidator

  FOR = {
    'start' => [
      { key: 'keywords', kind: 'words', max_items: 20, max_length: 64 },
      { key: 'conditions', kind: 'conditions', max_items: V::MAX_CONDITIONS, scope: 'any' }
    ],
    'send_message' => [
      { key: 'text', kind: 'text', required: true, max: CAPS[:text][:body], variables: 'all' }
    ],
    'send_template' => [
      { key: 'name', kind: 'template', required: true },
      { key: 'language', kind: 'template_language', required: true },
      { key: 'params', kind: 'template_params' }
    ],
    'question' => [
      { key: 'text', kind: 'text', required: true, max: CAPS[:text][:body], variables: 'all' },
      { key: 'reply_type', kind: 'select', values: V::REPLY_TYPES, default: 'any' },
      { key: 'keywords', kind: 'words', max_items: 20, max_length: 64,
        required_when: { key: 'reply_type', value: 'keywords' } },
      { key: 'store_as', kind: 'store_target' },
      { key: 'max_attempts', kind: 'number', min: 1, max: 5, default: 3 },
      { key: 'retry_text', kind: 'text', max: CAPS[:text][:body], variables: 'all' },
      { key: 'timeout_minutes', kind: 'number', min: 1, max: V::MAX_TIMEOUT_MINUTES }
    ],
    'buttons' => [
      { key: 'text', kind: 'text', required: true, max: CAPS[:buttons][:body], variables: 'all' },
      { key: 'options', kind: 'options', required: true, max_items: CAPS[:buttons][:max],
        title_max: CAPS[:buttons][:title], description_max: CAPS[:buttons][:description].to_i },
      { key: 'timeout_minutes', kind: 'number', min: 1, max: V::MAX_TIMEOUT_MINUTES }
    ],
    'list' => [
      { key: 'text', kind: 'text', required: true, max: CAPS[:list][:body], variables: 'all' },
      { key: 'button_label', kind: 'line', max: CAPS[:list][:button] },
      { key: 'options', kind: 'options', required: true, max_items: CAPS[:list][:max],
        title_max: CAPS[:list][:title], description_max: CAPS[:list][:description].to_i },
      { key: 'timeout_minutes', kind: 'number', min: 1, max: V::MAX_TIMEOUT_MINUTES }
    ],
    'condition' => [
      { key: 'conditions', kind: 'conditions', required: true, max_items: V::MAX_CONDITIONS, scope: 'any' }
    ],
    'audience_condition' => [
      { key: 'conditions', kind: 'conditions', required: true, max_items: V::MAX_CONDITIONS, scope: 'contact_audience' }
    ],
    'commerce_condition' => [
      { key: 'conditions', kind: 'conditions', required: true, max_items: V::MAX_CONDITIONS, scope: 'commerce' }
    ],
    'set_contact_attribute' => [
      { key: 'key', kind: 'attribute', model: 'contact_attribute', required: true },
      { key: 'value', kind: 'line', required: true, max: 1024, variables: 'flow' }
    ],
    'set_conversation_attribute' => [
      { key: 'key', kind: 'attribute', model: 'conversation_attribute', required: true },
      { key: 'value', kind: 'line', required: true, max: 1024, variables: 'flow' }
    ],
    'add_label' => [{ key: 'labels', kind: 'labels', required: true, max_items: 10 }],
    'remove_label' => [{ key: 'labels', kind: 'labels', required: true, max_items: 10 }],
    'assign_agent' => [{ key: 'agent_id', kind: 'agent', required: true }],
    'assign_team' => [{ key: 'team_id', kind: 'team', required: true }],
    'commerce_lookup' => [
      { key: 'mode', kind: 'select', required: true, values: V::LOOKUP_MODES },
      { key: 'number', kind: 'line', max: 64, variables: 'flow',
        shown_when: { key: 'mode', value: 'order_number' } }
    ],
    'webhook' => [{ key: 'url', kind: 'url', required: true, max: Limits::URL_LENGTH_LIMIT }],
    'delay' => [{ key: 'seconds', kind: 'number', required: true, min: 1, max: V::MAX_DELAY_SECONDS }],
    'handoff' => [
      { key: 'team_id', kind: 'team' },
      { key: 'agent_id', kind: 'agent' },
      { key: 'priority', kind: 'select', values: V::PRIORITIES },
      { key: 'labels', kind: 'labels', max_items: 10 },
      { key: 'reason', kind: 'line', max: 255 }
    ],
    'goto' => [{ key: 'target', kind: 'node', required: true }],
    'end' => [{ key: 'resolve', kind: 'boolean' }]
  }.freeze

  # The scopes a store_target may use, which the validator reads out of its own STORE_MODELS plus the run's
  # context. Served so the client's picker cannot offer a fourth.
  STORE_SCOPES = (V::STORE_MODELS.keys + ['context']).freeze
end
