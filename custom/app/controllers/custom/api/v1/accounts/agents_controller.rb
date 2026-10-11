# Attaching a named permission set to a membership
# (docs/p-final/clean-room/specs/C-account-role-permissions.md §2, §4).
#
# Attachment happens on the agent endpoints rather than on the role endpoints, which is what the shipped pages
# already do: both send the set's id under `custom_role_id`, and the edit page sends an explicit `null` to
# detach (app/javascript/dashboard/routes/dashboard/settings/agents/{AddAgent,EditAgent}.vue).
#
# Two things upstream cannot do on its own, and both of them matter:
#
# **The set must belong to the asking account.** Nothing in the schema enforces it -- there is no foreign key
# on `account_users.custom_role_id` -- so account A could otherwise attach account B's set to its own member
# and silently inherit whatever B's administrator put in it. The id is resolved inside
# `Current.account.custom_roles` and an id from elsewhere is simply not found.
#
# **A detachment must survive the update.** Upstream applies the membership's attributes with `.compact`
# (app/controllers/api/v1/accounts/agents_controller.rb:27), which drops a nil, so an explicit `null` would be
# silently ignored and the set would stay attached. The attachment is therefore applied here, where nil means
# nil.
module Custom::Api::V1::Accounts::AgentsController
  def self.prepended(base)
    base.class_eval do
      before_action :validate_custom_role, only: [:create, :update]
    end
  end

  # `@agent` is nil when upstream refused the invite on the plan's agent limit, in which case there is no
  # membership to attach anything to.
  def create
    super
    apply_custom_role(Current.account.account_users.find_by(user_id: @agent.id)) if @agent.present?
  end

  def update
    super
    apply_custom_role(@agent.current_account_user)
  end

  private

  def apply_custom_role(account_user)
    return if account_user.blank?
    return unless custom_role_requested?

    account_user.update!(custom_role_id: requested_custom_role_id)
  end

  # `key?` rather than a presence check: an agent update that says nothing about the set must leave it alone,
  # while one that says `null` must remove it.
  def custom_role_requested?
    params[:agent].is_a?(ActionController::Parameters) && params[:agent].key?(:custom_role_id)
  end

  def requested_custom_role_id
    @requested_custom_role&.id
  end

  # 404 rather than 403: a 403 would confirm that the id exists in some other account (package C §2).
  def validate_custom_role
    return unless custom_role_requested?

    id = params[:agent][:custom_role_id]
    return if id.blank?

    @requested_custom_role = Current.account.custom_roles.find_by(id: id)
    render_not_found_error(I18n.t('errors.custom_roles.not_found')) if @requested_custom_role.blank?
  end
end
