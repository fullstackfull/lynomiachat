# Controls of the realtime E2E (docs/commerce/27-phase7-8-e2e.md), in a runner with the simulated stores installed. A
# delivery is what the store itself would send: the order changes on the store's side first, then the event is posted
# to the running Lynomia, authenticated as that provider authenticates it (Salla's signature with the app's webhook
# secret, Zid's Basic Auth pair Lynomia gave it, Shopify's HMAC with the app's client secret).
#
# Usage: rails runner docs/commerce/e2e/realtime/ctl.rb <command> [args]
#   reset                         remove every store and simulated state; WooCommerce alone switched on (its UI flow)
#   connect                       switch Salla, Zid and Shopify on and connect their stores to account A
#   deliver <provider> <order> <change…>   change the order in the store, then deliver its event
#   event <provider> <order> <claimed status>   deliver an event without changing the store (an out-of-order event)
#   replay <provider>             deliver the provider's last delivery again, byte for byte
#   burst <provider> <order> <n>  n events for the same customer at once
#   outage <provider> on|off      the provider answers every request with 503
#   revoke <provider>             the provider stops accepting the store's tokens
#   realtime on|off               the COMMERCE_REALTIME_ENABLED kill switch
#   state                         stores, links and the simulated stores' request counts (no credentials)
#   secrets                       the credentials to scan logs and pages for
require_relative 'sims'
require 'net/http'

Rails.logger = ActiveSupport::Logger.new(Rails.root.join('tmp/e2e_ctl.log'))
RealtimeSims.install!

BASE = 'http://localhost:3100'.freeze
ZID_STORE = '318001'.freeze
SHOP = 'lynomia-demo.myshopify.com'.freeze
LAST = 'E2E::REALTIME::LAST'.freeze

def report(result) = puts("SIM #{result.to_json}")

def account_a = Account.find_by!(name: 'Lynomia Demo A')

def admin_a = User.find_by!(email: 'admin_a@commerce.lynomia.local')

def post(path, body, headers)
  uri = URI("#{BASE}#{path}")
  request = Net::HTTP::Post.new(uri, headers.merge('Content-Type' => 'application/json'))
  request.body = body
  Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }.code.to_i
end

def deliver(provider, path, body, headers)
  RealtimeSims.redis.set("#{LAST}::#{provider}", { path: path, body: body, headers: headers }.to_json)
  post(path, body, headers)
end

def salla_event(order_id)
  body = { event: 'order.updated', merchant: SallaSim::MERCHANT['id'], created_at: Time.current.strftime('%F %T.%L'),
           data: { id: order_id.to_i, customer: { id: SallaSim::CUSTOMER_ID.to_i } } }.to_json
  deliver('salla', '/webhooks/salla', body, { 'X-Salla-Security-Strategy' => 'Signature',
                                              'X-Salla-Signature' => OpenSSL::HMAC.hexdigest('SHA256', ENV.fetch('E2E_SALLA_WEBHOOK_SECRET'), body) })
end

