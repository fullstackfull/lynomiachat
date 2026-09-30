FactoryBot.define do
  factory :commerce_customer_link, class: 'Commerce::CustomerLink' do
    store factory: :commerce_store
    account { store.account }
    contact { association :contact, account: store.account }
    sequence(:external_customer_id, &:to_s)
    match_source { :manual }
  end
end
