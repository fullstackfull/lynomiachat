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
  end
end
