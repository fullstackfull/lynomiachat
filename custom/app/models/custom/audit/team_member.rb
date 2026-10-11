# B6 -- a member is added to or removed from a team (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# The browser reads `user_id` and `team_id` out of `audited_changes`
# (app/javascript/dashboard/helper/auditlogHelper.js:121-133), which a create and a destroy both carry.
module Custom::Audit::TeamMember
  extend ActiveSupport::Concern

  included do
    prepend Custom::Audit::Capture
    audited associated_with: :audited_account, on: [:create, :destroy]
  end

  def audited_account
    team&.account
  end
end
