# Lynomia shared audiences (docs/automation/02-shared-audiences.md) on Chatwoot's saved filters API. Members list and
# open their own filters plus the account's shared contact filters; only administrators share a filter or change or
# delete a shared one; a shared audience that automation rules or campaigns still to send reference cannot be deleted or
# made personal.
module Custom::Api::V1::Accounts::CustomFiltersController
  def create
    raise Pundit::NotAuthorizedError if sharing_requested? && !Current.account_user.administrator?

    super
  end

  def update
    raise Pundit::NotAuthorizedError if (@custom_filter.shared? || sharing_requested?) && !Current.account_user.administrator?
    return render_in_use if @custom_filter.shared? && params.dig(:custom_filter, :shared).to_s == 'false' && in_use?

    super
  end

  def destroy
    raise Pundit::NotAuthorizedError if @custom_filter.shared? && !Current.account_user.administrator?
    return render_in_use if @custom_filter.shared? && in_use?

    super
  end

  private

  def fetch_custom_filters
    @custom_filters = Current.account.custom_filters.visible_to(Current.user)
                             .where(filter_type: permitted_params[:filter_type] || self.class::DEFAULT_FILTER_TYPE)
  end

  def fetch_custom_filter
    @custom_filter = Current.account.custom_filters.visible_to(Current.user).find(permitted_params[:id])
  end

  def permitted_payload
    params.require(:custom_filter).permit(:name, :filter_type, :shared, query: {})
  end

  def sharing_requested?
    params.dig(:custom_filter, :shared).to_s == 'true'
  end

  def in_use?
    @rules_in_use = Audience::Usage.rules(@custom_filter).size
    @campaigns_in_use = Audience::Usage.campaigns(@custom_filter).count
    (@rules_in_use + @campaigns_in_use).positive?
  end

  def render_in_use
    messages = []
    messages << I18n.t('errors.custom_filters.used_by_automation', count: @rules_in_use) if @rules_in_use.positive?
    messages << I18n.t('errors.custom_filters.used_by_campaigns', count: @campaigns_in_use) if @campaigns_in_use.positive?
    render_could_not_create_error(messages.join(' '))
  end
end
