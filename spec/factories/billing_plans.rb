FactoryBot.define do
  factory :billing_plan do
    sequence(:name) { |n| "Plan #{n}" }
    price_cents { 1000 }
    currency { 'usd' }
    interval { 'month' }
    pricing_type { 'flat' }
    active { true }
  end
end
