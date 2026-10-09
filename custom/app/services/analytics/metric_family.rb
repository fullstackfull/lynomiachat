# What each Lynomia Analytics screen is allowed to ask for (docs/p8/02-analytics.md).
#
# This is a declaration, not a second analytics engine: a family names the metrics a screen reads, the filters
# that are meaningful for it, and whether a rollup row exists that could answer it. The existing conversation
# metrics stay where they are, in ReportingEvents::MetricRegistry::REPORT_METRICS -- CONVERSATIONS simply points
# at them so there is one definition of a conversation metric and not two.
#
# A family declaring no rollup_metrics is not a limitation to fix later; for most of these no rollup dimension
# exists at all. ReportingEvents::RollupService only writes the account, agent and inbox dimensions
# (app/services/reporting_events/rollup_service.rb:33-39), so a campaign or template breakdown has nothing to
# read and is correctly a raw-only family.
module Analytics::MetricFamily
  Family = Data.define(:key, :metrics, :filters, :rollup_metrics, :notes)

  # Filters a family may accept. Each is validated against the account before it reaches a query
  # (Analytics::FilterSet), so an id from another tenant cannot select rows.
  ALL_FILTERS = %i[inbox_id channel_type team_id agent_id campaign_id template_id automation_rule_id provider].freeze

  FAMILIES = {
    conversations: Family.new(
      key: :conversations,
      metrics: ReportingEvents::MetricRegistry::REPORT_METRICS.keys,
      filters: %i[inbox_id channel_type team_id agent_id],
      # The three dimensions the rollup writer actually populates. A team or channel breakdown has no rollup
      # dimension, so those combinations fall to raw even when rollup coverage is otherwise valid.
      rollup_metrics: ReportingEvents::MetricRegistry::REPORT_METRICS.filter_map { |name, spec| name if spec[:rollup_metric] },
      notes: 'Reuses the OSS metric definitions; rollup only where a dimension exists.'
    ),
    whatsapp: Family.new(
      key: :whatsapp,
      metrics: %i[template_messages_sent delivered read failed delivery_rate read_rate failure_rate],
      filters: %i[inbox_id template_id],
      rollup_metrics: [],
      notes: 'Meta-authoritative delivery state from messages.status and campaign_recipients timestamps. ' \
             'Delivered and read are counted from the timestamp being present, never from status equality, ' \
             'because both ladders are monotonic and keep only the furthest state reached.'
    ),
    campaigns: Family.new(
      key: :campaigns,
      metrics: %i[recipients_targeted sent delivered read failed pending delivery_rate read_rate failure_rate],
      filters: %i[inbox_id campaign_id],
      rollup_metrics: [],
      notes: 'campaign_recipients is the snapshot and the funnel; no separate execution engine.'
    ),
    automations: Family.new(
      key: :automations,
      metrics: %i[executed skipped stuck skip_reasons],
      filters: %i[automation_rule_id],
      rollup_metrics: [],
      notes: 'Delayed rules only, and only within automation_rule_pending_executions 30-day retention. ' \
             'Immediate rules record nothing, so they are absent rather than reported as zero.'
    ),
    flows: Family.new(
      key: :flows,
      metrics: %i[sessions_started sessions_completed sessions_failed sessions_cancelled handed_off active waiting average_duration],
      filters: %i[inbox_id],
      rollup_metrics: [],
      notes: 'flow_sessions lifecycle only. No node-level metrics: no per-node history is stored.'
    ),
    commerce: Family.new(
      key: :commerce,
      metrics: %i[carts_seen carts_abandoned carts_completed completed_after_abandonment carts_targeted provider_distribution],
      filters: %i[provider],
      rollup_metrics: [],
      notes: 'commerce_carts lifecycle and commerce_action_runs. No revenue: spend is per-currency and ' \
             'deliberately unconverted, and there is no order store.'
    )
  }.freeze

  module_function

  def keys
    FAMILIES.keys
  end

  def fetch(key)
    FAMILIES.fetch(key.to_s.to_sym) do
      raise CustomExceptions::Analytics::UnknownMetricFamily.new(family: key.to_s, allowed: keys.map(&:to_s))
    end
  end

  def filters_for(key)
    fetch(key).filters
  end

  # A family can only be served from rollups if a rollup metric exists for what was asked. Coverage over the
  # requested dates is a separate question, answered by Analytics::RollupCoverage.
  def rollup_candidate?(key, metric)
    fetch(key).rollup_metrics.include?(metric.to_s.to_sym)
  end
end
