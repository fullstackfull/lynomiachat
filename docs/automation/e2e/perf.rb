# Lynomia Automation at volume (docs/automation/06-performance.md). Run with `rails runner` in the E2E environment, on an
# Audience perf account (docs/audience/e2e/perf.rb seed <contacts>: contacts, two WooCommerce stores whose hosts are
# never called, links, summaries, conversations).
#
#   measure <contacts>  one shared audience and four rules in that account (two with Lynomia conditions, one plain
#                       Chatwoot rule, one Commerce rule), then:
#                       - one event: the audience condition, and audience + Commerce + conversation conditions, as the
#                         listener evaluates them (ConditionsFilterService), 20 conversations, uncached
#                       - bursts of 100 and 1000 conversation_updated events through AutomationRuleListener, in process
#                         (the jobs the actions enqueue are held, not run)
#                       - a Commerce burst: 1000 linked customers' orders read pending then paid (Commerce::ContactMetric
#                         .record), each change dispatched and run as the worker runs it (jobs inline); their summaries
#                         are put back afterwards
#                       - EXPLAIN ANALYZE of the queries one evaluation runs
#                       - outbound HTTP counted (must be 0)
#                       The rules and the audience are removed at the end; the conversations keep the run's label.
#                       Needs the seed's stores, links and summaries (re-seed if a Commerce E2E reset removed them).
require 'json'
require 'net/http'

module CountedHttp
  def request(*)
    $automation_http_calls += 1 # rubocop:disable Style/GlobalVars
    super
  end
end
$automation_http_calls = 0 # rubocop:disable Style/GlobalVars
Net::HTTP.prepend(CountedHttp)

PERF_LABEL = 'perf-automation'.freeze

# The execution log's own figures (Automation::ExecutionLog): each Lynomia rule's outcome and the time its conditions
# and actions took, apart from the jobs its actions cause afterwards.
module CollectedLog
  def write(rule, trigger, outcome, correlation_id, details = {})
    $automation_log << { outcome: outcome, ms: details[:started_at] && ((clock - details[:started_at]) * 1000) } # rubocop:disable Style/GlobalVars
    super
  end
end
$automation_log = [] # rubocop:disable Style/GlobalVars
Automation::ExecutionLog.singleton_class.prepend(CollectedLog)

def logged
  $automation_log.clear # rubocop:disable Style/GlobalVars
  yield
  entries = $automation_log.dup # rubocop:disable Style/GlobalVars
  timed = entries.filter_map { |entry| entry[:ms] }
  { outcomes: entries.group_by { |entry| entry[:outcome] }.transform_values(&:size), rule_ms: timed.any? ? spread(timed) : nil }
end

def report(result) = puts("SIM #{result.to_json}")

def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000

def spread(times)
  sorted = times.sort
  { median_ms: sorted[sorted.size / 2].round(2), p95_ms: sorted[(sorted.size * 0.95).floor.clamp(0, sorted.size - 1)].round(2),
    max_ms: sorted.last.round(2) }
end

def condition(key, operator, values, query_operator = nil)
  { 'attribute_key' => key, 'filter_operator' => operator, 'values' => values, 'query_operator' => query_operator }
end

# Jobs run at once, as a worker would; jobs scheduled for later are left out of the timing.
class PerfInlineAdapter < ActiveJob::QueueAdapters::InlineAdapter
  def enqueue_at(*) = nil
end

def with_jobs(adapter)
  previous = ActiveJob::Base.queue_adapter
  ActiveJob::Base.queue_adapter = adapter
  yield
ensure
  ActiveJob::Base.queue_adapter = previous
end

# The run's rules and audience, also when an earlier run stopped half way.
def cleanup(account)
  account.automation_rules.where('name LIKE ?', 'Perf:%').destroy_all
  account.custom_filters.where('name LIKE ?', 'Perf VIP:%').destroy_all
end

def setup(account, size)
  cleanup(account)
  account.enable_features!('automations')
  admin = account.users.find_by!(email: "perf_admin_#{size}@audience.lynomia.local")
  vip = account.custom_filters.create!(user: admin, shared: true, filter_type: :contact, name: 'Perf VIP: visible spend SAR > 1000',
                                       query: { payload: [condition('commerce_spend_sar', 'is_greater_than', ['1000'])] })
  label = [{ 'action_name' => 'add_label', 'action_params' => [PERF_LABEL] }]
  rule = ->(name, event, conditions) { account.automation_rules.create!(name: name, event_name: event, conditions: conditions, actions: label) }
  rules = {
    audience: rule.call('Perf: audience', 'conversation_updated', [condition('contact_audience', 'equal_to', [vip.id])]),
    combined: rule.call('Perf: audience + Commerce + conversation', 'conversation_updated',
                        [condition('contact_audience', 'equal_to', [vip.id], 'and'),
                         condition('commerce_orders_count', 'is_greater_than', ['1'], 'and'), condition('status', 'equal_to', ['open'])]),
    plain: rule.call('Perf: plain Chatwoot rule', 'conversation_updated', [condition('status', 'equal_to', ['open'])]),
    paid: rule.call('Perf: Commerce order paid', 'commerce_order_paid',
                    [condition('contact_audience', 'equal_to', [vip.id], 'and'), condition('commerce_event_provider', 'equal_to', ['woocommerce'])])
  }
  [vip, rules]
end

