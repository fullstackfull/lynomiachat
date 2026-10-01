# Controls of the Phase 9–10 E2E (docs/commerce/33-phase9-10-e2e.md), in a runner with the simulated stores installed.
# Every result is printed as one "SIM <json>" line, without credentials.
#
# Usage: rails runner docs/commerce/e2e/actions/ctl.rb <command> [args]
#   reset                         remove every store, run and simulated state; installation switches back to the
#                                 defaults of config/installation_config.yml; WooCommerce alone switched on
#   defaults                      the installation's commerce switches and what they mean for each provider
#   connect                       switch Salla, Zid and Shopify on and connect their stores to account A (Shopify with
#                                 the read-only scopes a first connection asks for)
#   switch <NAME> <true|false>    an installation switch, as Super Admin sets it
#   zid_order <id> <status>       the order's status in Zid, changed by the merchant (no event)
#   zid_write <ok|forbidden>      whether Zid accepts the authorization's status changes
#   zid_reauthorize               the administrator authorizes Lynomia in Zid again
#   shopify_order <number> <financial> <fulfillment>   the order in Shopify, changed by the merchant (no event)
#   shopify_grant <ok|write_scope>     the scopes the merchant approves on Shopify's authorization page
#   shopify_checkouts <ok|denied>      abandonedCheckouts answered, or refused for protected customer data
#   carts                         abandoned carts in the three simulated stores (see CARTS below)
#   salla_cart <id> <total>       a new abandoned cart of Omar in Salla, then Salla's abandoned.cart event
#   drop_carts                    forget the cached carts (as when they expire), so the next view reads the stores
#   window <open|closed>          Omar's WhatsApp conversation: a message from him now, or his last one 25 hours ago
#   runs                          the action runs (every column)
#   audit                         the commerce audit trail
#   stores                        stores with their capability state (no credentials)
#   sims                          what the simulated stores received (status changes, mutations, WhatsApp sends)
#   secrets                       the credentials to scan logs and pages for
require_relative 'sims'
require 'net/http'
require 'sidekiq/api'

Rails.logger = ActiveSupport::Logger.new(Rails.root.join('tmp/e2e_ctl.log'))
ActionSims.install!

BASE = 'http://localhost:3100'.freeze
ZID_STORE = '318001'.freeze
SHOP = 'lynomia-demo.myshopify.com'.freeze
SWITCHES = %w[COMMERCE_ACTIONS_ENABLED WOOCOMMERCE_ACTIONS_ENABLED SALLA_ACTIONS_ENABLED ZID_ACTIONS_ENABLED SHOPIFY_COMMERCE_ACTIONS_ENABLED
              COMMERCE_RECOVERY_ENABLED SALLA_RECOVERY_ENABLED ZID_RECOVERY_ENABLED SHOPIFY_COMMERCE_RECOVERY_ENABLED
              COMMERCE_RECOVERY_COOLDOWN_HOURS].freeze

def report(result) = puts("SIM #{result.to_json}")

def account_a = Account.find_by!(name: 'Lynomia Demo A')

def admin_a = User.find_by!(email: 'admin_a@commerce.lynomia.local')

def omar_conversation = account_a.conversations.joins(:contact).find_by!(contacts: { name: 'Omar Khalil' })

def riyadh(time) = time.in_time_zone('Asia/Riyadh').strftime('%F %T')

def post(path, body, headers)
  uri = URI("#{BASE}#{path}")
  request = Net::HTTP::Post.new(uri, headers.merge('Content-Type' => 'application/json'))
  request.body = body
  Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }.code.to_i
end

def configure(on)
  { 'SALLA_ENABLED' => on, 'SALLA_APP_ID' => '1234567890', 'SALLA_CLIENT_ID' => 'e2e-salla-client-id',
    'SALLA_CLIENT_SECRET' => ENV.fetch('E2E_SALLA_CLIENT_SECRET'), 'SALLA_WEBHOOK_SECRET' => ENV.fetch('E2E_SALLA_WEBHOOK_SECRET'),
    'ZID_ENABLED' => on, 'ZID_CLIENT_ID' => '4821', 'ZID_CLIENT_SECRET' => ENV.fetch('E2E_ZID_CLIENT_SECRET'),
    'SHOPIFY_COMMERCE_ENABLED' => on, 'SHOPIFY_COMMERCE_CLIENT_ID' => ShopifySim::CLIENT_ID,
    'SHOPIFY_COMMERCE_CLIENT_SECRET' => ENV.fetch('E2E_SHOPIFY_CLIENT_SECRET') }.each do |name, value|
    InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false)
  end
  GlobalConfig.clear_cache
