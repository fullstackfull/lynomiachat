FactoryBot.define do
  # A destination that is fully configured and PROVEN, because most specs are about what happens after that
  # point. The unproven states are reached by stripping attributes in the example that needs them, which keeps
  # each example's starting point visible in the example itself.
  factory :odoo_destination_profile, class: 'Odoo::DestinationProfile' do
    sequence(:name) { |n| "Odoo destination #{n}" }
    environment { 'test' }
    sequence(:base_url) { |n| "https://odoo-#{n}.example.com" }
    database { 'lynomia_books' }
    username { 'accounting@example.com' }
    # Credentials need Active Record encryption; a spec touching them includes 'with commerce encryption'.
    credentials { { 'api_key' => 'odoo-api-key-factory' } }
    odoo_version { '19.0' }
    odoo_version_info { { 'server_version' => '19.0', 'server_version_info' => [19, 0, 0, 'final', 0, ''] } }
    transport { 'json2' }
    company_id { 3 }
    company_name { 'Lynomia Chat FZ' }
    journal_id { 11 }
    journal_name { 'Customer Invoices' }
    payment_journal_id { 12 }
    payment_journal_name { 'Bank' }
    last_connection_test_at { 1.hour.ago }
    last_connection_result { { 'ok' => true } }
    last_capability_proof_at { 1.hour.ago }
    last_capability_proof { { 'ok' => true } }

    trait :enabled do
      sync_enabled { true }
    end

    trait :posting do
      sync_enabled { true }
      post_invoices { true }
    end

    trait :registering_payments do
      sync_enabled { true }
      post_invoices { true }
      register_payments { true }
    end
  end
end
