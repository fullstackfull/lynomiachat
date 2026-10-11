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

  # A membership holding a set is an agent. The edit page offers the two built-in roles and the account's sets in
  # one selector and sends only `custom_role_id` when a set is chosen
  # (app/javascript/dashboard/routes/dashboard/settings/agents/EditAgent.vue:131-136), so without this an
  # administrator moved to a set would keep `role = administrator`: every administrator endpoint still open to
  # them -- including the one that defines the set meant to narrow them -- while the page displays them as
  # holding it. The invite path already lands on `agent`, because upstream's builder drops a nil role and the
  # column defaults (app/builders/agent_builder.rb:79-83); this makes the edit path agree.
  #
  # The rest of the product already assumes the invariant: the one server reader of a set's capabilities counts
  # only a membership that is both an agent and holds a set
  # (app/services/conversations/unread_counts/counter.rb:170-172).
  def apply_custom_role(account_user)
    return if account_user.blank?
    return unless custom_role_requested?

    attributes = { custom_role_id: requested_custom_role_id }
    attributes[:role] = :agent if requested_custom_role_id.present?
    account_user.update!(attributes)
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
  #
  # Asking for `administrator` and a set in the same request is a contradiction rather than an ambiguity -- the
  # set would be inert -- so it is refused here instead of being resolved silently in either direction.
  def validate_custom_role
    return unless custom_role_requested?

    id = params[:agent][:custom_role_id]
    return if id.blank?
    return render_could_not_create_error(I18n.t('errors.custom_roles.administrator_conflict')) if administrator_requested?

    @requested_custom_role = Current.account.custom_roles.find_by(id: id)
    render_not_found_error(I18n.t('errors.custom_roles.not_found')) if @requested_custom_role.blank?
  end

  def administrator_requested?
    params[:agent][:role].to_s == 'administrator'
  end
end