end

# The switches as a new installation has them: config/installation_config.yml.
def default_switches
  YAML.load_file(Rails.root.join('config/installation_config.yml')).select { |entry| SWITCHES.include?(entry['name']) }
      .to_h { |entry| [entry['name'], entry['value']] }
end

def reset
  Commerce::ActionRun.delete_all
  Commerce::Store.find_each(&:destroy!)
  [SallaSim, ZidSim, ShopifySim].each(&:reset!)
  ZidSim.redis.del('E2E::WHATSAPP::SENT')
  %w[COMMERCE::* E2E::REALTIME::*].each do |pattern|
    keys = []
    Redis::Alfred.scan_each(match: pattern) { |key| keys << key }
    keys.each { |key| Redis::Alfred.delete(key) }
  end
  Sidekiq::Queue.all.each(&:clear)
  Sidekiq::ScheduledSet.new.clear
  Enterprise::AuditLog.where('comment LIKE ?', 'commerce.%').delete_all if defined?(Enterprise::AuditLog)
  Account.find_each { |account| account.update!(locale: 'en') && account.enable_features!('lynomia_commerce') }
  default_switches.each { |name, value| InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false) }
  %w[COMMERCE_REALTIME_ENABLED].each { |name| InstallationConfig.where(name: name).destroy_all }
  omar_conversation.messages.where(message_type: :outgoing).destroy_all
  configure(false)
end

def connect_salla
  code = Commerce::Salla::ConnectionCode.create(account: account_a, user: admin_a)[:code]
  authorize = SallaSim.fixture('app_store_authorize.json').deep_merge(
    'created_at' => Time.current.strftime('%F %T'),
    'data' => { 'access_token' => 'e2e-access-m1', 'refresh_token' => 'e2e-refresh-m1', 'expires' => 14.days.from_now.to_i,
                'scope' => 'offline_access customers.read orders.read shipping.read carts.read' }
  )
  settings = SallaSim.fixture('app_settings_updated.json').deep_merge('data' => { 'settings' => { 'lynomia_connection_code' => code } })
  [authorize, settings].each { |payload| Commerce::Salla::Installation.new(payload).process }
end

def wait_for(seconds = 30)
  deadline = Time.current + seconds
  sleep 0.5 until yield || Time.current > deadline
end

# Omar's carts: his (linked customer 90001 in Zid, 7001 in Shopify, 1227534533 in Salla) and others that must never show:
# another customer's with his phone, a masked phone, a recovered and an expired cart, and one whose link leaves the store.
def carts
  zid = lambda do |id, **fields|
    { id: "c0ffee0#{id}-0000-4000-8000-00000000000#{id}", url: "https://jasmine.zid.store/cart/recover/#{id}?key=e2e#{id}", cart_id: "cart-#{id}",
      order_id: nil, phase: 'payment_method', customer_id: 90_001, customer_name: 'Omar Khalil', customer_email: nil, customer_mobile: nil,
      products_count: 2, reminders_count: 0, cart_total: 185.5, cart_total_string: '185.50 SAR', currency_code: 'SAR',
      created_at: riyadh(3.hours.ago), updated_at: riyadh(2.hours.ago),
      products: [{ name: 'Rose Serum', quantity: 1 }, { name: 'Oud Lotion', quantity: 1 }] }.merge(fields)
  end
  ZidSim.redis.set("#{ZidSim::PREFIX}::CARTS::#{ZID_STORE}", [
    zid.call(1),
    zid.call(2, cart_total: 99, url: 'https://evil.example/cart/recover/2', created_at: riyadh(5.hours.ago), updated_at: riyadh(5.hours.ago)),
    zid.call(3, customer_id: 90_002, customer_mobile: '966551112233', customer_name: 'Omar Khalil'),
    zid.call(4, customer_id: nil, customer_mobile: '*******2233'),
    zid.call(5, phase: 'completed', order_id: 41_000_190),
    zid.call(6, created_at: riyadh(40.days.ago), updated_at: riyadh(40.days.ago))
  ].to_json)

  checkout = lambda do |id, customer, **fields|
    { id: "gid://shopify/AbandonedCheckout/#{id}", name: "##{id}", abandonedCheckoutUrl: "https://#{SHOP}/68210001/checkouts/ac/#{id}/recover?key=e2e#{id}",
      createdAt: 4.hours.ago.utc.iso8601, updatedAt: 3.hours.ago.utc.iso8601, completedAt: nil, lineItemsQuantity: 3,
      customer: customer && { id: "gid://shopify/Customer/#{customer}" }, totalPriceSet: { presentmentMoney: { amount: '410.0', currencyCode: 'SAR' } },
      lineItems: { nodes: [{ title: 'Oud Perfume 50ml', quantity: 2 }, { title: 'Gift Box', quantity: 1 }] } }.merge(fields)
  end
  ShopifySim.redis.set("#{ShopifySim::PREFIX}::CHECKOUTS::#{SHOP}", [
    checkout.call(9101, 7001), checkout.call(9102, 7002), checkout.call(9103, nil), checkout.call(9104, 7001, completedAt: 1.hour.ago.utc.iso8601)
  ].to_json)

  SallaSim.redis.set("#{SallaSim::PREFIX}::CARTS", [salla_cart(551_100, 230), salla_cart(551_101, 75, customer: { id: 1_227_534_599, name: 'Omar Khalil' })].to_json)
  report({ zid: 6, shopify: 4, salla: 2 })