# One event's conditions, as AutomationRuleListener evaluates them for a conversation: uncached, each conversation once.
def one_event(rule, conversations)
  runs = conversations.map do |conversation|
    ActiveRecord::Base.uncached do
      started = clock
      matched = AutomationRules::ConditionsFilterService.new(rule, conversation, { changed_attributes: {} }).perform
      [clock - started, matched]
    end
  end
  { conversations: runs.size, matched: runs.count(&:last), **spread(runs.map(&:first)) }
end

def burst(account, conversations)
  times = []
  started = clock
  log = logged do
    with_jobs(ActiveJob::QueueAdapters::TestAdapter.new) do
      conversations.each do |conversation|
        at = clock
        AutomationRuleListener.instance.conversation_updated(Events::Base.new('conversation.updated', Time.zone.now,
                                                                              conversation: conversation, changed_attributes: {}))
        times << (clock - at)
      end
    end
  end
  { events: conversations.size, rules_per_event: account.automation_rules.where(event_name: 'conversation_updated').count,
    total_ms: (clock - started).round(1), per_event: spread(times), lynomia_rules: log }
end

def order(link, status, payment)
  { 'external_order_id' => "perf-#{link.id}", 'order_number' => "P#{link.id}", 'status' => status, 'payment_status' => payment,
    'currency' => 'SAR', 'total' => '1500.00', 'created_at' => '2026-09-01T10:00:00Z', 'shipments' => [] }
end

def read(orders, at) = Commerce::Cache::Result.new(value: orders, fetched_at: at.utc.iso8601, stale: false, error: nil)

# 1000 linked customers with a conversation: a first read of a pending order (the baseline, no event), then a read of it
# paid, through the same write the Commerce reads use. Each paid read is one commerce_order_paid event, run inline with
# every job it causes (the dispatcher's listeners, the label's conversation update and its listeners, broadcasts).
def commerce_burst(account)
  links = Commerce::CustomerLink.where(account_id: account.id, contact_id: account.conversations.select(:contact_id))
                                .joins(:contact_metric).includes(:store, :contact).order(:id).limit(1000).to_a
  saved = Commerce::ContactMetric.where(commerce_customer_link_id: links.map(&:id)).map(&:attributes)
  now = Time.current.change(usec: 0)
  baseline = links.map do |link|
    at = clock
    Commerce::ContactMetric.record(link, read([order(link, 'pending', 'unpaid')], now + 1))
    clock - at
  end
  times = []
  started = clock
  log = logged do
    with_jobs(PerfInlineAdapter.new) do
      links.each do |link|
        at = clock
        Commerce::ContactMetric.record(link, read([order(link, 'processing', 'paid')], now + 2))
        times << (clock - at)
      end
    end
  end
  paid = { total_ms: (clock - started).round(1), per_event: spread(times) }
  saved.each { |row| Commerce::ContactMetric.where(id: row['id']).update_all(row.except('id')) }
  { customers: links.size, baseline_read: spread(baseline), paid_read_event_and_jobs: paid, paid_rule: log }
end

# The SQL one evaluation of the combined rule runs, each explained with its own bind values.
def explain(rule, conversation)
  statements = []
  callback = lambda do |*, payload|
    statements << [payload[:sql], payload[:binds]] if payload[:sql].start_with?('SELECT') && payload[:sql].match?(/contacts|conversations/)
  end
  ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
    ActiveRecord::Base.uncached { AutomationRules::ConditionsFilterService.new(rule, conversation, { changed_attributes: {} }).perform }
  end
  statements.uniq(&:first).map do |sql, binds|
    plan = ActiveRecord::Base.connection.select_all("EXPLAIN (ANALYZE, BUFFERS) #{sql}", 'EXPLAIN', binds).rows.flatten
    { sql: sql.gsub(/\s+/, ' ')[0, 400], plan: plan }
  end
end

def measure(size)
  account = Account.find_by!(name: "Lynomia Audience Perf #{size}")
  vip, rules = setup(account, size)
  vip_ids = Contacts::FilterService.new(account, nil, { payload: vip.query['payload'] }).relation.limit(500).pluck(:id)
  conversations = account.conversations.order(:id).includes(:contact).limit(1000).to_a
  sample = conversations.select.with_index { |_, index| (index % 50).zero? }.first(10) +
           account.conversations.where(contact_id: vip_ids).order(:id).limit(10).to_a
  several = Commerce::CustomerLink.where(account_id: account.id).joins(:contact_metric).where('commerce_contact_metrics.orders_count > 1')
  member = account.conversations.where(contact_id: vip_ids, status: :open).where(contact_id: several.select(:contact_id)).first

  members = Contacts::FilterService.new(account, nil, { payload: vip.query['payload'] }).perform[:count]
  result = {
    contacts: account.contacts.count, conversations: account.conversations.count, audience_members: members,
    one_event_audience: one_event(rules[:audience], sample),
    one_event_audience_commerce_conversation: one_event(rules[:combined], sample),
    one_event_plain_chatwoot: one_event(rules[:plain], sample),
    burst_100: burst(account, conversations.first(100)),
    burst_1000: burst(account, conversations),
    commerce_burst_1000: commerce_burst(account),
    explain: explain(rules[:combined], member)
  }
  cleanup(account)
  report(result.merge(http_calls: $automation_http_calls)) # rubocop:disable Style/GlobalVars
end

case ARGV[0]
when 'measure' then measure(Integer(ARGV[1]))
end
