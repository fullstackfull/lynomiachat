# An account owns the named permission sets it defines
# (docs/p-final/clean-room/specs/C-account-role-permissions.md §4).
#
# `destroy_async` because there is no foreign key on `custom_roles.account_id`, so nothing else would remove
# them, and an account is deleted through DeleteObjectJob already.
module Custom::Concerns::Account
  extend ActiveSupport::Concern

  included do
    has_many :custom_roles, dependent: :destroy_async
  end
end
