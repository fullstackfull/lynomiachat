# Simulated-Salla harness for the Salla E2E (docs/commerce/13-salla-e2e.md). Salla's hosts are not reachable from the
# test environment, so this runner answers Salla's HTTP in-process with WebMock, from payloads in Salla's documented
# shapes (spec/fixtures/files/commerce/salla). Nothing else is simulated: webhook deliveries reach the running app over
# HTTP and are signed with the installation's own webhook secret, and the Lynomia code under test runs unchanged.
#
# Usage: rails runner docs/commerce/e2e/salla/sim.rb <command> [args]
#   configure on|off           the Super Admin Salla settings (secrets from E2E_SALLA_* env), switch on or off
#   reset                      remove Salla stores, Salla Redis state and queued Salla jobs
#   super_admin                create the E2E super admin
#   queue                      number of queued Salla webhook jobs
#   jobs                       run the queued Salla webhook jobs (Salla answered from fixtures)
#   warm <store_id> <conversation_id>...   open the panel once per conversation (auto-link + cache)
#   age <store_id>             make the store's cached data 5 minutes old
#   backoff <merchant_id>      Salla reports the merchant as rate limited
#   refresh_fails <store_id>   expire the token and let Salla reject the refresh token
#   refresh_race <store_id>    expire the token and read it from 10 threads at once
#   state                      Salla stores, links and audit events (no credentials)
require 'webmock'
require 'sidekiq/api'
include WebMock::API # rubocop:disable Style/MixinUsage

# Job processing happens here, so its log goes to a file the E2E scans for secrets like the server's.
Rails.logger = ActiveSupport::Logger.new(Rails.root.join('tmp/e2e_sim.log'))
ActiveJob::Base.logger = Rails.logger

FIXTURES = Rails.root.join('spec/fixtures/files/commerce/salla')
API = 'https://api.salla.dev/admin/v2'.freeze
MERCHANTS = {
  'e2e-access-m1' => { id: 1_234_509_876, name: 'متجر الورد', domain: 'https://salla.sa/rose-store' },
  'e2e-access-m1-new' => { id: 1_234_509_876, name: 'متجر الورد', domain: 'https://salla.sa/rose-store' },
  'e2e-access-m1-refreshed' => { id: 1_234_509_876, name: 'متجر الورد', domain: 'https://salla.sa/rose-store' },
  'e2e-access-m2' => { id: 1_234_509_877, name: 'Salla Demo Two', domain: 'https://salla.sa/demo-two' }
}.freeze

def fixture(name) = JSON.parse(FIXTURES.join(name).read)

def envelope(data) = { status: 200, body: { status: 200, success: true, data: data }.to_json, headers: { 'X-RateLimit-Remaining' => '100' } }

def stub_salla!
  WebMock.enable!
  WebMock.disable_net_connect!
  Resolv.singleton_class.prepend(Module.new do
    def getaddresses(name) = %w[api.salla.dev accounts.salla.sa].include?(name) ? ['93.184.216.40'] : super
  end)
  user_info = fixture('user_info.json')
  stub_request(:get, 'https://accounts.salla.sa/oauth2/user/info').to_return do |request|
    merchant = MERCHANTS.fetch(request.headers['Authorization'].delete_prefix('Bearer '))
    { status: 200, body: user_info.merge('merchant' => user_info['merchant'].merge(merchant.stringify_keys)).to_json }
  end
  customers = fixture('customers.json')['data']
  twins = [customers.first.merge('id' => 1_227_534_700, 'first_name' => 'Sara', 'last_name' => 'Ali', 'mobile' => 550_000_111, 'email' => 'sara@example.com'),
           customers.first.merge('id' => 1_227_534_701, 'first_name' => 'Noor', 'last_name' => 'Ali', 'mobile' => 550_000_111, 'email' => 'noor@example.com')]
  stub_request(:get, "#{API}/customers").with(query: hash_including({})).to_return do |request|
    keyword = Rack::Utils.parse_query(request.uri.query)['keyword']
    envelope({ '551112233' => customers.first(1), '550000111' => twins }.fetch(keyword, []))
  end
  orders = fixture('orders.json')['data']
  stub_request(:get, "#{API}/orders").with(query: hash_including({})).to_return do |request|
    envelope(Rack::Utils.parse_query(request.uri.query)['customer_id'] == '1227534533' ? orders : [])
  end
  shipments = fixture('shipments.json')['data']
  untracked = shipments.first.merge('id' => 52_000, 'order_id' => 1_861_092_001, 'courier_name' => 'Salla Delivery', 'trackable' => false,
                                    'tracking_number' => nil, 'tracking_link' => nil, 'status' => 'delivered')
  stub_request(:get, "#{API}/shipments").with(query: hash_including({})).to_return do |request|
    envelope({ '1861092002' => shipments, '1861092001' => [untracked] }.fetch(Rack::Utils.parse_query(request.uri.query)['order_id'], []))
  end
end

def salla_store(id) = Commerce::Store.where(provider: 'salla').find(id)

# The E2E script reads the line starting with "SIM ".
def report(result) = puts("SIM #{result.to_json}")

def refresh_log = WebMock::RequestRegistry.instance.requested_signatures.hash.select { |signature, _| signature.uri.path == '/oauth2/token' }

