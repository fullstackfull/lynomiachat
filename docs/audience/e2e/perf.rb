# Audience performance at volume (docs/audience/05-performance.md). Run with `rails runner` in the E2E environment.
#
#   seed <contacts>    a separate account "Lynomia Audience Perf <contacts>": that many contacts, two WooCommerce stores
#                      (rows only: their host is not reachable and is never called), 80% of the contacts linked, 85% of
#                      the links summarised (the rest unread), 60% with a conversation in one of two inboxes, 5% labelled
#   measure <contacts> times the contact filter as the API runs it (the count, then the first page of 15), median and
#                      max of 5 uncached runs, for existing, Commerce, conversation and combined conditions, as an
#                      administrator and as an agent with one inbox; EXPLAIN ANALYZE; outbound HTTP counted (must be 0)
#   api <contacts>     the same screens through the full Rails stack: filter builder options, audiences list, preview,
#                      opening a saved audience
#   relabel <contacts> the vip labels again (the seed's rule)
#   drop <contacts>    the account and everything in it removed
require 'json'
require 'net/http'

module CountedHttp
  def request(*)
    $audience_http_calls += 1 # rubocop:disable Style/GlobalVars
    super
  end
end
$audience_http_calls = 0 # rubocop:disable Style/GlobalVars
Net::HTTP.prepend(CountedHttp)

def report(result) = puts("SIM #{result.to_json}")

def account_named(size) = Account.find_by(name: "Lynomia Audience Perf #{size}")

def seed(size)
  account = Account.create!(name: "Lynomia Audience Perf #{size}", locale: 'en')
  account.enable_features!('lynomia_commerce')
  admin = User.create!(email: "perf_admin_#{size}@audience.lynomia.local", name: 'Perf Admin', password: 'Password1!x',
                       password_confirmation: 'Password1!x', confirmed_at: Time.current)
  agent = User.create!(email: "perf_agent_#{size}@audience.lynomia.local", name: 'Perf Agent', password: 'Password1!x',
                       password_confirmation: 'Password1!x', confirmed_at: Time.current)
  AccountUser.create!(account: account, user: admin, role: :administrator)
  AccountUser.create!(account: account, user: agent, role: :agent)
  inboxes = 2.times.map { |index| Inbox.create!(account: account, name: "Perf API #{index}", channel: Channel::Api.create!(account: account)) }
  InboxMember.create!(inbox: inboxes.first, user: agent)
  stores = 2.times.map do |index|
    account.commerce_stores.create!(provider: 'woocommerce', name: "Perf store #{index}", base_url: "https://perf-#{size}-#{index}.invalid",
                                    external_store_id: "perf-#{size}-#{index}.invalid",
                                    credentials: { 'consumer_key' => 'ck_unused', 'consumer_secret' => 'cs_unused' })
  end
  now = Time.current
  random = Random.new(size)

  contact_ids = size.times.each_slice(5000).flat_map do |slice|
    Contact.insert_all!(slice.map do |index|
      { account_id: account.id, name: "Perf contact #{index}", email: "perf#{index}@#{size}.audience.invalid", created_at: now, updated_at: now,
        last_activity_at: now - random.rand(365).days }
    end, returning: :id).rows.flatten
  end

  linked = contact_ids.select.with_index { |_, index| index % 5 != 0 }
  link_rows = linked.each_with_index.map do |contact_id, index|
    { account_id: account.id, commerce_store_id: stores[index % 2].id, contact_id: contact_id,
      external_customer_id: Commerce::CustomerLink.type_for_attribute(:external_customer_id).serialize("perf-#{index}"),
      match_source: Commerce::CustomerLink.match_sources[:verified_phone], created_at: now, updated_at: now }
  end
  link_ids = link_rows.each_slice(5000).flat_map { |rows| Commerce::CustomerLink.insert_all!(rows, returning: :id).rows.flatten }

  statuses = %w[pending processing shipped completed cancelled refunded]
  metric_rows = link_ids.each_with_index.filter_map do |link_id, index|
    next if index % 7 == 0 # unread

    orders = random.rand(0..5)
    { account_id: account.id, commerce_customer_link_id: link_id, orders_count: orders, active_orders_count: [orders, random.rand(0..2)].min,
      last_purchase_at: orders.zero? ? nil : now - random.rand(1..400).days,
      spend: orders.zero? ? {} : { 'SAR' => format('%.2f', random.rand(10.0..3000.0)) }.merge(index % 9 == 0 ? { 'USD' => '25.00' } : {}),
      order_statuses: orders.zero? ? [] : statuses.sample(random.rand(1..3), random: random).sort,
      payment_statuses: orders.zero? ? [] : %w[paid], shipment_statuses: [], fetched_at: now, created_at: now, updated_at: now }
  end
  metric_rows.each_slice(5000) { |rows| Commerce::ContactMetric.insert_all!(rows) }

  conversation_contacts = contact_ids.select.with_index { |_, index| index % 5 < 3 }
  contact_inbox_rows = conversation_contacts.each_with_index.map do |contact_id, index|
    { contact_id: contact_id, inbox_id: inboxes[index % 2].id, source_id: SecureRandom.uuid, created_at: now, updated_at: now }
  end
  contact_inbox_ids = contact_inbox_rows.each_slice(5000).flat_map { |rows| ContactInbox.insert_all!(rows, returning: :id).rows.flatten }
  conversation_rows = conversation_contacts.each_with_index.map do |contact_id, index|
    { account_id: account.id, inbox_id: inboxes[index % 2].id, contact_id: contact_id, contact_inbox_id: contact_inbox_ids[index],
      status: index % 4, priority: index % 5 == 0 ? 2 : nil, created_at: now, updated_at: now, last_activity_at: now }
  end
  conversation_rows.each_slice(5000) { |rows| Conversation.insert_all!(rows) }

  label(contact_ids)

  report({ account_id: account.id, contacts: contact_ids.size, links: link_ids.size, summaries: metric_rows.size,
           conversations: conversation_rows.size })
