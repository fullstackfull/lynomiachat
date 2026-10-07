# Lynomia keeps Chatwoot's audit coverage of an account after the Enterprise overlay goes: the same declaration,
# included at the same site (app/models/account.rb:243), writing to the same `audits` table through Custom::AuditLog.
module Custom::Audit::Account
  extend ActiveSupport::Concern

  included do
    audited except: :updated_at, on: [:update]
    has_associated_audits
  end
end