end

def salla_cart(id, total, customer: nil)
  stamp = ->(time) { { date: time.in_time_zone('Asia/Riyadh').strftime('%F %T.%6N'), timezone_type: 3, timezone: 'Asia/Riyadh' } }
  { id: id, checkout_url: "https://salla.sa/rose-store/checkout/#{id}", age_in_minutes: 95, coupon: nil,
    total: { amount: total, currency: 'SAR' }, subtotal: { amount: total, currency: 'SAR' }, total_discount: { amount: 0, currency: 'SAR' },
    created_at: stamp.call(2.hours.ago), updated_at: stamp.call(90.minutes.ago),
    customer: customer || { id: SallaSim::CUSTOMER_ID.to_i, name: 'Omar Khalil', mobile: '+966551112233', email: 'omar.khalil@example.com' },
    items: [{ id: 1, product_id: 77, quantity: 2 }] }
end

def salla_event(event, data)
  body = { event: event, merchant: SallaSim::MERCHANT['id'], created_at: Time.current.strftime('%F %T.%L'), data: data }.to_json
  post('/webhooks/salla', body, { 'X-Salla-Security-Strategy' => 'Signature',
                                  'X-Salla-Signature' => OpenSSL::HMAC.hexdigest('SHA256', ENV.fetch('E2E_SALLA_WEBHOOK_SECRET'), body) })
end

def switches_report
  providers = %w[woocommerce salla zid shopify]
  { configured: SWITCHES.index_with { |name| InstallationConfig.find_by(name: name)&.value },
    defaults: default_switches,
    pre_uat_override: ENV.fetch('COMMERCE_ALLOW_PRE_UAT_PROVIDERS', nil),
    read: providers.index_with { |provider| Commerce::Providers.enabled?(provider) },
    actions: providers.index_with { |provider| Commerce::Switches.provider_actions_enabled?(provider) },
    recovery: providers.index_with { |provider| Commerce::Switches.provider_recovery_enabled?(provider) } }
end

command, *args = ARGV
case command
when 'reset'
  reset
  report({ stores: Commerce::Store.count, runs: Commerce::ActionRun.count })
when 'defaults'
  report(switches_report)
when 'connect'
  configure(true)
  connect_salla
  Commerce::Zid::Authorization.new(account: account_a, user: admin_a).connect("e2e-zid-code-#{ZID_STORE}-#{SecureRandom.hex(4)}")
  Commerce::Shopify::Authorization.new(account: account_a, user: admin_a).connect(SHOP, "e2e-shopify-code-#{SecureRandom.hex(4)}")
  wait_for { ZidSim.webhooks(ZID_STORE).any? }
  report({ stores: Commerce::Store.order(:id).pluck(:id, :provider, :name, :status) })
when 'switch'
  InstallationConfig.where(name: args[0]).first_or_initialize.update!(value: args[1] == 'true', locked: false)
  GlobalConfig.clear_cache
  report(switches_report.slice(:actions, :recovery).merge(args[0] => args[1]))
when 'zid_order'
  ZidSim.set_order(ZID_STORE, args[0], 'order_status' => { 'name' => ActionSims::ZidActions::STATUS_NAMES.fetch(args[1]), 'code' => args[1] })
  report({ zid_order: args })
