FactoryBot.define do
  factory :commerce_store, class: 'Commerce::Store' do
    account
    provider { 'woocommerce' }
    sequence(:name) { |n| "Store #{n}" }
    sequence(:base_url) { |n| "https://store#{n}.example.com" }
    external_store_id { URI(base_url).host }
    credentials { { 'consumer_key' => 'ck_factory', 'consumer_secret' => 'cs_factory' } }

    # A Salla store is its merchant id; its credentials are the app installation's OAuth tokens.
    trait :salla do
      provider { 'salla' }
      sequence(:external_store_id) { |n| (1_305_146_700 + n).to_s }
      credentials do
        { 'access_token' => 'salla-access-factory', 'refresh_token' => 'salla-refresh-factory', 'token_type' => 'bearer',
          'scope' => 'offline_access orders.read customers.read shipping.read',
          'access_token_expires_at' => 14.days.from_now.utc.iso8601, 'refresh_token_expires_at' => nil }
      end
    end

    # A Zid store is its Zid store id; its credentials are the app authorization's two tokens (Authorization and
    # X-Manager-Token), the refresh token and the per-store webhook Basic Auth pair.
    trait :zid do
      provider { 'zid' }
      sequence(:external_store_id) { |n| (318_000 + n).to_s }
      sequence(:base_url) { |n| "https://zid-store-#{n}.zid.store" }
      credentials do
        { 'authorization' => 'zid-authorization-factory', 'access_token' => 'zid-manager-factory', 'refresh_token' => 'zid-refresh-factory',
          'token_type' => 'Bearer', 'expires_at' => 300.days.from_now.utc.iso8601 }
      end
    end
  end
end
