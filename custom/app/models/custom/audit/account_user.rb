# Lynomia keeps Chatwoot's audit coverage of an account membership after the Enterprise overlay goes: the same declaration,
# included at the same site (app/models/account_user.rb:103), writing to the same `audits` table through Custom::AuditLog.
module Custom::Audit::AccountUser
  extend ActiveSupport::Concern

  included do
    audited only: [:availability, :role, :account_id, :inviter_id, :user_id], on: [:create, :update], associated_with: :account
  end
end
