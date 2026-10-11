# What one campaign actually did, per contact (docs/p-final/clean-room/specs/D-campaign-recipient-outcomes.md §2).
#
# Two routes, both already declared and both deliberately not feature-gated (config/routes.rb:104-105): a
# campaign that has run has results, and whether the account may still create new WhatsApp campaigns is a
# separate question from whether it may read what the last one did.
#
# Authorization is the campaign's own. Reading a campaign's results must not be a wider permission than reading
# the campaign, so this inherits CampaignPolicy rather than adding a boundary of its own -- and the campaign is
# looked up inside `Current.account.campaigns`, so an id from another account is not found rather than refused.
class Api::V1::Accounts::Campaigns::AnalyticsController < Api::V1::Accounts::BaseController
  DELIVERIES_PER_PAGE = 25

  before_action :fetch_campaign
  before_action :validate_status_filter, only: [:contacts]

  def metrics
    render json: Campaigns::RecipientMetrics.new(@campaign).as_json
  end

  def contacts
    @recipients = recipients.page(page).per(DELIVERIES_PER_PAGE)
  end

  private

  def fetch_campaign
    @campaign = Current.account.campaigns.find(params[:campaign_id])
    authorize @campaign, :show?
  end

  # `includes(:contact)` rather than a per-row lookup: the list renders the contact's name and number on every
  # row, and the query count must not grow with the page.
  def recipients
    scope = CampaignRecipient.where(account_id: Current.account.id, campaign_id: @campaign.id)
                             .includes(:contact)
                             .order(created_at: :asc, id: :asc)
    params[:status].present? ? scope.where(status: params[:status]) : scope
  end

  def page
    [params[:page].to_i, 1].max
  end

  # Refused at the boundary rather than passed to the database as an unknown state, which is the repo's
  # convention for an invalid parameter (CLAUDE.md) and keeps a typo out of the exception tracker.
  def validate_status_filter
    return if params[:status].blank?
    return if CampaignRecipient.statuses.key?(params[:status].to_s)

    render_could_not_create_error(
      I18n.t('errors.campaigns.unknown_recipient_status',
             status: params[:status], allowed: CampaignRecipient.statuses.keys.join(', '))
    )
  end
end
