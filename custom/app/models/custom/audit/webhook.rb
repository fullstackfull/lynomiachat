# B9 -- a webhook is created, changed or removed (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# `webhooks.secret` is the signing secret Lynomia uses to prove a delivery came from it, so it is excluded by
# construction here as well as by Custom::AuditLog's own rule. The url, the events subscribed to and the inbox
# are the operator's own configuration and are what the trail is for.
module Custom::Audit::Webhook
  extend ActiveSupport::Concern

  included do
    prepend Custom::Audit::Capture
    audited associated_with: :account, on: [:create, :update, :destroy],
            only: %i[name url inbox_id webhook_type subscriptions]
  end
end
