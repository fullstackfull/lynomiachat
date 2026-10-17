FactoryBot.define do
  factory :odoo_customer_mapping, class: 'Odoo::CustomerMapping' do
    destination_profile factory: :odoo_destination_profile
    account
    sequence(:stripe_customer_id) { |n| "cus_factory#{n}" }
    sequence(:source_reference) { |n| "LYNOMIA_CHAT/test/customer/account_#{n}" }
    state { :synchronized }
    matched_by { 'created' }
    sequence(:odoo_partner_id) { |n| 900 + n }
  end

  factory :odoo_document_mapping, class: 'Odoo::DocumentMapping' do
    destination_profile factory: :odoo_destination_profile
    provider { 'stripe' }
    provider_object_type { 'invoice' }
    sequence(:provider_object_id) { |n| "in_factory#{n}" }
    document_kind { 'customer_invoice' }
    odoo_model { 'account.move' }
    sequence(:source_reference) { |n| "LYNOMIA_CHAT/test/invoice/in_factory#{n}" }
    sequence(:idempotency_key) { |n| "LYNOMIA_CHAT:test:stripe:customer_invoice:in_factory#{n}:profile_1" }
    amount_minor { 14_900 }
    currency { 'usd' }
    occurred_at { 2.days.ago }
    state { :synchronized }

    trait :posted do
      odoo_record_id { 4242 }
      odoo_state { 'posted' }
      odoo_document_reference { 'INV/2026/0007' }
      posted_at { 1.day.ago }
    end
  end

  factory :odoo_sync_event, class: 'Odoo::SyncEvent' do
    destination_profile factory: :odoo_destination_profile
    provider { 'stripe' }
    event_type { 'invoice.paid' }
    provider_object_type { 'invoice' }
    sequence(:provider_object_id) { |n| "in_queued#{n}" }
    origin { 'webhook' }
    state { :pending }
    sequence(:dedup_key) { |n| "LYNOMIA_CHAT:test:stripe:invoice:in_queued#{n}:profile_1" }
  end
end
