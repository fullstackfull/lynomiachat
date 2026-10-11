# B8 -- a macro is created, changed or removed (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# `actions` is left out for the same reason as an automation rule's: it is an unbounded document that can carry
# a message body, and the trail needs the macro's identity and who may use it.
module Custom::Audit::Macro
  extend ActiveSupport::Concern

  included do
    prepend Custom::Audit::Capture
    audited associated_with: :account, on: [:create, :update, :destroy],
            only: %i[name visibility created_by_id updated_by_id]
  end
end
