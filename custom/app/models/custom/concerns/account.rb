# Lynomia: an account owns the custom roles it defines (custom/app/models/custom_role.rb).
module Custom::Concerns::Account
  extend ActiveSupport::Concern

  included do
    has_many :custom_roles, dependent: :destroy_async
  end
end
