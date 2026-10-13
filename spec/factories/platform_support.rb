# Platform Support Desk rows for specs.
#
# The desk seeds nothing in production -- no agent, no SLA policy (docs/platform-support/12 §11) -- so these
# factories exist only for tests. `reference_number` is deliberately NOT set here: the model allocates it from
# the global series under an advisory lock, and a factory that supplied its own would test something the
# product does not do.
FactoryBot.define do
  factory :platform_support_agent, class: 'PlatformSupport::Agent' do
    user { create(:super_admin) }
    display_name { 'Hisham Operator' }
    role { :agent }
    active { true }

    trait :lead do
      role { :lead }
    end

    trait :inactive do
      active { false }
    end
  end

  factory :platform_support_sla_policy, class: 'PlatformSupport::SlaPolicy' do
    sequence(:name) { |n| "Policy #{n}" }
    billing_plan_id { nil }
    active { true }
    # Obviously synthetic seconds. Production targets are the owner's data, never a default in code.
    first_response_time_threshold { 60 }
    resolution_time_threshold { 180 }
  end

  factory :platform_support_ticket, class: 'PlatformSupport::Ticket' do
    account
    account_name_at_creation { account&.name.presence || 'Deleted account' }
    reporter_name { 'A reporter' }
    subject { 'The dashboard will not load for our team' }
    description { 'It started this morning and affects every administrator.' }
    category { 'other' }
    status { :open }
    priority { :medium }
  end

  factory :platform_support_message, class: 'PlatformSupport::Message' do
    ticket factory: :platform_support_ticket
    author_type { 'User' }
    author_name { 'A reporter' }
    body { 'Any update on this?' }
  end

  factory :platform_support_internal_note, class: 'PlatformSupport::InternalNote' do
    ticket factory: :platform_support_ticket
    agent factory: :platform_support_agent
    author_name { 'Hisham Operator' }
    body { 'Checked the logs; it is the reauth latch.' }
  end

  factory :platform_support_event, class: 'PlatformSupport::Event' do
    ticket factory: :platform_support_ticket
    event_type { 'created' }
    actor_type { 'System' }
  end
end