def zid_event(order_id, status)
  auth = ZidSim.webhooks(ZID_STORE).last.fetch('authentication')
  body = { id: order_id.to_i, store_id: ZID_STORE.to_i, order_status: { name: status, code: status }, customer: { id: 90_001 },
           updated_at: Time.current.strftime('%F %T.%L') }.to_json
  deliver('zid', "/webhooks/zid/#{ZID_STORE}", body,
          { 'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(auth['username'], auth['password']) })
end

def shopify_event(number, fulfillment)
  order = ShopifySim.all_orders(SHOP).find { |raw| raw['name'] == "##{number}" }
  body = { id: order['legacyResourceId'].to_i, name: order['name'], fulfillment_status: fulfillment, customer: { id: 7001 },
           updated_at: Time.current.iso8601(3) }.to_json
  deliver('shopify', '/webhooks/shopify_commerce', body,
          { 'X-Shopify-Topic' => 'orders/updated', 'X-Shopify-Shop-Domain' => SHOP, 'X-Shopify-Webhook-Id' => SecureRandom.uuid,
            'X-Shopify-Triggered-At' => Time.current.iso8601(3),
            'X-Shopify-Hmac-Sha256' => Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', ENV.fetch('E2E_SHOPIFY_CLIENT_SECRET'), body)) })
end

def event(provider, order, status)
  case provider
  when 'salla' then salla_event(order)
  when 'zid' then zid_event(order, status)
  when 'shopify' then shopify_event(order, status)
  end
end

def configure(on)
  { 'SALLA_ENABLED' => on, 'SALLA_APP_ID' => '1234567890', 'SALLA_CLIENT_ID' => 'e2e-salla-client-id',
    'SALLA_CLIENT_SECRET' => ENV.fetch('E2E_SALLA_CLIENT_SECRET'), 'SALLA_WEBHOOK_SECRET' => ENV.fetch('E2E_SALLA_WEBHOOK_SECRET'),
    'ZID_ENABLED' => on, 'ZID_CLIENT_ID' => '4821', 'ZID_CLIENT_SECRET' => ENV.fetch('E2E_ZID_CLIENT_SECRET'),
    'SHOPIFY_COMMERCE_ENABLED' => on, 'SHOPIFY_COMMERCE_CLIENT_ID' => ShopifySim::CLIENT_ID,
    'SHOPIFY_COMMERCE_CLIENT_SECRET' => ENV.fetch('E2E_SHOPIFY_CLIENT_SECRET') }.each do |name, value|
    InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false)
  end
  InstallationConfig.where(name: 'COMMERCE_REALTIME_ENABLED').destroy_all
  GlobalConfig.clear_cache
end

def reset
  Commerce::Store.find_each(&:destroy!)
  [SallaSim, ZidSim, ShopifySim].each(&:reset!)
  %w[COMMERCE::* E2E::REALTIME::*].each do |pattern|
    keys = []
    Redis::Alfred.scan_each(match: pattern) { |key| keys << key }
    keys.each { |key| Redis::Alfred.delete(key) }
  end
  Sidekiq::Queue.all.each(&:clear)
  Sidekiq::ScheduledSet.new.clear
  Enterprise::AuditLog.where('comment LIKE ?', 'commerce.%').delete_all if defined?(Enterprise::AuditLog)
  Account.find_each { |account| account.update!(locale: 'en') && account.enable_features!('lynomia_commerce') }
end

def connect_salla
  code = Commerce::Salla::ConnectionCode.create(account: account_a, user: admin_a)[:code]
  authorize = SallaSim.fixture('app_store_authorize.json').deep_merge(
    'created_at' => Time.current.strftime('%F %T'),
    'data' => { 'access_token' => 'e2e-access-m1', 'refresh_token' => 'e2e-refresh-m1', 'expires' => 14.days.from_now.to_i }
  )
  settings = SallaSim.fixture('app_settings_updated.json').deep_merge('data' => { 'settings' => { 'lynomia_connection_code' => code } })
  [authorize, settings].each { |payload| Commerce::Salla::Installation.new(payload).process }
end

def wait_for(seconds = 30)
  deadline = Time.current + seconds
  sleep 0.5 until yield || Time.current > deadline
end

require 'sidekiq/api'
command, *args = ARGV
case command
when 'reset'
  reset
  configure(false)
  report({ stores: Commerce::Store.count })
when 'connect'
  configure(true)
  connect_salla
  Commerce::Zid::Authorization.new(account: account_a, user: admin_a).connect("e2e-zid-code-#{ZID_STORE}-#{SecureRandom.hex(4)}")
  Commerce::Shopify::Authorization.new(account: account_a, user: admin_a).connect(SHOP, "e2e-shopify-code-#{SecureRandom.hex(4)}")
  wait_for { ZidSim.webhooks(ZID_STORE).any? }
  report({ stores: Commerce::Store.order(:id).pluck(:id, :provider, :name, :status), zid_webhooks: ZidSim.webhooks(ZID_STORE).size })
when 'deliver'
  provider, order, *change = args
  case provider
  when 'salla' then SallaSim.change_order(order, *change)
  when 'zid' then ZidSim.redis.set("#{ZidSim::PREFIX}::ORDER::#{ZID_STORE}::#{order}",
                                   { 'order_status' => { 'name' => change[0], 'code' => change[0] }, 'payment_status' => change[1] }.to_json)
  when 'shopify'
    raw = ShopifySim.all_orders(SHOP).find { |candidate| candidate['name'] == "##{order}" }
    ShopifySim.redis.set("#{ShopifySim::PREFIX}::ORDER::#{SHOP}::#{raw['legacyResourceId']}",
                         { 'displayFinancialStatus' => change[0], 'displayFulfillmentStatus' => change[1] }.to_json)
  end
  status = event(provider, order, change.first)
  report({ provider: provider, order: order, status: status, delivered_at: (Time.current.to_f * 1000).round })
when 'event'
  provider, order, claimed = args
  status = event(provider, order, claimed)
  report({ provider: provider, order: order, status: status, delivered_at: (Time.current.to_f * 1000).round })
when 'replay'
  last = JSON.parse(RealtimeSims.redis.get("#{LAST}::#{args.first}"))
  report({ provider: args.first, status: post(last['path'], last['body'], last['headers']) })
when 'burst'
  provider, order, count = args
  statuses = Array.new(count.to_i) { |index| Thread.new { event(provider, order, "burst-#{index}") } }.map(&:value)
  report({ provider: provider, statuses: statuses.tally })
when 'outage'
  RealtimeSims.outage(args.first, args.last == 'on')
  report({ outage: args.first, on: args.last == 'on' })
when 'revoke'
  case args.first
  when 'salla' then SallaSim.revoke('e2e-access-m1')
  when 'zid' then ZidSim.revoke(ZID_STORE)
  when 'shopify' then ShopifySim.revoke(SHOP)
  end
  report({ revoked: args.first })
when 'realtime'
  InstallationConfig.where(name: 'COMMERCE_REALTIME_ENABLED').first_or_initialize.update!(value: args.first == 'on', locked: false)
  GlobalConfig.clear_cache
  report({ realtime: Commerce::Realtime.enabled? })
when 'state'
  stores = Commerce::Store.order(:id).map do |store|
    { id: store.id, account_id: store.account_id, provider: store.provider, name: store.name, status: store.status,
      realtime: store.metadata['realtime']&.slice('status', 'registered_at')&.merge('webhooks' => store.metadata.dig('realtime', 'webhook_ids')&.size) }
  end
  links = Commerce::CustomerLink.order(:id).map { |link| { store_id: link.commerce_store_id, contact_id: link.contact_id, match_source: link.match_source } }
  report({ stores: stores, links: links, requests: RealtimeSims.requests })
when 'secrets'
  values = Commerce::Store.where.not(credentials: nil).flat_map { |store| store.credentials.values.grep(String) }
  values += ZidSim.webhooks(ZID_STORE).flat_map { |hook| hook['authentication'].values_at('username', 'password') }
  values += %w[E2E_SALLA_WEBHOOK_SECRET E2E_SALLA_CLIENT_SECRET E2E_ZID_CLIENT_SECRET E2E_SHOPIFY_CLIENT_SECRET].map { |name| ENV.fetch(name) }
  report({ secrets: values.select { |value| value.length >= 12 }.uniq })
end
