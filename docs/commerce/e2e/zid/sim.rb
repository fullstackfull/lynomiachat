# The simulated Zid's controls for the Zid E2E (docs/commerce/17-zid-e2e.md), in a runner with ZidSim installed.
#
# Usage: rails runner docs/commerce/e2e/zid/sim.rb <command> [args]
#   configure on|off            the Super Admin Zid settings (secret from E2E_ZID_CLIENT_SECRET), switch on or off
#   reset                       remove Zid stores, the simulated Zid's state, Zid Redis keys and queued Zid jobs
#   queue                       queued Zid jobs by class
#   jobs                        run the queued Zid jobs (webhook registrations and deliveries) against the simulated Zid
#   zid_side <zid_store_id>     what Zid holds for the store: webhook subscriptions and the Basic Auth pair Lynomia gave it
#   requests                    requests the simulated Zid received, by method and path
#   refresh_mode ok|invalid_grant|malformed   how Zid answers refresh requests
#   expire <store_id>           make the store's tokens expire within the refresh window
#   refresh_race <store_id>     expire the tokens and read them from 10 threads at once
#   revoke <zid_store_id>       Zid invalidates every token of the store (as on uninstall)
#   order <zid_store_id> <order_id> <status_code> <payment_status>   an order changes in Zid
#   age <store_id>              make the store's cached data 5 minutes old
#   state                       Zid stores, links and audit events (no credentials)
require_relative 'zid_sim'
require 'sidekiq/api'

# Job processing happens here, so its log goes to a file the E2E scans for secrets like the server's.
Rails.logger = ActiveSupport::Logger.new(Rails.root.join('tmp/e2e_sim.log'))
ActiveJob::Base.logger = Rails.logger

ZID_JOBS = %w[Commerce::Zid::WebhookJob Commerce::Zid::WebhookRegistrationJob].freeze

def report(result) = puts("SIM #{result.to_json}")

def zid_store(id) = Commerce::Store.where(provider: 'zid').find(id)

def queued = Sidekiq::Queue.new('default').select { |job| ZID_JOBS.include?(job.item['wrapped']) }

command, *args = ARGV
case command
when 'configure'
  { 'ZID_ENABLED' => args.first == 'on', 'ZID_CLIENT_ID' => '4821', 'ZID_CLIENT_SECRET' => ENV.fetch('E2E_ZID_CLIENT_SECRET') }.each do |name, value|
    InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false)
  end
  GlobalConfig.clear_cache
  report({ zid_enabled: Commerce::Zid::Config.enabled? })
when 'reset'
  Commerce::Store.where(provider: 'zid').find_each(&:destroy!)
  ZidSim.reset!
  keys = []
  Redis::Alfred.scan_each(match: 'COMMERCE::ZID::*') { |key| keys << key }
  keys.each { |key| Redis::Alfred.delete(key) }
  queued.each(&:delete)
  report({ zid_stores: Commerce::Store.where(provider: 'zid').count, purged_keys: keys.size })
when 'queue'
  report(queued.map { |job| job.item['wrapped'] }.tally)
when 'jobs'
  ZidSim.install!
  results = queued.map do |job|
    job.item['wrapped'].constantize.perform_now(*job.item['args'].first['arguments'])
    job.delete
    "#{job.item['wrapped'].demodulize}: ok"
  rescue StandardError => e
    job.delete
    "#{job.item['wrapped'].demodulize}: #{e.class.name}: #{e.message}"
  end
  report({ processed: results })
when 'zid_side'
  hooks = ZidSim.webhooks(args.first)
  auth = hooks.first&.dig('authentication')
  report({ events: hooks.pluck('event'), target_urls: hooks.pluck('target_url').uniq, original_ids: hooks.pluck('original_id').uniq,
           username: auth&.dig('username'), password: auth&.dig('password') })
when 'requests'
  report(ZidSim.requests)
when 'refresh_mode'
  ZidSim.redis.set("#{ZidSim::PREFIX}::REFRESH_MODE", args.first)
  report({ refresh_mode: args.first })
when 'expire'
  store = zid_store(args.first)
  store.update!(credentials: store.credentials.merge('expires_at' => 10.days.from_now.utc.iso8601))
  report({ expires_at: store.credentials['expires_at'] })
when 'refresh_race'
  ZidSim.install!
  store = zid_store(args.first)
  store.update!(credentials: store.credentials.merge('expires_at' => 10.days.from_now.utc.iso8601))
  before = ZidSim.requests['POST /oauth/token'].to_i
  tokens = Array.new(10) do
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Commerce::Zid::TokenManager.new(Commerce::Store.find(store.id)).with_credentials { |credentials| credentials['access_token'] }
      end
    end
  end.map(&:value)
  report({ threads: tokens.size, distinct_tokens: tokens.uniq.size, token_requests: ZidSim.requests['POST /oauth/token'].to_i - before,
           saved: store.reload.credentials['access_token'] == tokens.first })
when 'revoke'
  ZidSim.revoke(args.first)
  report({ revoked: args.first })
when 'order'
  store, id, status, payment = args
  ZidSim.redis.set("#{ZidSim::PREFIX}::ORDER::#{store}::#{id}", { 'order_status' => { 'name' => status, 'code' => status }, 'payment_status' => payment }.to_json)
  report({ order: id, status: status, payment_status: payment })
when 'age'
  store = zid_store(args.first)
  keys = []
  Redis::Alfred.scan_each(match: "COMMERCE::V1::ACCOUNT::#{store.account_id}::STORE::#{store.id}::*") { |key| keys << key }
  keys.each do |key|
    entry = JSON.parse(Redis::Alfred.get(key))
    Redis::Alfred.setex(key, entry.merge('fetched_at' => 5.minutes.ago.utc.iso8601).to_json, 1.day)
  end
  report({ aged: keys.size })
when 'state'
  stores = Commerce::Store.where(provider: 'zid').order(:id).map do |store|
    { id: store.id, account_id: store.account_id, name: store.name, status: store.status, external_store_id: store.external_store_id,
      base_url: store.base_url, credential_fields: store.credentials&.keys, links: store.customer_links.count,
      webhook_ids: store.metadata.dig('zid_webhooks', 'ids')&.size, time_zone: store.metadata['time_zone'] }
  end
  audit = defined?(Enterprise::AuditLog) ? Enterprise::AuditLog.where("comment LIKE 'commerce.zid.%' OR comment LIKE 'commerce.store_%'").order(:id).pluck(:comment, :audited_changes) : []
  report({ stores: stores, audit: audit })
end
