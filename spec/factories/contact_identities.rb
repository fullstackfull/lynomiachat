# frozen_string_literal: true

FactoryBot.define do
  factory :contact_identity do
    account
    contact { association :contact, account: account }
    identity_type { :phone }
    value { Faker::PhoneNumber.cell_phone_in_e164 }

    trait :email do
      identity_type { :email }
      sequence(:value) { |n| "linked-#{n}@example.com" }
    end
  end
end
