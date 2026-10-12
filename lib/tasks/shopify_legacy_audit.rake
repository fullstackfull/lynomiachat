# What legacy Shopify installations exist, so a human can decide what happens to each one.
#
# The legacy Shopify integration was retired as a PRODUCT SURFACE (docs/product-refinement/02-shopify-retirement.md).
# Its DATA was deliberately not touched: an `Integrations::Hook` with `app_id = 'shopify'` holds a real
# merchant's authorization, and destroying one silently would take away a connection the merchant granted.
#
# PRODUCTION IS EXPECTED TO HAVE NONE. The product owner confirmed no Shopify store is connected in
# production, so this task's job is to VERIFY that rather than to drive a migration. A zero result is the
# expected one and prints SAFE_TO_RETIRE.
#
# This is why there is deliberately no migration UI, no re-authorization workflow and no merchant transition
# process anywhere in the retirement: building one for zero merchants would be inventing a product nobody
# needs. The per-row recommendations below exist only for the case the audit UNEXPECTEDLY finds rows -- then a
# human reads them and decides, one account at a time.
#
# It only reads. There is no counterpart task that deletes.
#
# NEVER PRINTS A SECRET. `Integrations::Hook#access_token` is the Shopify Admin API token and is an encrypted
# column (app/models/integrations/hook.rb:26). This task does not select it, does not decrypt it and does not
# reference it -- `select` names the four columns it needs, so the token is not even loaded into memory.
# `spec/lib/tasks/shopify_legacy_audit_spec.rb` asserts that.
#
# Usage:
#   bundle exec rake lynomia:shopify:legacy_audit
#   FORMAT=csv bundle exec rake lynomia:shopify:legacy_audit > legacy-shopify.csv
# Namespaced rather than left at the top level: a bare constant in a .rake file lands on Object and warns
# "already initialized" every time Rake reloads the file, which is what the other rollup tasks here already
# do wrong. Following lib/tasks/reporting_events_rollup.rake's module convention instead.
module ShopifyLegacyAudit
  # The four columns the report needs. Named explicitly so adding a column to the table can never widen what
  # this task reads, and so `access_token` is provably absent from the query.
  COLUMNS = %i[id account_id reference_id status].freeze
end

# rubocop:disable Metrics/BlockLength
namespace :lynomia do
  namespace :shopify do
    # A Shopify Commerce store is matched to a legacy hook by SHOP DOMAIN, per account.
    #
    # Not by `external_store_id`: for Shopify that column holds the numeric shop id out of Shopify's GID
    # (custom/app/services/commerce/shopify/oauth.rb:44-48), while a legacy hook's `reference_id` holds the
    # myshopify domain. Comparing them would never match and every row would read `migrate`, which is a
    # quietly wrong report rather than a missing one.
    #
    # The domain a Commerce store carries is its `base_url`, written as "https://<shop>" at
    # custom/app/services/commerce/shopify/authorization.rb:40,47.
    #
    # Per account on purpose: another account holding this shop in Commerce does not migrate THIS account.
    def commerce_shops_by_account
      Commerce::Store.where(provider: 'shopify')
                     .where.not(status: :disconnected)
                     .pluck(:account_id, :base_url)
                     .each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |(account_id, base_url), index|
        index[account_id] << base_url.to_s.delete_prefix('https://').delete_prefix('http://').downcase
      end
    end

    # What to do with each legacy installation. A recommendation, not an action.
    def recommendation_for(account_id, shop, commerce_shops)
      return 'already_migrated' if commerce_shops[account_id].include?(shop)

      'migrate'
    end

    desc 'Report legacy Shopify integration installations (read-only, never prints tokens)'
    task legacy_audit: :environment do
      hooks = Integrations::Hook.where(app_id: 'shopify').select(*ShopifyLegacyAudit::COLUMNS).to_a

      if hooks.empty?
        puts 'legacy Shopify installations = 0'
        puts ''
        puts 'SAFE_TO_RETIRE'
        puts ''
        puts 'Nothing to migrate. The canonical Commerce Shopify architecture is the only Shopify path on this'
        puts 'installation, and no merchant transition is required.'
        next
      end

      # One query for the names and one for the Commerce stores, rather than two per row.
      names = Account.where(id: hooks.map(&:account_id).uniq).pluck(:id, :name).to_h
      commerce_shops = commerce_shops_by_account

      rows = hooks.map do |hook|
        shop = hook.reference_id.to_s.downcase
        migrated = commerce_shops[hook.account_id].include?(shop)
        {
          hook_id: hook.id,
          account_id: hook.account_id,
          account_name: names[hook.account_id].to_s,
          shop_domain: shop,
          hook_status: hook.status.to_s,
          commerce_store: migrated ? 'yes' : 'no',
          recommendation: recommendation_for(hook.account_id, shop, commerce_shops)
        }
      end

      if ENV.fetch('FORMAT', nil) == 'csv'
        puts rows.first.keys.join(',')
        rows.each { |row| puts row.values.map { |value| value.to_s.tr(',', ' ') }.join(',') }
        next
      end

      puts "legacy Shopify installations = #{rows.count}"
      puts ''
      puts 'LEGACY_RECORDS_FOUND'
      puts ''
      puts 'This was NOT expected: production was recorded as having no Shopify stores connected. Do not delete'
      puts 'anything on the strength of this report alone -- confirm with the product owner first.'
      puts ''
      puts "across #{rows.map { |r| r[:account_id] }.uniq.count} account(s):"
      puts ''
      rows.each do |row|
        puts format('  hook %<hook>-7s account %<account>-6s %<name>-28s shop=%<shop>-40s commerce_store=%<store>-4s -> %<rec>s',
                    hook: row[:hook_id], account: row[:account_id], name: row[:account_name].truncate(26),
                    shop: row[:shop_domain], store: row[:commerce_store], rec: row[:recommendation])
      end
      puts ''
      puts 'recommendation:'
      puts '  migrate          the merchant must connect this store under Settings -> Commerce. Reauthorization'
      puts '                   is required: Commerce uses its own Shopify app and never reuses a legacy token.'
      puts '  already_migrated a Commerce store already exists for this shop. The legacy row is redundant and'
      puts '                   can be deleted once somebody confirms the Commerce store is working.'
      puts ''
      puts 'No row was changed. Deleting one is a separate, deliberate action.'
    end
  end
end
# rubocop:enable Metrics/BlockLength
