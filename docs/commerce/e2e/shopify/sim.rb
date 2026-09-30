# The simulated Shopify's controls for the Shopify Commerce E2E (docs/commerce/22-shopify-e2e.md), in a runner with
# ShopifySim installed.
#
# Usage: rails runner docs/commerce/e2e/shopify/sim.rb <command> [args]
#   configure on|off            the Super Admin Shopify Commerce settings (secret from E2E_SHOPIFY_CLIENT_SECRET), switch on or off
#   legacy_config               the legacy Shopify integration's settings, as a fingerprint (values hashed)
#   legacy_hook <account> <shop> on|off   a legacy Shopify integration hook for the shop in the account
#   reset                       remove Shopify Commerce stores, the simulated Shopify's state, Commerce Shopify Redis keys and jobs
#   queue                       queued Shopify Commerce jobs by class
#   jobs                        run the queued Shopify Commerce webhook jobs
#   requests                    requests the simulated Shopify received, by path; GraphQL operations; expiring flags sent
#   grant_mode ok|non_expiring|write_scope   how Shopify answers the next code exchanges
#   refresh_mode ok|invalid|timeout_once|5xx_once   how Shopify answers refresh requests
#   gql_mode ok|denied|throttled   how the GraphQL API answers (denied: protected customer data not approved)
#   expire <store_id>           the access token expired: Lynomia's expiry and Shopify's both in the past
#   invalidate_access <shop>    Shopify rejects the shop's current access token before the expiry Lynomia knows
#   refresh_race <store_id>     expire the token and read it from 10 threads at once
#   revoke <shop>               the shop uninstalled the app: Shopify invalidates every token of the shop
#   order <shop> <order_number> <financial> <fulfillment>   an order changes in Shopify
#   age <store_id>              make the store's cached data 5 minutes old
#   state                       Shopify Commerce stores, links and audit events (no credentials)
require_relative 'shopify_sim'
require 'sidekiq/api'

# Job processing happens here, so its log goes to a file the E2E scans for secrets like the server's.
Rails.logger = ActiveSupport::Logger.new(Rails.root.join('tmp/e2e_sim.log'))
ActiveJob::Base.logger = Rails.logger

JOBS = %w[Commerce::Shopify::WebhookJob].freeze
LEGACY = %w[ENABLE_SHOPIFY_INTEGRATION SHOPIFY_CLIENT_ID SHOPIFY_CLIENT_SECRET SHOPIFY_APP_STORE_URL].freeze

def report(result) = puts("SIM #{result.to_json}")

def shopify_store(id) = Commerce::Store.where(provider: 'shopify').find(id)

def queued = Sidekiq::Queue.new('default').select { |job| JOBS.include?(job.item['wrapped']) }

command, *args = ARGV
case command
when 'configure'
  { 'SHOPIFY_COMMERCE_ENABLED' => args.first == 'on', 'SHOPIFY_COMMERCE_CLIENT_ID' => ShopifySim::CLIENT_ID,
    'SHOPIFY_COMMERCE_CLIENT_SECRET' => ENV.fetch('E2E_SHOPIFY_CLIENT_SECRET') }.each do |name, value|
    InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false)
  end
  GlobalConfig.clear_cache
  report({ shopify_commerce_enabled: Commerce::Shopify::Config.enabled? })
when 'legacy_config'
  values = LEGACY.index_with { |name| InstallationConfig.find_by(name: name)&.value }
  report({ fingerprint: Digest::SHA256.hexdigest(values.to_json), hooks: Integrations::Hook.where(app_id: 'shopify').count })
when 'legacy_hook'
  account, shop, switch = args
  hooks = Integrations::Hook.where(account_id: account, app_id: 'shopify', reference_id: shop)
  switch == 'on' ? hooks.first_or_create!(access_token: 'e2e-legacy-shpat', status: :enabled, settings: { scope: 'read_orders' }) : hooks.destroy_all
  report({ legacy_hooks: Integrations::Hook.where(app_id: 'shopify').pluck(:account_id, :reference_id, :status) })
