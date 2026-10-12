# A membership may hold one named permission set
# (docs/p-final/clean-room/specs/C-account-role-permissions.md §4).
#
# Optional, because almost no membership has one and a membership without one must behave exactly as an agent
# does today. The column already exists and OSS code already reads it
# (app/views/api/v1/models/_agent.json.jbuilder:14, app/models/account_user.rb:86).
#
# Nothing validates that the role belongs to the membership's own account here: the request boundary is where
# that is decided, because it is the only place that knows which account is asking
# (custom/app/controllers/custom/api/v1/accounts/agents_controller.rb).
module Custom::Concerns::AccountUser
  extend ActiveSupport::Concern

  included do
    belongs_to :custom_role, optional: true
  end
end
