# frozen_string_literal: true

FactoryBot.define do
  factory :support_ticket, class: 'Support::Ticket' do
    title { 'Order never arrived' }
    category { 'technical' }

    after(:build) do |ticket|
      ticket.account ||= create(:account)
    end
  end

  factory :support_sla_policy, class: 'Support::SlaPolicy' do
    name { 'Standard' }
    first_response_time_threshold { 1.hour.to_i }
    resolution_time_threshold { 1.day.to_i }

    after(:build) do |policy|
      policy.account ||= create(:account)
    end
  end
end
