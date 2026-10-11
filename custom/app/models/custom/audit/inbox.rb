# B3 -- an inbox is created, changed or removed (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# Every column of `inboxes` is operator-facing configuration, so all of them are audited and the gem's own
# ignore list keeps the timestamps out. A channel's configuration change arrives here too, as an inbox update,
# through Custom::Channelable: that is where the credentials are excluded.
module Custom::Audit::Inbox
  extend ActiveSupport::Concern

  included do
    prepend Custom::Audit::Capture
    audited associated_with: :account, on: [:create, :update, :destroy]
  end
end
