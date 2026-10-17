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

  # BY `display_id`, WHICH IS THE ONLY CAMPAIGN IDENTIFIER A CLIENT EVER HAS.
  #
  # `api/v1/models/_campaign.json.jbuilder` renders `json.id resource.display_id` and does
  # not render the primary key at all, so every client -- the dashboard's own analytics page
  # and the Store Syria campaigns page alike -- holds a display_id and calls it `id`. This
  # looked the campaign up by PRIMARY KEY, so for any account past its first campaign the
  # two numbers differ and the page showed a DIFFERENT campaign's delivery results under the
  # name of the one the merchant opened, or 404'd.
  #
  # The specs could not see it because they passed `campaign.id` -- an identifier the API
  # never hands out. Addressing by display_id also makes this consistent with every other
  # campaign route, all of which resolve through CampaignsController#campaign's
  # `find_by(display_id:)`.
  def fetch_campaign
    @campaign = Current.account.campaigns.find_by!(display_id: params[:campaign_id])
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

  # `to_s` first: a query string can carry any shape, and `?page[]=2` arrives as an array, on which `to_i` is not
  # defined. An unreadable page number is the first page, which is what the pager asks for when it has no state.
  def page
    [params[:page].to_s.to_i, 1].max
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