end

# 5% labelled vip: half of them unlinked, every one with an open conversation (index 40k and 40k + 6).
def label(contact_ids)
  contact_ids.each_with_index.select { |_, index| [0, 6].include?(index % 40) }
             .each { |contact_id, _| Contact.find(contact_id).update!(label_list: ['vip']) }
end

def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000

def spread(times)
  sorted = times.sort
  { median_ms: sorted[sorted.size / 2].round(1), max_ms: sorted.last.round(1) }
end

# The filter as the contacts API runs it: the count (preview), then the first page of 15. Each run reads the database:
# Rails' query cache is on in `rails runner`.
def timed(account, user, payload)
  runs = Array.new(5) do
    ActiveRecord::Base.connection.clear_query_cache
    ActiveRecord::Base.uncached do
      started = clock
      result = Contacts::FilterService.new(account, user, { payload: payload.map(&:with_indifferent_access) }).perform
      counted = clock
      result[:contacts].page(1).per(15).to_a
      [counted - started, clock - counted, result[:count]]
    end
  end
  { count: runs.first.last, count_ms: spread(runs.map(&:first)), first_page_ms: spread(runs.map { |run| run[1] }) }
end

def condition(key, operator, values, query_operator = nil)
  { 'attribute_key' => key, 'filter_operator' => operator, 'values' => values, 'query_operator' => query_operator }
end

COMBINED = 'combined: spend SAR > 1000 AND open conversation AND label vip'.freeze

def scenarios(account)
  store = account.commerce_stores.order(:id).first
  after = (Time.zone.today - 30).iso8601
  {
    'existing: email contains' => [condition('email', 'contains', ['perf1'])],
    'existing: label vip' => [condition('labels', 'equal_to', ['vip'])],
    'Commerce: linked store is present' => [condition('commerce_store', 'is_present', [])],
    'Commerce: store = store 1' => [condition('commerce_store', 'equal_to', [store.id])],
    'Commerce: visible spend SAR > 1000' => [condition('commerce_spend_sar', 'is_greater_than', ['1000'])],
    'Commerce: visible spend SAR < 100 (every store known)' => [condition('commerce_spend_sar', 'is_less_than', ['100'])],
    'Commerce: visible orders < 2 (every store known)' => [condition('commerce_orders_count', 'is_less_than', ['2'])],
    'Commerce: last visible purchase after 30 days ago' => [condition('commerce_last_purchase_at', 'is_greater_than', [after])],
    'Commerce: order status = processing' => [condition('commerce_order_status', 'equal_to', ['processing'])],
    'conversation: status open or resolved' => [condition('conversation_status', 'equal_to', %w[open resolved])],
    COMBINED => [condition('commerce_spend_sar', 'is_greater_than', ['1000'], 'AND'), condition('conversation_status', 'equal_to', ['open'], 'AND'),
                 condition('labels', 'equal_to', ['vip'])]
  }
end

