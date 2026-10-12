# B7 -- an automation rule is created, changed or removed
# (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# `conditions` and `actions` are left out on purpose. They are unbounded jsonb documents that can carry a
# message template, and a rule's identity plus whether it is live is what a reader of the trail is asking about.
# Package B §6: the context is reduced to identifying fields rather than stored wholesale.
module Custom::Audit::AutomationRule
  extend ActiveSupport::Concern

  included do
    prepend Custom::Audit::Capture
    audited associated_with: :account, on: [:create, :update, :destroy],
            only: %i[name description event_name active execution_delay]
  end
end
