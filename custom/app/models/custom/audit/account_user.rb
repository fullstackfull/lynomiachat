# B2 -- a membership is created or changed (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# The browser tells a self-edit from an edit of somebody else by comparing the row's actor with the membership's
# own user (app/javascript/dashboard/helper/auditlogHelper.js:218), and reads the old and new role and
# availability out of `audited_changes`, so those three columns are the ones that have to be here.
#
# `custom_role_id` is audited too: attaching or detaching a named permission set changes what a person can do,
# which is exactly the kind of change the trail exists to explain. `active_at` is not -- it moves on every
# request and would bury everything else.
module Custom::Audit::AccountUser
  extend ActiveSupport::Concern

  included do
    prepend Custom::Audit::Capture
    audited associated_with: :account, on: [:create, :update], only: %i[user_id role availability auto_offline custom_role_id]
  end
end