command, *args = ARGV
case command
when 'configure'
  values = { 'SALLA_ENABLED' => args.first == 'on', 'SALLA_APP_ID' => '1234567890', 'SALLA_CLIENT_ID' => 'e2e-salla-client-id',
             'SALLA_CLIENT_SECRET' => ENV.fetch('E2E_SALLA_CLIENT_SECRET'), 'SALLA_WEBHOOK_SECRET' => ENV.fetch('E2E_SALLA_WEBHOOK_SECRET') }
  values.each { |name, value| InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false) }
  GlobalConfig.clear_cache
  report({ salla_enabled: Commerce::Salla::Config.enabled? })
when 'reset'
  Commerce::Store.where(provider: 'salla').find_each(&:destroy!)
  keys = []
  Redis::Alfred.scan_each(match: 'COMMERCE::SALLA::*') { |key| keys << key }
  keys.each { |key| Redis::Alfred.delete(key) }
  Sidekiq::Queue.new('default').each { |job| job.delete if job.item['wrapped'] == 'Commerce::Salla::WebhookJob' }
  report({ salla_stores: Commerce::Store.where(provider: 'salla').count, purged_keys: keys.size })
when 'super_admin'
  SuperAdmin.find_or_create_by!(email: 'super@commerce.lynomia.local') do |user|
    user.assign_attributes(name: 'Super Admin', password: 'Password1!x', password_confirmation: 'Password1!x', confirmed_at: Time.current)
  end
  report({ super_admin: true })
when 'queue'
  report({ queued: Sidekiq::Queue.new('default').count { |job| job.item['wrapped'] == 'Commerce::Salla::WebhookJob' } })
when 'jobs'
  stub_salla!
  results = Sidekiq::Queue.new('default').select { |job| job.item['wrapped'] == 'Commerce::Salla::WebhookJob' }.map do |job|
    Commerce::Salla::WebhookJob.perform_now(job.item['args'].first['arguments'].first)
    job.delete
    'ok'
  rescue StandardError => e
    job.delete
    "#{e.class.name}: #{e.message}"
  end
  report({ processed: results })
when 'warm'
  stub_salla!
  store = salla_store(args.shift)
  states = args.map do |display_id|
    conversation = store.account.conversations.find_by!(display_id: display_id)
    Commerce::ConversationPanel.new(store: store, conversation: conversation, user: nil).show[:state]
  end
  report({ warmed: states })
when 'age'
  store = salla_store(args.first)
  keys = []
  Redis::Alfred.scan_each(match: "COMMERCE::V1::ACCOUNT::#{store.account_id}::STORE::#{store.id}::*") { |key| keys << key }
  keys.each do |key|
    entry = JSON.parse(Redis::Alfred.get(key))
    Redis::Alfred.setex(key, entry.merge('fetched_at' => 5.minutes.ago.utc.iso8601).to_json, 1.day)
  end
  report({ aged: keys.size })
when 'backoff'
  Redis::Alfred.set("COMMERCE::SALLA::MERCHANT::#{args.first}::BACKOFF", 1, ex: 60)
  report({ backoff: args.first })
when 'refresh_fails'
  stub_salla!
  store = salla_store(args.first)
  store.update!(credentials: store.credentials.merge('access_token_expires_at' => 1.hour.from_now.utc.iso8601))
  stub_request(:post, 'https://accounts.salla.sa/oauth2/token').to_return(status: 400, body: '{"error":"invalid_grant"}')
  error = begin
    Commerce::Salla::TokenManager.new(store).access_token
    nil
  rescue Commerce::Error => e
    e.as_json
  end
  store.reload
  report({ error: error, status: store.status, refresh_token_kept: store.credentials.key?('refresh_token'), token_requests: refresh_log.values.sum })
when 'refresh_race'
  stub_salla!
  store = salla_store(args.first)
  store.update!(credentials: store.credentials.merge('access_token_expires_at' => 1.hour.from_now.utc.iso8601))
  previous_refresh = store.credentials['refresh_token']
  stub_request(:post, 'https://accounts.salla.sa/oauth2/token').to_return do
    sleep 0.3
    { status: 200, body: { access_token: 'e2e-access-m1-refreshed', refresh_token: 'e2e-refresh-m1-refreshed', token_type: 'bearer',
                           expires: 14.days.from_now.to_i, scope: 'offline_access customers.read orders.read shipping.read' }.to_json }
  end
  tokens = Array.new(10) do
    Thread.new { ActiveRecord::Base.connection_pool.with_connection { Commerce::Salla::TokenManager.new(Commerce::Store.find(store.id)).access_token } }
  end.map(&:value)
  store.reload
  requests = WebMock::RequestRegistry.instance.requested_signatures.hash.select { |signature, _| signature.uri.path == '/oauth2/token' }
  report({ threads: tokens.size, distinct_tokens: tokens.uniq.size, token_requests: requests.values.sum,
         old_refresh_token_sent_times: requests.select { |signature, _| signature.body.include?(previous_refresh) }.values.sum,
         new_refresh_token_saved: store.credentials['refresh_token'] == 'e2e-refresh-m1-refreshed' })
when 'state'
  stores = Commerce::Store.where(provider: 'salla').order(:id).map do |store|
    { id: store.id, account_id: store.account_id, name: store.name, status: store.status, external_store_id: store.external_store_id,
      credential_fields: store.credentials&.keys, links: store.customer_links.count }
  end
  audit = defined?(Enterprise::AuditLog) ? Enterprise::AuditLog.where("comment LIKE 'commerce.salla.%'").order(:id).pluck(:comment, :audited_changes) : []
  report({ stores: stores, audit: audit })
end