def users(account, size)
  %w[admin agent].map { |role| account.users.find_by!(email: "perf_#{role}_#{size}@audience.lynomia.local") }
end

def explain(account, user, payload, options)
  relation = Contacts::FilterService.new(account, user, { payload: payload.map(&:with_indifferent_access) }).perform[:contacts]
  ActiveRecord::Base.connection.select_values("EXPLAIN (#{options}) #{relation.except(:order).select('COUNT(*)').to_sql}")
end

def measure(size)
  account = account_named(size)
  admin, agent = users(account, size)
  payloads = scenarios(account)
  results = payloads.transform_values { |payload| timed(account, admin, payload) }
  # Open conversations are all in the agent's inbox, resolved ones all in the other: the agent sees half.
  results['conversation: status open or resolved (agent, one of the two inboxes)'] =
    timed(account, agent, payloads['conversation: status open or resolved'])

  report({ contacts: account.contacts.count, results: results,
           explain_spend: explain(account, admin, payloads['Commerce: visible spend SAR > 1000'], 'ANALYZE, BUFFERS'),
           explain_combined: explain(account, admin, payloads[COMBINED], 'ANALYZE').grep(/Execution Time|Planning Time/),
           http_calls: $audience_http_calls }) # rubocop:disable Style/GlobalVars
end

# The same through the full Rails stack (routing, authentication, policies, JSON), in process: what the contacts screen asks
# for when the filter builder opens, when a filter is previewed (count and first page in one response), and when a saved
# audience is opened.
def api(size)
  require 'action_dispatch/testing/integration'
  account = account_named(size)
  admin, = users(account, size)
  payloads = scenarios(account)
  audience = account.custom_filters.find_or_create_by!(user: admin, filter_type: :contact, name: "Perf #{COMBINED}") do |filter|
    filter.query = { payload: payloads[COMBINED] }
  end
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! URI(ENV.fetch('FRONTEND_URL')).host
  session.https!(ENV.fetch('FRONTEND_URL').start_with?('https'))
  headers = { 'api_access_token' => admin.access_token.token, 'Content-Type' => 'application/json' }
  base = "/api/v1/accounts/#{account.id}"
  request = lambda do |verb, path, body = nil|
    session.public_send(verb, "#{base}#{path}", params: body&.to_json, headers: headers)
    raise "#{verb} #{path}: #{session.response.status}" unless session.response.status == 200

    session.response.parsed_body
  end
  timed_api = lambda do |&calls|
    calls.call # warm: the first request of a process loads code
    runs = Array.new(5) do
      started = clock
      body = calls.call
      [clock - started, body]
    end
    body = runs.first.last
    spread(runs.map(&:first)).merge(count: (body.dig('meta', 'count') if body.is_a?(Hash))).compact
  end
  preview = ->(payload) { timed_api.call { request.call(:post, '/contacts/filter?page=1', { payload: payload }) } }

  report({ contacts: account.contacts.count, api: {
           'open filter builder: Commerce options' => timed_api.call { request.call(:get, '/commerce/audience_fields') },
           'audiences list (sidebar)' => timed_api.call { request.call(:get, '/custom_filters?filter_type=contact') },
           'preview: email contains (existing)' => preview.call(payloads['existing: email contains']),
           'preview: visible spend SAR > 1000' => preview.call(payloads['Commerce: visible spend SAR > 1000']),
           'preview: visible orders < 2' => preview.call(payloads['Commerce: visible orders < 2 (every store known)']),
           "preview: #{COMBINED}" => preview.call(payloads[COMBINED]),
           'open saved audience: read it, count and first page' => timed_api.call do
             query = request.call(:get, "/custom_filters/#{audience.id}")['query']
             request.call(:post, '/contacts/filter?page=1', query)
           end
         }, http_calls: $audience_http_calls }) # rubocop:disable Style/GlobalVars
end

size = Integer(ARGV[1] || '10000')
case ARGV[0]
when 'seed' then seed(size)
when 'measure' then measure(size)
when 'api' then api(size)
when 'relabel'
  account = account_named(size)
  account.contacts.tagged_with('vip').find_each { |contact| contact.update!(label_list: []) }
  label(account.contacts.order(:id).pluck(:id))
  report({ vip: account.contacts.tagged_with('vip').count })
when 'drop'
  account = account_named(size)
  User.where('email LIKE ?', "perf_%_#{size}@audience.lynomia.local").find_each(&:destroy!)
  account&.destroy!
  report({ dropped: account.present? })
end
