# A simulated Zid for the Zid E2E (docs/commerce/17-zid-e2e.md). Zid's hosts are not reachable from the test environment,
# so oauth.zid.sa and api.zid.sa are answered in-process with WebMock, in Zid's documented shapes: the token response of
# Zid's OAuth docs and the manager profile, orders and webhooks of the official Zid SDK (github.com/zidsa/sdk-python).
# Every other host is untouched, and the Lynomia code under test runs unchanged.
#
# The simulation keeps Zid's side in Redis (E2E::ZIDSIM::*) so the web server, the job runner and the E2E script see the
# same Zid: authorization codes (single-use), issued tokens, revocations, webhook subscriptions (with the credentials
# Lynomia gave Zid), and request counters.
require 'webmock'

module ZidSim
  extend WebMock::API

  PREFIX = 'E2E::ZIDSIM'.freeze
  FIXTURE = Rails.root.join('spec/fixtures/files/commerce/zid/orders.json')
  STORES = {
    '318001' => { title: 'متجر الياسمين', url: 'https://jasmine.zid.store/', customers: { 90_001 => ['Omar Khalil', 'omar.khalil@example.com', '966551112233'] } },
    '318002' => { title: 'Zid Demo Two', url: 'https://zid-demo-two.zid.store/', customers: { 91_001 => ['Omar Khalil', 'omar@two.example', '966551112233'] } }
  }.freeze
  MARKETPLACE_BUYER = %w[966501234567 layla.haddad@example.com].freeze

  module_function

  def install!
    WebMock.enable!
    WebMock.allow_net_connect!
    Resolv.singleton_class.prepend(Module.new do
      def getaddresses(name) = %w[oauth.zid.sa api.zid.sa].include?(name) ? ['93.184.216.50'] : super
    end)
    stub_request(:any, /\Ahttps:\/\/(oauth|api)\.zid\.sa\//).to_return { |request| respond(request) }
  end

  def respond(request)
    count("#{request.method.upcase} #{request.uri.path}")
    return token(Rack::Utils.parse_query(request.body)) if request.uri.host == 'oauth.zid.sa' && request.uri.path == '/oauth/token'

    store = authenticated_store(request)
    return json(401, { status: 401, success: false, error: { code: 'unauthenticated', message: 'Unauthenticated.' } }) unless store

    api(request, store)
  end

  # ---- OAuth ------------------------------------------------------------------------------------------------------
  def token(form)
    case form['grant_type']
    when 'authorization_code' then exchange(form)
    when 'refresh_token' then refresh(form)
    else json(400, { error: 'unsupported_grant_type' })
    end
  end

  def exchange(form)
    store = form['code'].to_s[/\Ae2e-zid-code-(\d+)-/, 1]
    return json(400, { error: 'invalid_grant' }) unless store && redis.set("#{PREFIX}::CODE::#{form['code']}", 1, nx: true, ex: 1.day.to_i)

    issue(store)
  end

  def refresh(form)
    mode = redis.get("#{PREFIX}::REFRESH_MODE")
    sleep 0.3
    return json(400, { error: 'invalid_grant', message: 'The refresh token is invalid.' }) if mode == 'invalid_grant'
    return json(200, { access_token: 'e2e-zid-malformed' }) if mode == 'malformed'

    store = redis.hget("#{PREFIX}::REFRESH", form['refresh_token'])
    store ? issue(store) : json(400, { error: 'invalid_grant' })
  end

  def issue(store)
    generation = redis.incr("#{PREFIX}::GENERATION::#{store}")
    tokens = { access_token: "e2e-zid-manager-#{store}-#{generation}", authorization: "e2e-zid-auth-#{store}-#{generation}",
               refresh_token: "e2e-zid-refresh-#{store}-#{generation}" }
    redis.hset("#{PREFIX}::TOKENS", "#{tokens[:authorization]}|#{tokens[:access_token]}", store)
    redis.hset("#{PREFIX}::REFRESH", tokens[:refresh_token], store)
    json(200, tokens.merge(token_type: 'Bearer', expires_in: 31_536_000))
  end

  def authenticated_store(request)
    authorization = request.headers['Authorization'].to_s.delete_prefix('Bearer ')
    redis.hget("#{PREFIX}::TOKENS", "#{authorization}|#{request.headers['X-Manager-Token']}")
  end

  # Zid's uninstall: every token of the store stops working at once.
  def revoke(store)
    redis.hgetall("#{PREFIX}::TOKENS").each { |pair, owner| redis.hdel("#{PREFIX}::TOKENS", pair) if owner == store }
    redis.hgetall("#{PREFIX}::REFRESH").each { |token, owner| redis.hdel("#{PREFIX}::REFRESH", token) if owner == store }
  end

  # ---- Merchant API -----------------------------------------------------------------------------------------------
  def api(request, store)
    case [request.method, request.uri.path]
    in [:get, '/v1/managers/account/profile'] then json(200, profile(store))
    in [:get, '/v1/managers/store/orders'] then json(200, orders_page(store, Rack::Utils.parse_query(request.uri.query)))
    in [:post, '/v1/managers/webhooks'] then subscribe(store, JSON.parse(request.body))
    in [:delete, '/v1/managers/webhooks'] then unsubscribe(store)
    else json(404, { status: 404, success: false })
    end
  end

  def profile(store)
    data = STORES.fetch(store)
    { status: 'object', user: { id: 90_412, name: 'Store Manager', email: "manager-#{store}@example.com",
                                store: { id: store.to_i, title: data[:title], url: data[:url], timezone: 'Asia/Riyadh' } } }
  end

  def orders_page(store, query)
    orders = orders(store)
    orders = orders.select { |order| order['customer']['id'].to_s == query['customer_id'] } if query['customer_id']
    orders = orders.select { |order| searchable(order).any? { |value| value.include?(query['search_term']) } } if query['search_term']
    orders = orders.sort_by { |order| order['created_at'] }.reverse if query['sort_by'] == 'desc'
    { status: 'object', orders: orders.first(query.fetch('per_page', 15).to_i), total_order_count: orders.size }
  end

  # Zid searches its own, unmasked data: a marketplace order is found by its buyer's real phone and email, then masked.
  def searchable(order)
    return MARKETPLACE_BUYER if order['is_marketplace_order']

    order['customer'].values_at('email', 'mobile').map(&:to_s)
  end

  # The official fixture's orders, owned by this store's customer; the marketplace order (Layla's) arrives masked.
  def orders(store)
    customer_id, (name, email, mobile) = STORES.fetch(store)[:customers].first
    orders = JSON.parse(FIXTURE.read)['orders'].map do |order|
      next order.merge('store_id' => store.to_i) if order['is_marketplace_order']

      order.merge('store_id' => store.to_i, 'customer' => order['customer'].merge('id' => customer_id, 'name' => name, 'email' => email,
                                                                                  'mobile' => mobile))
    end
    orders.map { |order| order.merge(JSON.parse(redis.get("#{PREFIX}::ORDER::#{store}::#{order['id']}") || '{}')) }
  end

  def subscribe(store, body)
    id = SecureRandom.uuid
    redis.rpush("#{PREFIX}::WEBHOOKS::#{store}", body.merge('id' => id).to_json)
    json(200, { id: id, event: body['event'], target_url: body['target_url'], store_id: store, original_id: body['original_id'], active: true })
  end

  def unsubscribe(store)
    redis.del("#{PREFIX}::WEBHOOKS::#{store}")
    json(200, { status: 'object', message: { type: 'object', code: 'deleted' } })
  end

  def webhooks(store) = redis.lrange("#{PREFIX}::WEBHOOKS::#{store}", 0, -1).map { |raw| JSON.parse(raw) }

  # ---- helpers ----------------------------------------------------------------------------------------------------
  def count(name) = redis.hincrby("#{PREFIX}::REQUESTS", name, 1)

  def requests = redis.hgetall("#{PREFIX}::REQUESTS").transform_values(&:to_i)

  def json(status, body) = { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }

  def redis = Redis.new(url: ENV.fetch('REDIS_URL'))

  def reset!
    keys = redis.keys("#{PREFIX}::*")
    redis.del(*keys) if keys.any?
  end
end
