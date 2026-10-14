# frozen_string_literal: true

# THE ACTIONS, WITH THE SHAPE OF WHAT EACH ONE TAKES.
#
# `actions_attributes` is a bare allow-list of names; what each one's `action_params` must contain lives in
# ActionService and AutomationRules::ActionService as the argument each method reads, and nowhere
# declaratively. A client therefore had to know, for instance, that change_priority takes a one-element array
# of a priority -- and the Phase 4A review found Lynomia's own dashboard carrying exactly that knowledge as a
# second copy in JavaScript, including an action the backend refuses.
#
# AN ACTION WITH NO `fields` ENTRY IS ONE THIS SCHEMA DOES NOT DESCRIBE, and a client should not offer it.
# That is deliberate rather than an omission to fill in later: an action whose parameters are a file upload,
# a webhook URL or an email body needs a surface of its own and an authorization story of its own, and
# offering a form for it that happens to post the right-shaped JSON is how a half-built action ships.
#
# `commerce_safe` IS THE RULE Custom::AutomationRule ALREADY ENFORCES, reported rather than restated: a
# Commerce trigger refuses a free-form customer message, because a store event is not a customer message and
# the channel window may well be shut. A client that offers one on a Commerce trigger offers a rule that
# cannot be saved.
module Automation::ActionFields
  FOR = {
    'add_label' => [{ key: 'labels', kind: 'labels', required: true }],
    'remove_label' => [{ key: 'labels', kind: 'labels', required: true }],
    'assign_agent' => [{ key: 'agent_id', kind: 'agent', required: true, wrapped: true }],
    'assign_team' => [{ key: 'team_id', kind: 'team', required: true, wrapped: true }],
    'remove_assigned_agent' => [],
    'remove_assigned_team' => [],
    'change_priority' => [{ key: 'priority', kind: 'select', required: true, wrapped: true,
                            values: %w[low medium high urgent nil] }],
    'mute_conversation' => [],
    'snooze_conversation' => [],
    'resolve_conversation' => [],
    'open_conversation' => [],
    'pending_conversation' => [],
    'add_private_note' => [{ key: 'note', kind: 'text', required: true, max: 10_000, wrapped: true }],
    'send_whatsapp_template' => [
      { key: 'inbox_id', kind: 'inbox', required: true },
      { key: 'name', kind: 'template', required: true },
      { key: 'language', kind: 'template_language', required: true },
      { key: 'params', kind: 'template_params' }
    ]
  }.freeze
end
