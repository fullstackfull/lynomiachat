require 'rake'
require 'rails_helper'

# The legacy Shopify retirement destroys no merchant data; this task is how a human finds out what is there
# before deciding (docs/product-refinement/02-shopify-retirement.md §5).
#
# Two things are asserted and neither is cosmetic: the report must be CORRECT about whether a shop has already
# moved to Commerce, and it must never put a Shopify Admin API token on an operator's terminal.
RSpec.describe Rake::Task do
  describe 'lynomia:shopify:legacy_audit' do
    # A Commerce::Store will not persist credentials without Active Record encryption, and two of these
    # examples need a real one to prove the already-migrated match.
    subject(:task) { described_class['lynomia:shopify:legacy_audit'] }

    include_context 'with commerce encryption'

    let(:account) { create(:account, name: 'Hisham Test') }
    let(:shop) { 'lynomia-demo.myshopify.com' }
    let(:token) { 'shpat_thisisaverysecretlegacytoken' }

    before { task.reenable }

    it 'says so plainly when there is nothing to migrate' do
      expect { task.invoke }.to output(/No legacy Shopify installations/).to_stdout
    end

    it 'reports a legacy installation that has not moved to Commerce' do
      create(:integrations_hook, account: account, app_id: 'shopify', reference_id: shop, access_token: token)

      expect { task.invoke }.to output(/#{Regexp.escape(shop)}.*commerce_store=no.*migrate/m).to_stdout
    end

    # The join key is the SHOP DOMAIN via commerce_stores.base_url, not external_store_id -- which for Shopify
    # is the numeric shop id from the GID and would never match a hook's reference_id. If that regresses, every
    # row reads `migrate` and the report is confidently wrong, so it is asserted directly.
    it 'recognises a shop that already has a Commerce store in the same account' do
      create(:integrations_hook, account: account, app_id: 'shopify', reference_id: shop, access_token: token)
      create(:commerce_store, account: account, provider: 'shopify', base_url: "https://#{shop}",
                              external_store_id: '123456789', status: :active)

      expect { task.invoke }.to output(/commerce_store=yes.*already_migrated/m).to_stdout
    end

    it "does not treat another account's Commerce store as this account's migration" do
      create(:integrations_hook, account: account, app_id: 'shopify', reference_id: shop, access_token: token)
      create(:commerce_store, account: create(:account), provider: 'shopify', base_url: "https://#{shop}",
                              external_store_id: '987654321', status: :active)

      expect { task.invoke }.to output(/commerce_store=no.*migrate/m).to_stdout
    end

    it 'never prints the access token' do
      create(:integrations_hook, account: account, app_id: 'shopify', reference_id: shop, access_token: token)

      expect { task.invoke }.not_to output(/#{Regexp.escape(token)}|shpat_/).to_stdout
    end

    # Stronger than "the token is absent from the output": the column is never even SELECTed, so it is not
    # decrypted, not held in memory and cannot reach a log or an exception backtrace either.
    it 'never selects the access_token column' do
      create(:integrations_hook, account: account, app_id: 'shopify', reference_id: shop, access_token: token)

      statements = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        statements << payload[:sql]
      end
      begin
        task.invoke
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      hook_reads = statements.select { |sql| sql.include?('integrations_hooks') }
      expect(hook_reads).not_to be_empty
      expect(hook_reads.join(' ')).not_to include('access_token')
    end
  end
end
