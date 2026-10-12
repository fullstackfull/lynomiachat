# B5 -- a team is created, changed or removed (docs/p-final/clean-room/specs/B-audit-event-capture.md).
module Custom::Audit::Team
  extend ActiveSupport::Concern

  included do
    prepend Custom::Audit::Capture
    audited associated_with: :account, on: [:create, :update, :destroy]
  end
end
