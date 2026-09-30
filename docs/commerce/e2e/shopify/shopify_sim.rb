# A simulated Shopify for the Shopify Commerce E2E (docs/commerce/22-shopify-e2e.md). Shopify's hosts are not reachable
# from the test environment, so every <shop>.myshopify.com host is answered in-process with WebMock, in the shapes of
# Shopify's documentation and the Admin GraphQL API 2026-07 schema: the token endpoint (authorization code with
# expiring=1, refresh_token grant) and the GraphQL endpoint (shop, customers, orders, order). Every other host is
# untouched, and the Lynomia code under test runs unchanged.
#
# The simulation keeps Shopify's side in Redis (E2E::SHOPIFYSIM::*) so the web server, the job runner and the E2E script
# see the same Shopify: single-use authorization codes, issued tokens with their expiry, refreshes (a repeated refresh
# with the same refresh token returns the same pair, as Shopify documents), revocations, order changes, request counts
# and every GraphQL operation received (a mutation is recorded and refused).
require 'webmock'

module ShopifySim
  extend WebMock::API

  PREFIX = 'E2E::SHOPIFYSIM'.freeze
  CLIENT_ID = 'e2e-shopify-commerce-client'.freeze
  API_PATH = '/admin/api/2026-07/graphql.json'.freeze
  FIXTURES = Rails.root.join('spec/fixtures/files/commerce/shopify')
  SHOPS = {
    'lynomia-demo.myshopify.com' => { id: 68_210_001, name: 'Lynomia Demo', number: '1' },
    'lynomia-two.myshopify.com' => { id: 68_210_002, name: 'Lynomia Two', number: '2' }
  }.freeze
  # The shop's customers: default email and phone only (names are protected data the connector does not request).
  CUSTOMERS = [
    { 'id' => 'gid://shopify/Customer/7001', 'email' => 'Omar.Khalil@example.com', 'phone' => '+966551112233' },
    { 'id' => 'gid://shopify/Customer/7002', 'email' => 'hana@example.net', 'phone' => '+966550000999' }
  ].freeze
  COST = { 'requestedQueryCost' => 40, 'actualQueryCost' => 12,
           'throttleStatus' => { 'maximumAvailable' => 2000.0, 'currentlyAvailable' => 1988, 'restoreRate' => 100.0 } }.freeze

  module_function

  def install!
    WebMock.enable!
    WebMock.allow_net_connect!
    Resolv.singleton_class.prepend(Module.new do
      def getaddresses(name) = name.to_s.end_with?('.myshopify.com') ? ['93.184.216.60'] : super
    end)
    stub_request(:post, %r{\Ahttps://[a-z0-9-]+\.myshopify\.com/admin/}).to_return { |request| respond(request) }
  end

  def respond(request)
    shop = request.uri.host
    count("POST #{request.uri.path}")
    return json(404, { errors: 'Not Found' }) unless SHOPS.key?(shop)
    return token(shop, JSON.parse(request.body)) if request.uri.path == '/admin/oauth/access_token'
    return graphql(shop, request) if request.uri.path == API_PATH

    json(404, { errors: 'Not Found' })
  end

  # ---- OAuth ------------------------------------------------------------------------------------------------------
  def token(shop, body)
    return json(401, { error: 'invalid_client' }) unless body['client_id'] == CLIENT_ID && body['client_secret'] == ENV.fetch('E2E_SHOPIFY_CLIENT_SECRET')

    body['grant_type'] == 'refresh_token' ? refresh(shop, body['refresh_token']) : exchange(shop, body)
  end

  def exchange(shop, body)
    return json(400, { error: 'invalid_request', error_description: 'The authorization code was not found or was already used.' }) \
      unless body['code'].to_s.start_with?('e2e-shopify-code-') && redis.set("#{PREFIX}::CODE::#{body['code']}", 1, nx: true, ex: 1.day.to_i)

    redis.rpush("#{PREFIX}::EXPIRING", body['expiring'].to_s)
    case redis.get("#{PREFIX}::GRANT_MODE")
    when 'non_expiring' then json(200, { access_token: "e2e-shp-access-#{SHOPS.dig(shop, :id)}-legacy", scope: 'read_customers,read_orders' })
    when 'write_scope' then issue(shop, scope: 'read_customers,read_orders,write_orders')
    else issue(shop)
    end
  end

  # Shopify's documented refresh behavior: a repeated refresh with the same refresh token (after a timeout or a lost
  # answer) gets the same new pair, and the previous refresh token keeps working until the new access token is used.
  def refresh(shop, refresh_token)
    mode = redis.get("#{PREFIX}::REFRESH_MODE")
    sleep 0.3
    return json(400, { error: 'invalid_request', error_description: 'This refresh token is not valid.' }) if mode == 'invalid'
    return json(502, { errors: 'Bad gateway' }) if mode == '5xx_once' && redis.del("#{PREFIX}::REFRESH_MODE") == 1

    replay = redis.get("#{PREFIX}::REFRESHED::#{refresh_token}")
    return json(200, JSON.parse(replay)) if replay && redis.hget("#{PREFIX}::REFRESH", refresh_token) == shop
    return json(400, { error: 'invalid_request', error_description: 'This refresh token is not valid.' }) unless redis.hget("#{PREFIX}::REFRESH", refresh_token) == shop

    answer = issue(shop, replaced: refresh_token)
    redis.setex("#{PREFIX}::REFRESHED::#{refresh_token}", 1.hour.to_i, answer[:body])
    raise Net::ReadTimeout if mode == 'timeout_once' && redis.del("#{PREFIX}::REFRESH_MODE") == 1

    answer
  end

  def issue(shop, scope: 'read_customers,read_orders', replaced: nil)
    id = SHOPS.dig(shop, :id)
    generation = redis.incr("#{PREFIX}::GENERATION::#{shop}")
    access_ttl = (redis.get("#{PREFIX}::ACCESS_TTL") || 3600).to_i
    tokens = { access_token: "e2e-shp-access-#{id}-#{generation}", refresh_token: "e2e-shp-refresh-#{id}-#{generation}" }
    redis.hset("#{PREFIX}::ACCESS", tokens[:access_token], { shop: shop, expires_at: Time.now.to_i + access_ttl, replaced: replaced }.to_json)
    redis.hset("#{PREFIX}::REFRESH", tokens[:refresh_token], shop)
    json(200, tokens.merge(scope: scope, expires_in: access_ttl, refresh_token_expires_in: 7_776_000))
  end

  # The shop uninstalled the app: every token of the shop stops working at once.
  def revoke(shop)
    redis.hgetall("#{PREFIX}::ACCESS").each { |token, data| redis.hdel("#{PREFIX}::ACCESS", token) if JSON.parse(data)['shop'] == shop }
    redis.hgetall("#{PREFIX}::REFRESH").each { |token, owner| redis.hdel("#{PREFIX}::REFRESH", token) if owner == shop }
  end

  # Shopify rejects the shop's current access tokens before their expiry (as Lynomia sees it).
  def invalidate_access(shop)
    redis.hgetall("#{PREFIX}::ACCESS").each do |token, data|
      redis.hset("#{PREFIX}::ACCESS", token, JSON.parse(data).merge('expires_at' => 0).to_json) if JSON.parse(data)['shop'] == shop
    end
  end

  # ---- Admin GraphQL API ------------------------------------------------------------------------------------------
  def graphql(shop, request)
    return json(401, { errors: '[API] Invalid API key or access token (unrecognized login or wrong password)' }) unless authorized?(shop, request)

    body = JSON.parse(request.body)
    operation = body['query'].to_s[/\A\s*(query|mutation)\s+(\w+)/, 2] || 'anonymous'
    redis.rpush("#{PREFIX}::OPERATIONS", "#{body['query'].to_s[/\A\s*(\w+)/, 1]} #{operation}")
    return json(200, { errors: [{ message: 'Mutations are not available to this app.', extensions: { code: 'ACCESS_DENIED' } }] }) if body['query'] =~ /\A\s*mutation/

    mode = redis.get("#{PREFIX}::GQL_MODE")
    return denied if mode == 'denied' && operation != 'LynomiaShop'
    return throttled if mode == 'throttled'

    json(200, { data: data(shop, operation, body['variables'] || {}), extensions: { cost: COST } })
  end

  def authorized?(shop, request)
    token = request.headers['X-Shopify-Access-Token'].to_s
    data = redis.hget("#{PREFIX}::ACCESS", token)
    return false unless data && JSON.parse(data)['shop'] == shop && JSON.parse(data)['expires_at'] > Time.now.to_i

    replaced = JSON.parse(data)['replaced']
    redis.hdel("#{PREFIX}::REFRESH", replaced) if replaced
    true
  end

  def data(shop, operation, variables)
    case operation
    when 'LynomiaShop' then { shop: { id: "gid://shopify/Shop/#{SHOPS.dig(shop, :id)}", name: SHOPS.dig(shop, :name), myshopifyDomain: shop } }
    when 'LynomiaCustomers' then { customers: { nodes: customers(variables['query']).first(variables['first']) } }
    when 'LynomiaGuestOrders', 'LynomiaOrders' then { orders: { nodes: orders(shop, variables['query']).first(variables['first']) } }
    when 'LynomiaOrder' then { order: orders(shop, nil).find { |order| order['id'] == variables['id'] } }
    end
  end

  # Shopify search: a quoted phrase is one value (backslash escapes), matched exactly; email ignores case.
  def filter(query)
    field, phrase, number = query.to_s.match(/\A(\w+):(?:"((?:[^"\\]|\\.)*)"|(\d+))\z/)&.captures
    [field, phrase ? phrase.gsub(/\\(.)/, '\1') : number]
  end

  def customers(query)
    field, value = filter(query)
    CUSTOMERS.select { |customer| field == 'email' ? customer['email'].casecmp?(value) : customer['phone'] == value }.map do |customer|
      { 'id' => customer['id'], 'defaultEmailAddress' => { 'emailAddress' => customer['email'] },
        'defaultPhoneNumber' => { 'phoneNumber' => customer['phone'] } }
    end
  end

  def orders(shop, query)
    field, value = filter(query)
    all = all_orders(shop)
    all = all.select { |order| order['customer'] && order['customer']['id'] == "gid://shopify/Customer/#{value}" } if field == 'customer_id'
    all = all.select { |order| order['email'].to_s.casecmp?(value) } if field == 'email'
    all.sort_by { |order| order['createdAt'] }.reverse
  end

  # The fixture's orders as this shop's, with Omar's email; the guest checkouts of Mona and Omar; and order changes.
  def all_orders(shop)
    number = SHOPS.dig(shop, :number)
    registered = JSON.parse(FIXTURES.join('orders.json').read).dig('data', 'orders', 'nodes').map do |order|
      order.merge('email' => order['customer']['id'].end_with?('/7001') ? 'Omar.Khalil@example.com' : order['email'])
    end
    guests = JSON.parse(FIXTURES.join('guest_orders.json').read).dig('data', 'orders', 'nodes').first(1).flat_map do |order|
      [order.merge('email' => 'Mona.Saleh@example.com'),
       order.merge('id' => 'gid://shopify/Order/6001011', 'legacyResourceId' => '6001011', 'name' => '#1011', 'email' => 'omar.khalil@example.com',
                   'createdAt' => '2026-09-26T08:00:00Z', 'updatedAt' => '2026-09-26T09:00:00Z')]
    end
    (registered + guests).map do |order|
      order = order.merge('name' => order['name'].sub('#1', "##{number}")) if number != '1'
      order.merge(JSON.parse(redis.get("#{PREFIX}::ORDER::#{shop}::#{order['legacyResourceId']}") || '{}'))
    end
  end

  def denied
    json(200, { errors: [{ message: 'This app is not approved to access the Customer object. See https://shopify.dev/docs/apps/launch/protected-customer-data for more details.',
                           extensions: { code: 'ACCESS_DENIED' } }] })
  end

  def throttled
    json(200, { errors: [{ message: 'Throttled', extensions: { code: 'THROTTLED', documentation: 'https://shopify.dev/api/usage/rate-limits' } }],
                extensions: { cost: COST.merge('throttleStatus' => COST['throttleStatus'].merge('currentlyAvailable' => 5)) } })
  end

  # ---- State ------------------------------------------------------------------------------------------------------
  def count(key) = redis.hincrby("#{PREFIX}::REQUESTS", key, 1)

  def requests = redis.hgetall("#{PREFIX}::REQUESTS").transform_values(&:to_i)

  def operations = redis.lrange("#{PREFIX}::OPERATIONS", 0, -1)

  def expiring = redis.lrange("#{PREFIX}::EXPIRING", 0, -1)

  def json(status, body) = { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }

  def redis = Redis.new(url: ENV.fetch('REDIS_URL'))

  def reset!
    keys = redis.keys("#{PREFIX}::*")
    redis.del(*keys) if keys.any?
  end
end
