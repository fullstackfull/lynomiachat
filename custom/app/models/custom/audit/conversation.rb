# B12 -- a conversation is removed (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# Only the destroy: a conversation changes constantly in the normal course of work -- assignee, status, last
# activity -- and none of that is a configuration change an administrator reads the trail for.
#
# `display_id` is the number the product shows and the number a person recognises; the browser prefers it over
# the internal id (app/javascript/dashboard/helper/auditlogHelper.js:181-184). The columns are named explicitly
# so that `additional_attributes` and `custom_attributes`, which hold whatever a widget or an integration wrote
# about the customer, do not end up on a trail that is rendered in a browser.
module Custom::Audit::Conversation
  extend ActiveSupport::Concern

  included do
    prepend Custom::Audit::Capture
    audited associated_with: :account, on: [:destroy], only: %i[display_id inbox_id contact_id assignee_id team_id status]
  end
end
