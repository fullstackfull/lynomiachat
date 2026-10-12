# Lynomia Analytics, account level (docs/p8/02-analytics.md).
#
# At P8.1 this exposes only `meta`: the canonical analytics contract for the account -- which timezone its buckets
# are cut in, what the requested range resolves to, which metric families exist and which filters each accepts.
# The frontend needs this before it can render a date picker that produces deterministic requests, and it is what
# exercises the whole foundation (date range, filters, families, authorization, account scoping) end to end
# rather than leaving it as untested scaffolding. The metric endpoints arrive with the screens that read them.
class Api::V1::Accounts::AnalyticsController < Api::V1::Accounts::BaseController
  include Analytics::RequestScoped

  before_action :authorize_analytics

  # The operational overview: how much work arrived, how much closed, how much is still open, how fast we
  # respond, and where the volume sits. One request rather than eight.
  def overview
    render json: Analytics::Conversations::Overview.new(
      account: Current.account,
      date_range: date_range,
      filters: filter_set(:conversations),
      breakdown_by: params[:breakdown_by]
    ).call.as_json
  end

  # Is WhatsApp actually delivering? Every WhatsApp send in the account -- campaign, flow, automation or agent.
  def whatsapp
    render json: Analytics::Whatsapp::Overview.new(
      account: Current.account,
      date_range: date_range,
      filters: filter_set(:whatsapp),
      breakdown_by: params[:breakdown_by]
    ).call.as_json
  end

  # How the period's one-off campaigns performed, from the recipient snapshot that is also their audience record.
  def campaigns
    render json: Analytics::Campaigns::Overview.new(
      account: Current.account,
      date_range: date_range,
      filters: filter_set(:campaigns),
      breakdown_by: params[:breakdown_by]
    ).call.as_json
  end

  # Delayed automation executions only: an immediate rule leaves no record, and the response says so.
  def automations
    render json: Analytics::Automations::Overview.new(
      account: Current.account,
      date_range: date_range,
      filters: filter_set(:automations),
      breakdown_by: params[:breakdown_by]
    ).call.as_json
  end

  # Flow session lifecycle. No node-level metrics exist to report.
  def flows
    render json: Analytics::Flows::Overview.new(
      account: Current.account,
      date_range: date_range,
      filters: filter_set(:flows),
      breakdown_by: params[:breakdown_by]
    ).call.as_json
  end

  # Cart lifecycle and order actions, provider-neutral. No revenue: see docs/p8/02d-commerce-analytics.md.
  def commerce
    render json: Analytics::Commerce::Overview.new(
      account: Current.account,
      date_range: date_range,
      filters: filter_set(:commerce),
      breakdown_by: params[:breakdown_by]
    ).call.as_json
  end

  # Support cases (P9). Counts and the resolution average only; the family note says what is deliberately absent.
  def tickets
    render json: Analytics::Tickets::Overview.new(
      account: Current.account,
      date_range: date_range,
      filters: filter_set(:tickets),
      breakdown_by: params[:breakdown_by]
    ).call.as_json
  end

  def meta
    render json: {
      timezone: {
        name: date_range.zone,
        source: Current.account.reporting_timezone.presence ? 'account.reporting_timezone' : 'fallback',
        applies_to: 'date range interpretation and bucket boundaries',
        display_note: 'Format timestamps in the viewer timezone if preferred; it must not change grouping.'
      },
      range: date_range.to_meta,
      buckets: { count: date_range.bucket_count, maximum: Analytics::DateRange::MAX_BUCKETS[date_range.group_by] },
      group_by: { requested: date_range.group_by, supported: Analytics::DateRange::SUPPORTED_GROUP_BY },
      breakdowns: breakdowns_meta,
      current_state_metrics: Analytics::MetricFamily::CURRENT_STATE_METRICS.map(&:to_s),
      families: families_meta
    }
  end

  private

  # Analytics is account-wide reporting, so it follows the reporting permission the product already has
  # (ReportPolicy#view? is administrator-only). Where a P8 screen is scoped to one record instead, it follows
  # that record's own permission -- the existing per-campaign analytics does exactly that with
  # `authorize @campaign, :show?`, and the contact timeline will follow the contact's policy for the same reason.
  def authorize_analytics
    authorize :report, :view?
  end

  # Per family, so a screen can render its dimension switcher from the contract instead of a hardcoded list.
  def breakdowns_meta
    {
      conversations: breakdown_entry(Analytics::Conversations::Overview),
      whatsapp: breakdown_entry(Analytics::Whatsapp::Overview),
      campaigns: breakdown_entry(Analytics::Campaigns::Overview),
      automations: breakdown_entry(Analytics::Automations::Overview),
      flows: breakdown_entry(Analytics::Flows::Overview),
      commerce: breakdown_entry(Analytics::Commerce::Overview),
      tickets: breakdown_entry(Analytics::Tickets::Overview)
    }
  end

  def breakdown_entry(assembler)
    { supported: assembler::BREAKDOWN_DIMENSIONS.map(&:to_s), default: assembler::DEFAULT_BREAKDOWN.to_s }
  end

  def families_meta
    Analytics::MetricFamily.keys.index_with do |key|
      family = Analytics::MetricFamily.fetch(key)
      {
        metrics: family.metrics.map(&:to_s),
        filters: family.filters.map(&:to_s),
        rollup_capable_metrics: family.rollup_metrics.map(&:to_s),
        notes: family.notes
      }
    end
  end
end
