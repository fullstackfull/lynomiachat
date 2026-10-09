class Api::V1::Accounts::Campaigns::AnalyticsController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  before_action :campaign
  before_action :authorize_campaign
  before_action :ensure_whatsapp_campaign_analytics_enabled!

  def metrics
    render json: delivery_metrics
  end

  def contacts
    recipients = filtered_recipients.includes(:contact).page(current_page).per(RESULTS_PER_PAGE)

    render json: {
      payload: recipients.map { |recipient| recipient_payload(recipient) },
      meta: {
        current_page: recipients.current_page,
        total_pages: recipients.total_pages,
        total_count: recipients.total_count
      }
    }
  end

  private

  def campaign
    @campaign ||= Current.account.campaigns.find_by!(display_id: params[:campaign_id])
  end

  def ensure_whatsapp_campaign_analytics_enabled!
    return if @campaign.one_off? && @campaign.inbox.inbox_type == 'Whatsapp' && Current.account.feature_enabled?(:whatsapp_campaign)

    raise Pundit::NotAuthorizedError
  end

  def authorize_campaign
    authorize @campaign, :show?
  end

  # Delivery and read come from the TIMESTAMP being present, not from status equality: the ladder keeps only the
  # furthest state reached, so a recipient Meta reported as read before it reported delivered carries `read_at`
  # with `delivered_at` still null until a later delivered event backfills it
  # (custom/app/models/campaign_recipient.rb:53-57). Reading `delivered_at` alone would therefore undercount.
  # `failed_at` is terminal because the writer refuses to fail a delivered or read recipient.
  #
  # `skipped` has no timestamp: Lynomia decided the contact was unsendable before attempting a send, so status is
  # the only record of it. `status_counts` stays exactly as it was -- it is the raw ladder, and the dashboard's
  # per-status recipient list is driven by it.
  def delivery_metrics
    recipients = @campaign.campaign_recipients
    counts = recipients.group(:status).count

    {
      audience: recipients.count,
      sent: recipients.where.not(source_id: nil).count,
      delivered: recipients.where(Analytics::Campaigns::Metrics::DELIVERED_SQL).count,
      read: recipients.where.not(read_at: nil).count,
      failed: recipients.where.not(failed_at: nil).count,
      skipped: counts['skipped'].to_i,
      status_counts: CampaignRecipient.statuses.keys.index_with { |status| counts[status].to_i }
    }
  end

  def filtered_recipients
    return recipients unless CampaignRecipient.statuses.key?(params[:status])

    recipients.where(status: params[:status])
  end

  def recipients
    @recipients ||= @campaign.campaign_recipients.order(created_at: :desc)
  end

  def recipient_payload(recipient)
    {
      contact: {
        id: recipient.contact.id,
        name: recipient.contact.name,
        phone_number: recipient.contact.phone_number
      },
      status: recipient.status,
      message_content: recipient.message_content,
      error_code: recipient.error_code,
      error_title: recipient.error_title,
      error_message: recipient.error_message
    }
  end

  def current_page
    params[:page].presence || 1
  end
end