when 'reset'
  Commerce::Store.where(provider: 'shopify').find_each(&:destroy!)
  ShopifySim.reset!
  keys = []
  Redis::Alfred.scan_each(match: 'COMMERCE::SHOPIFY::*') { |key| keys << key }
  keys.each { |key| Redis::Alfred.delete(key) }
  queued.each(&:delete)
  report({ shopify_stores: Commerce::Store.where(provider: 'shopify').count, purged_keys: keys.size })
when 'queue'
  report(queued.map { |job| job.item['wrapped'] }.tally)
when 'jobs'
  ShopifySim.install!
  results = queued.map do |job|
    job.item['wrapped'].constantize.perform_now(*job.item['args'].first['arguments'])
    job.delete
    "#{job.item['args'].first['arguments'].first}: ok"
  rescue StandardError => e
    job.delete
    "#{job.item['wrapped'].demodulize}: #{e.class.name}: #{e.message}"
  end
  report({ processed: results })
when 'requests'
  report({ requests: ShopifySim.requests, operations: ShopifySim.operations, expiring: ShopifySim.expiring })
when 'grant_mode', 'refresh_mode', 'gql_mode'
  ShopifySim.redis.set("#{ShopifySim::PREFIX}::#{command.upcase}", args.first)
  report({ command => args.first })
when 'expire'
  store = shopify_store(args.first)
  store.update!(credentials: store.credentials.merge('access_token_expires_at' => 1.minute.ago.utc.iso8601))
  ShopifySim.invalidate_access(URI(store.base_url).host)
  report({ access_token_expires_at: store.credentials['access_token_expires_at'] })
when 'invalidate_access'
  ShopifySim.invalidate_access(args.first)
  report({ invalidated: args.first })
when 'refresh_race'
  ShopifySim.install!
  store = shopify_store(args.first)
  store.update!(credentials: store.credentials.merge('access_token_expires_at' => 1.minute.ago.utc.iso8601))
  before = ShopifySim.requests['POST /admin/oauth/access_token'].to_i
  tokens = Array.new(10) do
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Commerce::Shopify::TokenManager.new(Commerce::Store.find(store.id)).with_credentials { |credentials| credentials['access_token'] }
      end
    end
  end.map(&:value)
  report({ threads: tokens.size, distinct_tokens: tokens.uniq.size, token_requests: ShopifySim.requests['POST /admin/oauth/access_token'].to_i - before,
           saved: store.reload.credentials['access_token'] == tokens.first })
when 'revoke'
  ShopifySim.revoke(args.first)
  report({ revoked: args.first })
when 'order'
  shop, number, financial, fulfillment = args
  order = ShopifySim.all_orders(shop).find { |raw| raw['name'] == "##{number}" }
  ShopifySim.redis.set("#{ShopifySim::PREFIX}::ORDER::#{shop}::#{order['legacyResourceId']}",
                       { 'displayFinancialStatus' => financial, 'displayFulfillmentStatus' => fulfillment }.to_json)
  report({ order: number, financial: financial, fulfillment: fulfillment })
when 'age'
  store = shopify_store(args.first)
  keys = []
  Redis::Alfred.scan_each(match: "COMMERCE::V1::ACCOUNT::#{store.account_id}::STORE::#{store.id}::*") { |key| keys << key }
  keys.each do |key|
    entry = JSON.parse(Redis::Alfred.get(key))
    Redis::Alfred.setex(key, entry.merge('fetched_at' => 5.minutes.ago.utc.iso8601).to_json, 1.day)
  end
  report({ aged: keys.size })
when 'state'
  stores = Commerce::Store.where(provider: 'shopify').order(:id).map do |store|
    expiry = store.credentials&.values_at('access_token_expires_at', 'refresh_token_expires_at')
    { id: store.id, account_id: store.account_id, name: store.name, status: store.status, external_store_id: store.external_store_id,
      base_url: store.base_url, credential_fields: store.credentials&.keys, expires: expiry, scope: store.credentials&.dig('scope'),
      token_generation: store.credentials&.dig('access_token').to_s[/-(\d+)\z/, 1], links: store.customer_links.pluck(:external_customer_id) }
  end
  audit = if defined?(Enterprise::AuditLog)
            Enterprise::AuditLog.where("comment LIKE 'commerce.shopify.%' OR comment LIKE 'commerce.store_%'").order(:id).pluck(:comment, :audited_changes)
          else
            []
          end
  report({ stores: stores, audit: audit })
end