when 'zid_write'
  args[0] == 'forbidden' ? ZidSim.redis.set("#{ZidSim::PREFIX}::WRITE_MODE", 'forbidden') : ZidSim.redis.del("#{ZidSim::PREFIX}::WRITE_MODE")
  report({ zid_write: args[0] })
when 'zid_reauthorize'
  Commerce::Zid::Authorization.new(account: account_a, user: admin_a).connect("e2e-zid-code-#{ZID_STORE}-#{SecureRandom.hex(4)}")
  report({ zid: Commerce::Store.find_by!(provider: 'zid').metadata.slice('write_access') })
when 'shopify_order'
  raw = ShopifySim.all_orders(SHOP).find { |candidate| candidate['name'] == "##{args[0]}" }
  ShopifySim.change(SHOP, raw['legacyResourceId'], 'displayFinancialStatus' => args[1], 'displayFulfillmentStatus' => args[2])
  report({ shopify_order: args })
when 'shopify_grant'
  ShopifySim.redis.set("#{ShopifySim::PREFIX}::GRANT_MODE", args[0])
  report({ shopify_grant: args[0] })
when 'shopify_checkouts'
  args[0] == 'denied' ? ShopifySim.redis.set("#{ShopifySim::PREFIX}::CHECKOUT_MODE", 'denied') : ShopifySim.redis.del("#{ShopifySim::PREFIX}::CHECKOUT_MODE")
  report({ shopify_checkouts: args[0] })
when 'carts'
  carts
when 'salla_cart'
  list = JSON.parse(SallaSim.redis.get("#{SallaSim::PREFIX}::CARTS") || '[]') << salla_cart(args[0].to_i, args[1].to_f)
  SallaSim.redis.set("#{SallaSim::PREFIX}::CARTS", list.to_json)
  status = salla_event('abandoned.cart', { id: args[0].to_i, customer: { id: SallaSim::CUSTOMER_ID.to_i } })
  report({ salla_cart: args[0], status: status, delivered_at: (Time.current.to_f * 1000).round })
when 'drop_carts'
  Commerce::Store.find_each { |store| %i[carts cart_queue].each { |kind| Commerce::Cache.delete_all(store, kind) } }
  report({ dropped: true })
when 'window'
  conversation = omar_conversation
  if args[0] == 'open'
    conversation.messages.create!(account: conversation.account, inbox: conversation.inbox, message_type: :incoming, sender: conversation.contact,
                                  content: 'I left some items in my cart')
  else
    conversation.messages.where(message_type: :incoming).find_each { |message| message.update_columns(created_at: 25.hours.ago) }
  end
  report({ window: args[0], can_reply: conversation.reload.can_reply?, conversation: conversation.display_id })
when 'runs'
  report({ runs: Commerce::ActionRun.order(:id).map { |run| run.attributes.except('request_digest') } })
when 'audit'
  logs = defined?(Enterprise::AuditLog) ? Enterprise::AuditLog.where('comment LIKE ?', 'commerce.%').order(:id) : []
  report({ audit: logs.map { |log| { event: log.comment, auditable_type: log.auditable_type, user_id: log.user_id, changes: log.audited_changes } } })
when 'stores'
  stores = Commerce::Store.order(:id).map do |store|
    { id: store.id, provider: store.provider, name: store.name, status: store.status, write_access: store.metadata['write_access'],
      order_actions: store.settings.to_h['order_actions'], actions_status: Commerce::OrderActions.store_status(store),
      scope: store.credentials.to_h['scope'] }
  end
  report({ stores: stores })
when 'sims'
  report({ zid_status_changes: ZidSim.status_changes, shopify_mutations: ShopifySim.mutations, shopify_operations: ShopifySim.operations,
           whatsapp_sent: ActionSims.whatsapp_sent, requests: RealtimeSims.requests })
when 'secrets'
  values = Commerce::Store.where.not(credentials: nil).flat_map { |store| store.credentials.values.grep(String) }
  values += ZidSim.webhooks(ZID_STORE).flat_map { |hook| hook['authentication'].values_at('username', 'password') }
  values += %w[E2E_SALLA_WEBHOOK_SECRET E2E_SALLA_CLIENT_SECRET E2E_ZID_CLIENT_SECRET E2E_SHOPIFY_CLIENT_SECRET].map { |name| ENV.fetch(name) }
  report({ secrets: values.select { |value| value.length >= 12 && value.exclude?(' ') }.uniq })
end
