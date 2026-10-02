# Lynomia shared audiences (docs/automation/02-shared-audiences.md): a deleted user's shared contact filters stay with
# the account. Runs before `has_many :custom_filters, dependent: :destroy_async` collects the user's filters.
module Custom::Concerns::User
  extend ActiveSupport::Concern

  included do
    before_destroy :release_shared_audiences, prepend: true
  end

  private

  def release_shared_audiences
    custom_filters.where(shared: true).update_all(user_id: nil) # rubocop:disable Rails/SkipsModelValidations
  end
end
