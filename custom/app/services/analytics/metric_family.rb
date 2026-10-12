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
  # The union across every family that has one, so `meta.current_state_metrics` is the complete list a screen
  # needs in order to refuse to plot a reading taken now as if it were a history. Collected from the families
  # rather than written out, so adding a family cannot leave this behind. Whatsapp and Campaigns declare none.
  CURRENT_STATE_METRICS = [
    Analytics::Conversations::Metrics, Analytics::Automations::Metrics, Analytics::Flows::Metrics,
    Analytics::Commerce::Metrics, Analytics::Tickets::Metrics
  ].flat_map { |family| family::CURRENT_STATE_METRICS }.uniq.freeze

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
      metrics: Analytics::Automations::Metrics::ALL_METRICS,
      filters: %i[automation_rule_id],
      rollup_metrics: [],
      notes: 'Delayed rules only, and only within automation_rule_pending_executions 30-day retention. ' \
             'Immediate rules run inline and record nothing, so they are absent rather than reported as zero; ' \
             'the response warns when the account has any. Outcomes are bucketed on updated_at, which is when ' \
             'the episode reached its outcome; episodes_armed is bucketed on created_at.'
    ),
    flows: Family.new(
      key: :flows,
      metrics: Analytics::Flows::Metrics::ALL_METRICS,
      filters: %i[inbox_id],
      rollup_metrics: [],
      notes: 'flow_sessions lifecycle only. No node-level metrics, because no per-node history is stored, and ' \
             'no abandoned state, because the product has none: a session with no further replies stays ' \
             'waiting until something ends it. Duration is wall-clock finished_at - created_at.'
    ),
    tickets: Family.new(
      key: :tickets,
      metrics: Analytics::Tickets::Metrics::ALL_METRICS,
      filters: %i[inbox_id team_id agent_id],
      rollup_metrics: [],
      notes: 'Support cases (P9). Counts and the resolution average only: no SLA attainment percentage, no ' \
             'first-response average and no reopen rate, because every SLA figure in this product begins when a ' \
             'policy is first attached to a case, so a rate over a range that predates the policy would divide ' \
             'two different populations. Reopens are counted from the durable event trail rather than inferred ' \
             'from the current status, so a case reopened and resolved again is still counted.'
    ),
    commerce: Family.new(
      key: :commerce,
      metrics: Analytics::Commerce::Metrics::ALL_METRICS,
      filters: %i[provider],
      rollup_metrics: [],
      notes: 'commerce_carts lifecycle and commerce_action_runs, provider-neutral. No revenue, GMV or profit: ' \
             'visible_total is never summed because carts carry a per-cart currency and nothing converts ' \
             'between currencies, so the currency breakdown reports cart counts. No recovery attribution: ' \
             'post_target_completions is a completion that followed outreach, which is a time ordering and not ' \
             'a proof of cause, and untargeted_completions sits beside it. No order store.'
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
