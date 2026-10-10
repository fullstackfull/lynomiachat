FactoryBot.define do
  factory :billing_entitlement_override do
    account
    kind { :feature }
    sequence(:name) { |n| "capability_#{n}" }
    enabled { true }
    reason { 'granted during a pilot' }
  end
end
