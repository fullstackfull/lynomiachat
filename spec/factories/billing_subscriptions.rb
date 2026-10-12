FactoryBot.define do
  factory :billing_subscription do
    account
    plan factory: :billing_plan
    status { 'active' }
    # `manual` by default: a Stripe-sourced subscription implies provider ids, and a factory that invents them
    # would let a spec assert against a subscription Stripe has never heard of.
    source { 'manual' }
  end
end
