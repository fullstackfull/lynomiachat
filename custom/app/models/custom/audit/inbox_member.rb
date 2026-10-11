# B4 -- a member is added to or removed from an inbox (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# `inbox&.account`, with the safe operator, because the destroy of an inbox membership can run after the inbox
# itself is gone and a capture point must never be the thing that raises.
module Custom::Audit::InboxMember
  extend ActiveSupport::Concern

  included do
    prepend Custom::Audit::Capture
    audited associated_with: :audited_account, on: [:create, :destroy]
  end

  def audited_account
    inbox&.account
  end
end
