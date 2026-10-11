# An account's named permission sets (docs/p-final/clean-room/specs/C-account-role-permissions.md §2).
#
# Administrator-only on all five actions, and that is the principal security property of the package: a
# capability must never let its holder create, change, attach or delete a set, or any granted agent could grant
# themselves anything. Holding every capability the product defines still does not open this controller.
#
# Every lookup goes through `Current.account.custom_roles`, so a set belonging to another account is not found
# rather than refused -- a 404 rather than a 403, because a 403 confirms that the id exists (package C §2).
#
# The capability is checked at the boundary too. The client already renders a plan notice instead of the page
# (app/javascript/dashboard/routes/dashboard/settings/customRoles/component/CustomRolePaywall.vue), and client
# gating is not authorization, so the server says the same thing to a direct API call.
class Api::V1::Accounts::CustomRolesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :ensure_capability
  before_action :fetch_custom_role, only: [:show, :update, :destroy]

  def index
    @custom_roles = Current.account.custom_roles.order(:name)
  end

  def show; end

  def create
    @custom_role = Current.account.custom_roles.create!(custom_role_params)
    render :show, status: :created
  end

  def update
    @custom_role.update!(custom_role_params)
    render :show
  end

  # The memberships holding this set keep everything except the set: `has_many :account_users,
  # dependent: :nullify` on the model detaches them, and each reverts to its built-in role's capabilities.
  def destroy
    @custom_role.destroy!
    head :ok
  end

  private

  def fetch_custom_role
    @custom_role = Current.account.custom_roles.find(params[:id])
  end

  # The same refusal every other Lynomia capability uses when an account does not have it
  # (custom/app/controllers/api/v1/accounts/flows_controller.rb:81 and the Commerce controllers), so one answer
  # means one thing across the product. The flag itself is resolved by P11's entitlement sync; this package
  # deliberately adds no second entitlement path of its own (package C §9).
  def ensure_capability
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('custom_roles')
  end

  def custom_role_params
    params.require(:custom_role).permit(:name, :description, permissions: [])
  end
end
