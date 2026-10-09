# SLA policies for support cases (docs/p9/03-sla-workflow.md).
#
# Stored in the `sla_policies` table that already ships in the OSS schema and has never held a row in this fork.
# Deliberately NOT served at `/api/v1/accounts/:id/sla_policies`, which is the path the surviving (and currently
# unreachable) conversation-SLA frontend expects: claiming that path would make a dormant conversation UI appear
# to work against case-shaped data. It lives under /support/ so the namespace says what the rows are for.
#
# Configuring SLA targets is an account-wide setting, so it follows the administrator boundary rather than the
# per-case one.
class Api::V1::Accounts::Support::SlaPoliciesController < Api::V1::Accounts::Support::BaseController
  before_action :check_admin_authorization?
  before_action :fetch_policy, only: [:show, :update, :destroy]

  def index
    @sla_policies = Current.account.sla_policies.order(:name)
  end

  def show; end

  def create
    @sla_policy = Current.account.sla_policies.create!(policy_params)
    render :show, status: :created
  end

  def update
    @sla_policy.update!(policy_params)
    render :show
  end

  # Nullifies the link on every case that used it -- `has_many … dependent: :nullify` on the model -- so deleting
  # a policy cannot take a case's history with it. The due times already computed stay as they are: they were a
  # commitment made when the policy was attached, and silently clearing them would rewrite the past.
  def destroy
    @sla_policy.destroy!
    head :no_content
  end

  private

  def fetch_policy
    @sla_policy = Current.account.sla_policies.find(params[:id])
  end

  def policy_params
    params.require(:sla_policy).permit(:name, :description, :first_response_time_threshold,
                                       :resolution_time_threshold, :only_during_business_hours)
  end
end
