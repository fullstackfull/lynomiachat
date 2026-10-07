# Lynomia keeps Chatwoot's audit coverage of a webhook after the Enterprise overlay goes: the same declaration,
# included at the same site (app/models/webhook.rb:46), writing to the same `audits` table through Custom::AuditLog.
module Custom::Audit::Webhook
  extend ActiveSupport::Concern

  included do
    audited associated_with: :account, except: [:secret]
  end
end
