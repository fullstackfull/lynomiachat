# Lynomia Analytics: one-off WhatsApp campaign performance across campaigns
# (docs/p8/02b-whatsapp-campaign-analytics.md).
#
# `campaign_recipients` is both the audience snapshot and the funnel: one row per contact a campaign addressed,
# written when the campaign runs and advanced only forwards by #update_from_whatsapp_status! under a row lock
# (custom/app/models/campaign_recipient.rb). There is no separate execution engine and no second store, so every
# number here comes off that one table.
#
# Delivery and read are counted from the TIMESTAMP being present, never from status equality, because the ladder
# keeps only the furthest state reached. The literal single-column form -- `delivered_at IS NOT NULL` alone --
# would be wrong: when Meta sends `read` before `delivered`, the writer sets status `read` and `read_at` and
# leaves `delivered_at` null until a later `delivered` event backfills it
# (custom/app/models/campaign_recipient.rb:53-57). A recipient that was read therefore reached delivered whether
# or not `delivered_at` arrived, so delivered is `delivered_at IS NOT NULL OR read_at IS NOT NULL`.
#
# `failed` is safe to read from `failed_at`: the writer refuses to mark a delivered or read recipient failed
# (custom/app/models/campaign_recipient.rb:70-72), so the timestamp is terminal once set.
#
# `skipped` has no timestamp column. Lynomia decided the contact was unsendable before any send was attempted
# (`mark_skipped!`), so status is the only record of it, and that is what is read.
class Analytics::Campaigns::Metrics
  DELIVERED_SQL = 'campaign_recipients.delivered_at IS NOT NULL OR campaign_recipients.read_at IS NOT NULL'.freeze

  COUNT_METRICS = %i[campaigns_run recipients_targeted sent delivered read failed skipped pending].freeze
  RATE_METRICS = %i[delivery_rate read_rate failure_rate].freeze
  EVENT_METRICS = (COUNT_METRICS + RATE_METRICS).freeze

  AUDIENCE_TYPES = %w[Label Audience].freeze

  def initialize(account:, date_range:, filters:)
    @account = account
    @date_range = date_range
    @filters = filters
  end

  def campaigns_run
    recipients.distinct.count(:campaign_id)
  end

  def recipients_targeted
    @recipients_targeted ||= recipients.count
  end

  # Meta accepted the send and returned a message id. A recipient Lynomia never managed to hand over has none.
  def sent
    recipients.where.not(source_id: nil).count
  end

  def delivered
    recipients.where(DELIVERED_SQL).count
  end

  def read
    recipients.where.not(read_at: nil).count
  end

  def failed
    recipients.where.not(failed_at: nil).count
  end

  def skipped
    recipients.where(status: :skipped).count
  end

  # Addressed, not skipped, and no outcome yet.
  def pending
    recipients.where(status: :queued).count
  end

  # Rates are over the recipients the campaign targeted, which is the number an operator is judging the campaign
  # by. nil rather than 0 when nothing was targeted.
  def delivery_rate
    rate(delivered)
  end

  def read_rate
    rate(read)
  end

  def failure_rate
    rate(failed)
  end

  def series(metric)
    counts = case metric
             when :recipients_targeted then bucketed(recipients)
             when :delivered then bucketed(recipients.where(DELIVERED_SQL))
             when :failed then bucketed(recipients.where.not(failed_at: nil))
             end
    fill_buckets(counts)
  end

  def breakdown(dimension)
    case dimension
    when :campaign then campaign_rows
    when :failure then failure_rows
    when :skip_reason then skip_reason_rows
    when :audience then audience_rows
    end
  end

  private

  def recipients
    scope = CampaignRecipient.where(account_id: @account.id, created_at: @date_range.utc_range)
    scope = scope.where(inbox_id: @filters[:inbox_id]) if @filters[:inbox_id]
    scope = scope.where(campaign_id: filtered_campaign_id) if @filters[:campaign_id]
    scope
  end

  # The filter carries a campaign id that FilterSet already proved belongs to this account.
  def filtered_campaign_id
    @filters[:campaign_id]
  end

  def rate(value)
    total = recipients_targeted
    return nil if total.zero?

    (value.to_f / total * 100).round(1)
  end

  def bucketed(scope)
    scope.group_by_period(@date_range.group_by, Arel.sql('campaign_recipients.created_at'),
                          time_zone: @date_range.zone, default_value: 0).count
  end

  def fill_buckets(counts)
    normalized = (counts || {}).transform_keys { |key| key.to_date.strftime(Analytics::DateRange::DATE_FORMAT) }
    @date_range.bucket_starts.map do |bucket|
      key = bucket.to_date.strftime(Analytics::DateRange::DATE_FORMAT)
      { bucket: key, value: normalized[key].to_i }
    end
  end

  def campaign_rows
    labels = @account.campaigns.where(id: recipients.distinct.select(:campaign_id)).pluck(:id, :title).to_h
    recipients.group(:campaign_id).count.sort_by { |_id, count| -count }
              .map { |id, count| { id: id, label: labels[id] || "##{id}", value: count } }
  end

  # Meta's error code as the recipient recorded it, which is a short actionable value rather than free text.
  def failure_rows
    recipients.where.not(failed_at: nil).group(:error_code).count
              .sort_by { |_code, count| -count }
              .map { |code, count| { id: code.presence, label: code.presence, value: count } }
  end

  # Why Lynomia refused to send before trying. The message is one of a small set of fixed strings written by
  # Whatsapp::OneoffCampaignService, so grouping on it stays low cardinality.
  def skip_reason_rows
    recipients.where(status: :skipped).group(:error_message).count
              .sort_by { |_reason, count| -count }
              .map { |reason, count| { id: reason.presence, label: reason.presence, value: count } }
  end

  # Which saved audiences and labels the period's campaigns were aimed at.
  #
  # The value is a count of CAMPAIGNS, not of recipients. A campaign keeps only a reference to each audience or
  # label it targeted and never the conditions (custom/app/models/custom/campaign_audience.rb), and membership
  # is resolved at send time, so there is no way to attribute an individual recipient to the source that
  # selected it. Counting campaigns says exactly what is known: this audience was used this many times. The rows
  # deliberately do not sum to anything, because one campaign can target several sources.
  def audience_rows
    campaigns = @account.campaigns.where(id: recipients.distinct.select(:campaign_id)).pluck(:id, :audience)
    tallies = campaigns.each_with_object(Hash.new(0)) do |(_id, audience), counts|
      Array(audience).each do |entry|
        next unless AUDIENCE_TYPES.include?(entry['type'])

        counts[[entry['type'], entry['id']]] += 1
      end
    end

    tallies.sort_by { |_key, count| -count }.map do |(type, id), count|
      { id: "#{type.downcase}:#{id}", label: audience_labels.dig(type, id) || "#{type} ##{id}", value: count }
    end
  end

  def audience_labels
    @audience_labels ||= {
      'Label' => @account.labels.pluck(:id, :title).to_h,
      'Audience' => @account.custom_filters.contact.pluck(:id, :name).to_h
    }
  end
end
