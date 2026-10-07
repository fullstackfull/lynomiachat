# Lynomia Audience: a saved contact segment (an audience) is recorded in the audit log when it is created, changed or
# deleted (docs/audience/04-security-and-tenancy.md). Conversation folders and report filters stay unaudited, as in
# Chatwoot. Membership is never audited: it is evaluated, not stored.
module Custom::Audit::CustomFilter
  extend ActiveSupport::Concern

  included do
    audited associated_with: :account, if: :contact?
  end
end
