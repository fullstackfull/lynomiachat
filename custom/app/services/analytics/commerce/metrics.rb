# Lynomia Analytics: commerce cart lifecycle and order actions (docs/p8/02d-commerce-analytics.md).
#
# Provider-neutral throughout: every number comes from `commerce_carts` and `commerce_action_runs`, which already
# normalise Woo, Salla, Zid and Shopify into one shape. Nothing here calls a provider, and nothing here keeps a
# second copy of an order.
#
# Three rules this family is built around, all of them restatements of what the data can support:
#
#   1. NO REVENUE, GMV OR PROFIT. `commerce_carts.visible_total` exists, and it is deliberately never summed.
#      Carts carry a per-cart `currency` and nothing in this product converts between currencies, so one total
#      would silently add riyals to dollars. A currency breakdown reports cart COUNTS instead, which is the
#      number an operator actually needs from it: which currencies the traffic is in, and therefore that the
#      values cannot be added up.
#
#   2. NO RECOVERY ATTRIBUTION. Completion does not prove Lynomia's outreach caused it -- Zid's own cart schema
#      carries `reminders_count` and a `whatsapp_message`, so the store may be sending reminders of its own
#      (custom/app/models/commerce/cart.rb). What is reported is `post_target_completions`: a completion that
#      happened AFTER outreach was accepted. That is a time ordering, named for what it measures, beside
#      `untargeted_completions` so the contrast is visible rather than implied.
#
#   3. NO INVENTED CART STATES. The enum is abandoned and completed, because those are the only two things a
#      provider announces. There is no `active` state and no inactivity timer, so silence is never a signal.
class Analytics::Commerce::Metrics
  COUNT_METRICS = %i[
    carts_seen carts_abandoned carts_targeted carts_completed post_target_completions untargeted_completions
    order_actions_requested order_actions_failed recovery_messages_prepared
  ].freeze
  RATE_METRICS = %i[targeting_rate].freeze
  CURRENT_STATE_METRICS = %i[open_abandoned_now actions_unresolved_now].freeze
  EVENT_METRICS = (COUNT_METRICS + RATE_METRICS).freeze
  ALL_METRICS = (EVENT_METRICS + CURRENT_STATE_METRICS).freeze

  SEEN_COLUMN = 'commerce_carts.first_seen_at'.freeze
  ABANDONED_COLUMN = 'commerce_carts.abandoned_at'.freeze
  TARGETED_COLUMN = 'commerce_carts.targeted_at'.freeze
  COMPLETED_COLUMN = 'commerce_carts.completed_at'.freeze
  ACTION_COLUMN = 'commerce_action_runs.created_at'.freeze

  # The model's own definition of the strongest statement the data supports (Commerce::Cart#post_target_completion?),
  # as SQL so it can be counted and bucketed rather than loaded row by row.
  POST_TARGET_SQL = 'commerce_carts.targeted_at IS NOT NULL AND commerce_carts.completed_at > commerce_carts.targeted_at'.freeze

  def initialize(account:, date_range:, filters:)
    @account = account
    @date_range = date_range
    @filters = filters
  end

  # Every cart the provider first mentioned in this period. For most providers the first thing said about a cart
  # is that it was abandoned, so this and carts_abandoned are usually close; they are reported separately because
  # nothing guarantees it.
  def carts_seen
    carts.where(first_seen_at: @date_range.utc_range).count
  end

  def carts_abandoned
    @carts_abandoned ||= carts.where(abandoned_at: @date_range.utc_range).count
  end

  # Outreach was accepted for sending. Not "a message arrived": that is the WhatsApp family's question.
  def carts_targeted
    @carts_targeted ||= carts.where(targeted_at: @date_range.utc_range).count
  end

  def carts_completed
    carts.where(completed_at: @date_range.utc_range).count
  end

  # A completion that followed outreach. A time ordering, not a proof of cause.
  def post_target_completions
    completions_in_range.where(POST_TARGET_SQL).count
  end

  def untargeted_completions
    completions_in_range.where(targeted_at: nil).count
  end

  # Of the carts the provider reported abandoned in this period, the share Lynomia messaged in the same period.
  # nil rather than 0 when nothing was abandoned.
  def targeting_rate
    return nil if carts_abandoned.zero?

    (carts_targeted.to_f / carts_abandoned * 100).round(1)
  end

  def order_actions_requested
    action_runs_in_range.order_actions.count
  end

  def order_actions_failed
    action_runs_in_range.order_actions.failed.count
  end

  def recovery_messages_prepared
    action_runs_in_range.where(action_type: Commerce::ActionRun::RECOVERY_MESSAGE).count
  end

  # Current state: carts the provider called abandoned and has never called completed.
  def open_abandoned_now
    carts.abandoned.count
  end

  # Current state: actions that have not settled. `unknown` is the one that matters -- the request reached the
  # store but the answer was lost, and it is never re-sent, only reconciled by reading the store. A number above
  # zero is work for an operator.
  def actions_unresolved_now
    action_runs.unresolved.count
  end

  def series(metric)
    counts = case metric
             when :carts_abandoned then bucketed(carts.where(abandoned_at: @date_range.utc_range), ABANDONED_COLUMN)
             when :carts_targeted then bucketed(carts.where(targeted_at: @date_range.utc_range), TARGETED_COLUMN)
             when :carts_completed then bucketed(completions_in_range, COMPLETED_COLUMN)
             end
    fill_buckets(counts)
  end

  def breakdown(dimension)
    case dimension
    when :provider then provider_rows
    when :store then store_rows
    when :currency then currency_rows
    when :action_type then action_type_rows
    when :action_error then action_error_rows
    end
  end

  private

  def carts
    scope = Commerce::Cart.where(account_id: @account.id)
    scope = scope.where(provider: @filters[:provider]) if @filters[:provider]
    scope
  end

  def completions_in_range
    carts.where(completed_at: @date_range.utc_range)
  end

  def action_runs
    scope = Commerce::ActionRun.where(account_id: @account.id)
    scope = scope.where(provider: @filters[:provider]) if @filters[:provider]
    scope
  end

  def action_runs_in_range
    action_runs.where(created_at: @date_range.utc_range)
  end

  def bucketed(scope, column)
    scope.group_by_period(@date_range.group_by, Arel.sql(column),
                          time_zone: @date_range.zone, default_value: 0).count
  end

  def fill_buckets(counts)
    normalized = (counts || {}).transform_keys { |key| key.to_date.strftime(Analytics::DateRange::DATE_FORMAT) }
    @date_range.bucket_starts.map do |bucket|
      key = bucket.to_date.strftime(Analytics::DateRange::DATE_FORMAT)
      { bucket: key, value: normalized[key].to_i }
    end
  end

  # Carts first seen in the period, which is the cohort the provider, store and currency questions are about.
  def seen_in_range
    carts.where(first_seen_at: @date_range.utc_range)
  end

  def provider_rows
    seen_in_range.group(:provider).count.sort_by { |_provider, count| -count }
                 .map { |provider, count| { id: provider, label: provider, value: count } }
  end

  def store_rows
    labels = @account.commerce_stores.pluck(:id, :name).to_h
    seen_in_range.group(:commerce_store_id).count.sort_by { |_id, count| -count }
                 .map { |id, count| { id: id, label: labels[id] || "##{id}", value: count } }
  end

  # Cart COUNTS per currency, never a sum of visible_total. See the class comment: nothing converts between
  # currencies, so a combined money total would be wrong, and a per-currency money total is the revenue figure
  # this product deliberately does not publish.
  def currency_rows
    seen_in_range.group(:currency).count.sort_by { |_currency, count| -count }
                 .map { |currency, count| { id: currency.presence, label: currency.presence, value: count } }
  end

  def action_type_rows
    action_runs_in_range.group(:action_type).count.sort_by { |_type, count| -count }
                        .map { |type, count| { id: type, label: type, value: count } }
  end

  def action_error_rows
    action_runs_in_range.failed.group(:error_code).count.sort_by { |_code, count| -count }
                        .map { |code, count| { id: code.presence, label: code.presence, value: count } }
  end
end
