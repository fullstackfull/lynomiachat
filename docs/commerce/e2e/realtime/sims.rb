# The simulated stores of the Phase 7–8 realtime E2E (docs/commerce/27-phase7-8-e2e.md). WooCommerce is a real store;
# Salla, Zid and Shopify are not reachable from the test environment, so they are answered in-process with WebMock, in
# their documented shapes: Zid and Shopify by the provider E2Es' simulators (../zid/zid_sim.rb, ../shopify/shopify_sim.rb),
# Salla by SallaSim below (the Salla E2E's fixtures, with orders that can change). Every other host is untouched.
#
# Each simulated store keeps its side in Redis (orders that changed, tokens, outages, request counts), so the web server,
# the job worker and the control runner (ctl.rb) all see the same store. The Lynomia code under test runs unchanged.
require 'webmock'
require_relative '../zid/zid_sim'
require_relative '../shopify/shopify_sim'

module SallaSim
  extend WebMock::API

  PREFIX = 'E2E::SALLASIM'.freeze
  FIXTURES = Rails.root.join('spec/fixtures/files/commerce/salla')
  MERCHANT = { 'id' => 1_234_509_876, 'name' => 'متجر الورد', 'domain' => 'https://salla.sa/rose-store' }.freeze
  CUSTOMER_ID = '1227534533'.freeze

  module_function

  def install!
    WebMock.enable!
    WebMock.allow_net_connect!
    Resolv.singleton_class.prepend(Module.new do
      def getaddresses(name) = %w[api.salla.dev accounts.salla.sa].include?(name) ? ['93.184.216.40'] : super
    end)
    stub_request(:any, %r{\Ahttps://(api\.salla\.dev|accounts\.salla\.sa)/}).to_return { |request| respond(request) }
  end

  def respond(request)
    count("#{request.method.upcase} #{request.uri.path}")
    return json(401, { status: 401, success: false, error: { code: 'Unauthorized' } }) unless authorized?(request)

    query = Rack::Utils.parse_query(request.uri.query)
    case request.uri.path
    when '/oauth2/user/info' then json(200, user_info)
    when '/admin/v2/customers' then envelope(query['keyword'] == '551112233' ? fixture('customers.json')['data'].first(1) : [])
    when '/admin/v2/orders' then envelope(query['customer_id'] == CUSTOMER_ID ? orders : [])
    when '/admin/v2/shipments' then envelope(query['order_id'] == '1861092002' ? fixture('shipments.json')['data'] : [])
    else json(404, { status: 404, success: false })
    end
  end

  def authorized?(request)
    token = request.headers['Authorization'].to_s.delete_prefix('Bearer ')
    token.start_with?('e2e-access-') && !redis.sismember("#{PREFIX}::REVOKED", token)
  end

  def user_info
    info = fixture('user_info.json')
    info.merge('merchant' => info['merchant'].merge(MERCHANT))
  end

  # The fixture's orders of Omar's Salla customer, with the changes made since (ctl.rb order salla …).
  def orders
    fixture('orders.json')['data'].map do |order|
      change = JSON.parse(redis.get("#{PREFIX}::ORDER::#{order['id']}") || '{}')
      change.empty? ? order : order.merge('status' => order['status'].merge(change))
    end
  end

  def change_order(id, slug, name) = redis.set("#{PREFIX}::ORDER::#{id}", { 'slug' => slug, 'name' => name }.to_json)

  def revoke(token) = redis.sadd("#{PREFIX}::REVOKED", token)

  def fixture(name) = JSON.parse(FIXTURES.join(name).read)

  def envelope(data) = { status: 200, body: { status: 200, success: true, data: data }.to_json,
                         headers: { 'Content-Type' => 'application/json', 'X-RateLimit-Remaining' => '100' } }

  def json(status, body) = { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }

  def count(name) = redis.hincrby("#{PREFIX}::REQUESTS", name, 1)

  def requests = redis.hgetall("#{PREFIX}::REQUESTS").transform_values(&:to_i)

  def redis = Redis.new(url: ENV.fetch('REDIS_URL'))

  def reset!
    keys = redis.keys("#{PREFIX}::*")
    redis.del(*keys) if keys.any?
  end
end

# The three simulated providers together, each of which can be switched to an outage: every request then gets 503.
module RealtimeSims
  SIMS = { 'salla' => SallaSim, 'zid' => ZidSim, 'shopify' => ShopifySim }.freeze
  OUTAGE = 'E2E::REALTIME::OUTAGE'.freeze

  module_function

  def install!
    SIMS.each_value(&:install!)
    SIMS.each do |provider, sim|
      sim.singleton_class.prepend(Module.new do
        define_method(:respond) do |request|
          next super(request) unless RealtimeSims.redis.exists?("#{OUTAGE}::#{provider}")

          sim.count("#{request.method.upcase} #{request.uri.path} (outage)")
          { status: 503, body: '{"error":"service unavailable"}', headers: { 'Content-Type' => 'application/json' } }
        end
      end)
    end
  end

  def outage(provider, on) = on ? redis.set("#{OUTAGE}::#{provider}", 1) : redis.del("#{OUTAGE}::#{provider}")

  def requests = SIMS.transform_values(&:requests)

  def redis = Redis.new(url: ENV.fetch('REDIS_URL'))
end
