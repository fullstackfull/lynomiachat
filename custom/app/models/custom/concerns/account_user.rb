# Lynomia: a membership may hold one custom role (custom/app/models/custom_role.rb).
module Custom::Concerns::AccountUser
  extend ActiveSupport::Concern

  included do
    belongs_to :custom_role, optional: true
  end
end
