FactoryBot.define do
  factory :commerce_store, class: 'Commerce::Store' do
    account
    provider { 'woocommerce' }
    sequence(:name) { |n| "Store #{n}" }
    sequence(:base_url) { |n| "https://store#{n}.example.com" }
    external_store_id { URI(base_url).host }
    credentials { { 'consumer_key' => 'ck_factory', 'consumer_secret' => 'cs_factory' } }
  end
end
