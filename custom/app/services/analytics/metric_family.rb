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

  # Metrics that describe how things stand now rather than what happened inside a range. The response labels
  # them so a screen cannot plot a current reading as if it were a historical series.
  CURRENT_STATE_METRICS = Analytics::Conversations::Metrics::CURRENT_STATE_METRICS

  # Filters a family may accept. Each is validated against the account before it reaches a query
  # (Analytics::FilterSet), so an id from another tenant cannot select rows.
  ALL_FILTERS = %i[inbox_id channel_type team_id agent_id campaign_id template_id automation_rule_id provider].freeze

  FAMILIES = {
    conversations: Family.new(
      key: :conversations,
      metrics: Analytics::Conversations::Metrics::EVENT_METRICS +
               Analytics::Conversations::Metrics::CURRENT_STATE_METRICS,
      filters: %i[inbox_id channel_type team_id agent_id],
      # The three dimensions the rollup writer actually populates. A team or channel breakdown has no rollup
      # dimension, so those combinations fall to raw even when rollup coverage is otherwise valid.
      rollup_metrics: ReportingEvents::MetricRegistry::REPORT_METRICS.filter_map { |name, spec| name if spec[:rollup_metric] },
      notes: 'Conversation and message metrics. avg_first_response_time and avg_resolution_time reuse the OSS ' \
             'reporting_events definitions unchanged. unresolved_backlog is current state, not a range count.'
    ),
    whatsapp: Family.new(
      key: :whatsapp,
      metrics: Analytics::Whatsapp::Metrics::EVENT_METRICS + %i[coexistence_echoes],
      filters: %i[inbox_id template_id],
      rollup_metrics: [],
      notes: 'Outgoing WhatsApp messages. delivered means the status ladder reached delivered or read, because ' \
             'messages.status carries no timestamps and keeps only the furthest state reached; a later failed ' \
             'overwrites it, so delivery is understated for a message that was delivered and then failed. ' \
             'Coexistence echoes are excluded from every count and rate and reported separately: their ' \
             'delivered status is written locally, not by Meta.'
    ),
    campaigns: Family.new(
      key: :campaigns,
      metrics: Analytics::Campaigns::Metrics::EVENT_METRICS,
      filters: %i[inbox_id campaign_id],
      rollup_metrics: [],
      notes: 'campaign_recipients is the snapshot and the funnel; no separate execution engine. Delivered and ' \
             'read come from the timestamps being present, never from status equality. The audience breakdown ' \
             'counts campaigns per targeted audience, not recipients: a campaign keeps only a reference to each ' \
             'audience and membership is resolved at send time, so no recipient can be attributed to a source.'
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

  def current_state?(metric)
    CURRENT_STATE_METRICS.include?(metric.to_s.to_sym)
  end
end
