# The simulated stores of the Phase 9–10 E2E (docs/commerce/33-phase9-10-e2e.md): the Phase 7–8 simulators
# (../realtime/sims.rb) with the store APIs order actions and abandoned carts use, in their documented shapes. WooCommerce
# is a real store (with the test-only gateway of ../woocommerce/lynomia-e2e-gateway.php). The Lynomia code under test
# runs unchanged; the simulators keep their side in Redis, shared by the server, the job worker and ctl.rb.
#
#   Zid      GET orders/{id}/view, POST orders/{id}/change-order-status (official SDK), GET abandoned-carts[/{id}]
#   Shopify  query order (action fields), mutations orderCancel (a Job, done a few seconds later) and refundCreate
#            (@idempotent: a key already used answers its first result and refunds nothing), query job,
#            abandonedCheckouts, shop.primaryDomain; mutations only with a token granted write_orders
#   Salla    GET /admin/v2/carts/abandoned
#   WhatsApp the Cloud API's send-message answer, so an agent's reply in the test WhatsApp inbox is "delivered" without
#            reaching Meta
require_relative '../realtime/sims'

module ActionSims
  READ_SCOPE = 'read_customers,read_orders'.freeze
  WRITE_SCOPE = 'read_customers,read_orders,write_orders'.freeze
  CANCEL_JOB_SECONDS = 4

  module_function

  # Prepended before the Phase 7–8 outage switch, which therefore covers these requests too.
  def install!
    ZidSim.singleton_class.prepend(ZidActions)
    ShopifySim.singleton_class.prepend(ShopifyActions)
    SallaSim.singleton_class.prepend(SallaCarts)
    RealtimeSims.install!
    WebMock::API.stub_request(:post, %r{\Ahttps://graph\.facebook\.com/v\d+\.\d+/[\w-]+/messages\z}).to_return do |request|
      ZidSim.redis.rpush('E2E::WHATSAPP::SENT', JSON.parse(request.body).slice('to', 'type').to_json)
      { status: 200, body: { messaging_product: 'whatsapp', messages: [{ id: "wamid.E2E#{SecureRandom.hex(8)}" }] }.to_json,
        headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def whatsapp_sent = ZidSim.redis.lrange('E2E::WHATSAPP::SENT', 0, -1).map { |raw| JSON.parse(raw) }

  module ZidActions
    STATUS_NAMES = { 'new' => 'New', 'preparing' => 'Preparing', 'ready' => 'Ready', 'indelivery' => 'In delivery',
                     'delivered' => 'Delivered', 'cancelled' => 'Cancelled' }.freeze

    def api(request, store)
      path = request.uri.path
      order = path[%r{\A/v1/managers/store/orders/(\d+)/(view|change-order-status)\z}, 1]
      cart = path[%r{\A/v1/managers/store/abandoned-carts/([\w-]+)\z}, 1]
      return view(store, order) if order && request.method == :get && path.end_with?('/view')
      return change_status(store, order, request) if order && request.method == :post && path.end_with?('/change-order-status')
      return json(200, { 'abandoned-carts' => carts(store, Rack::Utils.parse_query(request.uri.query)) }) if path == '/v1/managers/store/abandoned-carts'
      return cart(store, cart) if cart && request.method == :get

      super
    end

    def view(store, id)
      order = orders(store).find { |raw| raw['id'].to_s == id }
      order ? json(200, { order: order }) : json(404, { status: 404, success: false })
    end

    # Zid's write permission is the authorization's: 'forbidden' answers as Zid does for a token without it.
    def change_status(store, id, request)
      redis.rpush("#{ZidSim::PREFIX}::STATUS_CHANGES", { store: store, order: id, body: JSON.parse(request.body) }.to_json)
      return json(403, { status: 403, success: false, message: { type: 'error', code: 'forbidden' } }) if redis.get("#{ZidSim::PREFIX}::WRITE_MODE") == 'forbidden'

      code = JSON.parse(request.body)['order_status'].to_s
      return json(422, { status: 422, success: false }) unless STATUS_NAMES.key?(code)

      set_order(store, id, 'order_status' => { 'name' => STATUS_NAMES[code], 'code' => code })
      view(store, id)
    end

    def set_order(store, id, change)
      key = "#{ZidSim::PREFIX}::ORDER::#{store}::#{id}"
      redis.set(key, JSON.parse(redis.get(key) || '{}').merge(change).to_json)
    end

    def carts(store, query)
      all = JSON.parse(redis.get("#{ZidSim::PREFIX}::CARTS::#{store}") || '[]')
      all = all.select { |cart| cart['customer_id'].to_s == query['customer_id'] } if query['customer_id']
      all.first(query.fetch('page_size', 20).to_i).map { |cart| cart.except('products') }
    end

    def cart(store, id)
      found = JSON.parse(redis.get("#{ZidSim::PREFIX}::CARTS::#{store}") || '[]').find { |cart| cart['id'] == id }
      found ? json(200, { abandoned_cart: found }) : json(404, { status: 404, success: false })
    end

    def status_changes = redis.lrange("#{ZidSim::PREFIX}::STATUS_CHANGES", 0, -1).map { |raw| JSON.parse(raw) }
  end

  module ShopifyActions
    ACTION_OPERATIONS = %w[LynomiaOrderActions LynomiaJob LynomiaOrderCancel LynomiaRefundCreate LynomiaAbandonedCheckouts LynomiaShopDomain].freeze

    # The scopes a new grant carries: what the merchant approved (GRANT_MODE write_scope: write_orders as well).
    def exchange(shop, body)
      redis.set("#{ShopifySim::PREFIX}::SCOPE::#{shop}", redis.get("#{ShopifySim::PREFIX}::GRANT_MODE") == 'write_scope' ? WRITE_SCOPE : READ_SCOPE)
      super
    end

    # A refreshed token keeps the installation's scopes.
    def issue(shop, scope: nil, replaced: nil)
      scope ||= redis.get("#{ShopifySim::PREFIX}::SCOPE::#{shop}") || READ_SCOPE
      super(shop, scope: scope, replaced: replaced).tap do |answer|
        redis.hset("#{ShopifySim::PREFIX}::TOKEN_SCOPE", JSON.parse(answer[:body])['access_token'], scope)
      end
    end

    def graphql(shop, request)
      body = JSON.parse(request.body)
      operation = body['query'].to_s[/\A\s*(query|mutation)\s+(\w+)/, 2]
      return super unless ACTION_OPERATIONS.include?(operation)
      return super unless authorized?(shop, request)

      token = request.headers['X-Shopify-Access-Token'].to_s
      return super if body['query'] =~ /\A\s*mutation/ && !redis.hget("#{ShopifySim::PREFIX}::TOKEN_SCOPE", token).to_s.split(',').include?('write_orders')

      redis.rpush("#{ShopifySim::PREFIX}::OPERATIONS", "#{body['query'].to_s[/\A\s*(\w+)/, 1]} #{operation}")
      actions(shop, operation, body['variables'] || {}, body['query'])
    end

    def actions(shop, operation, variables, query)
      case operation
      when 'LynomiaOrderActions' then answer({ order: action_order(shop, variables['id']) })
      when 'LynomiaJob' then answer({ job: job(variables['id']) })
      when 'LynomiaOrderCancel' then cancel(shop, variables)
      when 'LynomiaRefundCreate' then refund_create(shop, variables, query)
      when 'LynomiaAbandonedCheckouts' then checkouts(shop, variables)
      when 'LynomiaShopDomain' then answer({ shop: { primaryDomain: { host: 'shop.lynomia-demo.example' } } })
      end
    end

    def answer(data) = json(200, { data: data, extensions: { cost: ShopifySim::COST } })

    def order_raw(shop, gid)
      settle_jobs(shop)
      all_orders(shop).find { |order| order['id'] == gid }
    end

    def action_order(shop, gid)
      raw = order_raw(shop, gid)
      return nil unless raw

      refunds = refunds(shop, raw['legacyResourceId'])
      refunded = refunds.sum(BigDecimal('0')) { |refund| BigDecimal(refund['amount']) }
      remaining = BigDecimal(raw.dig('currentTotalPriceSet', 'presentmentMoney', 'amount')) - refunded
      paid = %w[PAID PARTIALLY_REFUNDED].include?(raw['displayFinancialStatus']) && raw['cancelledAt'].nil?
      refundable = paid && remaining.positive?
      money = ->(value) { { presentmentMoney: { amount: value.to_s('F') } } }
      raw.merge('refundable' => refundable, 'presentmentCurrencyCode' => raw.dig('currentTotalPriceSet', 'presentmentMoney', 'currencyCode'),
                'totalRefundedSet' => money.call(refunded),
                'suggestedRefund' => refundable ? suggested(raw, remaining, money) : nil,
                'refunds' => refunds.map { |refund| refund.slice('id', 'legacyResourceId', 'note', 'createdAt') })
    end

    def suggested(raw, remaining, money)
      { maximumRefundableSet: money.call(remaining),
        suggestedTransactions: [{ kind: 'SUGGESTED_REFUND', gateway: 'shopify_payments', formattedGateway: 'Shopify Payments',
                                  parentTransaction: { id: "gid://shopify/OrderTransaction/9#{raw['legacyResourceId']}" },
                                  maximumRefundableSet: money.call(remaining) }] }
    end

    def refunds(shop, id) = redis.lrange("#{ShopifySim::PREFIX}::REFUNDS::#{shop}::#{id}", 0, -1).map { |raw| JSON.parse(raw) }

    def change(shop, id, values)
      key = "#{ShopifySim::PREFIX}::ORDER::#{shop}::#{id}"
      redis.set(key, JSON.parse(redis.get(key) || '{}').merge(values).to_json)
    end

    # orderCancel answers a Job; the order shows the cancellation once the Job is done (CANCEL_JOB_SECONDS later).
    def cancel(shop, variables)
      raw = order_raw(shop, variables['orderId'])
      if raw.nil? || raw['cancelledAt'] || !%w[PENDING AUTHORIZED].include?(raw['displayFinancialStatus'])
        errors = [{ code: 'INVALID', field: ['orderId'], message: 'Cannot cancel this order.' }]
        return answer({ orderCancel: { job: nil, orderCancelUserErrors: errors, userErrors: errors.map { |e| e.except(:code) } } })
      end

      id = "gid://shopify/Job/#{SecureRandom.uuid}"
      redis.hset("#{ShopifySim::PREFIX}::JOBS", id, { shop: shop, order: raw['legacyResourceId'], done_at: Time.now.to_f + CANCEL_JOB_SECONDS,
                                          staff_note: variables['staffNote'], refund: false }.to_json)
      redis.rpush("#{ShopifySim::PREFIX}::MUTATIONS", { name: 'orderCancel', order: raw['legacyResourceId'], variables: variables }.to_json)
      answer({ orderCancel: { job: { id: id, done: false }, orderCancelUserErrors: [], userErrors: [] } })
    end

    def job(id)
      data = redis.hget("#{ShopifySim::PREFIX}::JOBS", id.to_s)
      return nil unless data

      settle_jobs(JSON.parse(data)['shop'])
      { id: id, done: Time.now.to_f >= JSON.parse(data)['done_at'] }
    end

    def settle_jobs(shop)
      redis.hgetall("#{ShopifySim::PREFIX}::JOBS").each_value do |raw|
        job = JSON.parse(raw)
        next unless job['shop'] == shop && Time.now.to_f >= job['done_at']

        key = "#{ShopifySim::PREFIX}::ORDER::#{shop}::#{job['order']}"
        next if JSON.parse(redis.get(key) || '{}')['cancelledAt']

        change(shop, job['order'], 'cancelledAt' => Time.at(job['done_at']).utc.iso8601, 'displayFinancialStatus' => 'VOIDED')
      end
    end

    # refundCreate with Shopify's idempotency: the first request with a key decides; a repeat answers the same.
    # 13.13 is refused with userErrors; 7.77 is made but its answer is lost (a read timeout on Lynomia's side).
    def refund_create(shop, variables, query)
      key = variables['idempotencyKey'].to_s
      unless query.include?('@idempotent(key: $idempotencyKey)') && key.present?
        return json(200, { errors: [{ message: 'An idempotency key is required for refundCreate.', extensions: { code: 'BAD_REQUEST' } }] })
      end

      redis.rpush("#{ShopifySim::PREFIX}::MUTATIONS", { name: 'refundCreate', key: key, variables: variables }.to_json)
      previous = redis.get("#{ShopifySim::PREFIX}::IDEMPOTENT::#{key}")
      return json(200, JSON.parse(previous)) if previous

      result = refund_result(shop, variables)
      redis.set("#{ShopifySim::PREFIX}::IDEMPOTENT::#{key}", result.to_json)
      raise Net::ReadTimeout if variables.dig('input', 'transactions', 0, 'amount') == '7.77'

      json(200, result)
    end

    def refund_result(shop, variables)
      input = variables['input']
      amount = input.dig('transactions', 0, 'amount').to_s
      order = action_order(shop, input['orderId'])
      maximum = order && order['suggestedRefund'] ? BigDecimal(order['suggestedRefund'][:maximumRefundableSet][:presentmentMoney][:amount]) : 0
      if order.nil? || amount == '13.13' || BigDecimal(amount) > maximum
        message = amount == '13.13' ? 'The payment processor declined the refund.' : 'Amount cannot be greater than the refundable amount.'
        return { data: { refundCreate: { refund: nil, userErrors: [{ field: %w[transactions 0 amount], message: message }] } } }
      end

      number = redis.incr("#{ShopifySim::PREFIX}::REFUND_SEQ") + 7000
      refund = { 'id' => "gid://shopify/Refund/#{number}", 'legacyResourceId' => number.to_s, 'note' => input['note'],
                 'createdAt' => Time.now.utc.iso8601, 'amount' => amount }
      redis.rpush("#{ShopifySim::PREFIX}::REFUNDS::#{shop}::#{order['legacyResourceId']}", refund.to_json)
      fully = BigDecimal(amount) == maximum
      change(shop, order['legacyResourceId'], 'displayFinancialStatus' => fully ? 'REFUNDED' : 'PARTIALLY_REFUNDED')
      { data: { refundCreate: { refund: refund.slice('id', 'legacyResourceId'), userErrors: [] } } }
    end

    # Open checkouts, newest first ('status:open'), or one by id; 'denied' mode is Shopify's protected customer data refusal.
    def checkouts(shop, variables)
      return denied if redis.get("#{ShopifySim::PREFIX}::CHECKOUT_MODE") == 'denied'

      all = JSON.parse(redis.get("#{ShopifySim::PREFIX}::CHECKOUTS::#{shop}") || '[]').sort_by { |checkout| checkout['createdAt'] }.reverse
      id = variables['query'].to_s[/\Aid:(\d+)\z/, 1]
      all = id ? all.select { |checkout| checkout['id'].end_with?("/#{id}") } : all.select { |checkout| checkout['completedAt'].nil? }
      answer({ abandonedCheckouts: { nodes: all.first(variables['first'].to_i) } })
    end

    def mutations = redis.lrange("#{ShopifySim::PREFIX}::MUTATIONS", 0, -1).map { |raw| JSON.parse(raw) }
  end

  module SallaCarts
    def respond(request)
      return super unless request.uri.path == '/admin/v2/carts/abandoned'

      count("#{request.method.upcase} #{request.uri.path}")
      return json(401, { status: 401, success: false, error: { code: 'Unauthorized' } }) unless authorized?(request)

      per_page = Rack::Utils.parse_query(request.uri.query).fetch('per_page', 15).to_i
      envelope(JSON.parse(redis.get("#{SallaSim::PREFIX}::CARTS") || '[]').sort_by { |cart| -cart['id'] }.first(per_page))
    end
  end
end
