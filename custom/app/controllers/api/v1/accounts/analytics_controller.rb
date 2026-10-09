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
