# Regenerates docs/partner-consent/contract/consent_changed.v1.json from the REAL producer.
#
#   RAILS_ENV=test \
#   ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=commerce-spec-primary-key-0123456789 \
#   ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=commerce-spec-deterministic-key-0123 \
#   ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=commerce-spec-key-derivation-salt-01 \
#   bundle exec rails runner script/generate_consent_contract.rb
#
# Then copy the artifact to storesyria/tests/Contract/lynomia/ and update CONTRACT_SHA256 in
# BOTH spec/contracts/consent_changed_contract_spec.rb and
# storesyria/tests/Contract/LynomiaConsentContractTest.php. Either side alone goes red, which
# is the point of the checksum.
#
# EVERYTHING IT CREATES IS ROLLED BACK. The first version of this script ran as a plain
# `rails runner` against the test database and COMMITTED its fixtures, because a runner has
# no test transaction around it. Eleven request specs then failed on `PartnerConsent.count`
# -- passing alone, failing in a suite -- and the cause was this script, not the code under
# test. A generator that leaves rows behind poisons every later run on that database.
# The fixtures, out of the transaction block so the block stays inside Metrics/BlockLength.
# They are rolled back with everything else -- `build_samples` only creates rows, and its
# caller owns the transaction.
def build_samples
  account = Account.create!(name: 'Contract WS')
  store = Commerce::Store.create!(account: account, provider: 'storesyria',
                                  external_store_id: "contract-#{SecureRandom.hex(4)}",
                                  name: 'Contract Store', base_url: 'https://contract.example', status: :active)
  contact = Contact.create!(account: account, name: 'Contract Shopper')
  link = Commerce::CustomerLink.create!(account: account, store: store, contact: contact,
                                        external_customer_id: 'cust-77', match_source: :manual)
  consent = Commerce::MessagingConsent.create!(account: account, contact: contact, purpose: :promotional,
                                               state: :withdrawn, source: 'shopper_keyword',
                                               decided_at: Time.utc(2026, 10, 20, 12, 0, 0),
                                               evidence: { 'keyword' => 'stop' })

  partner_row = PartnerConsent.create!(platform_app: PlatformApp.create!(name: 'Contract App'), account: account,
                                       commerce_store: store, contact: contact, external_subject_id: 'cust-77',
                                       purpose: :promotional, channel: :whatsapp, state: :granted,
                                       source: 'checkout_optin', policy_version: 'v3',
                                       captured_at: Time.utc(2026, 10, 20, 13, 0, 0), revision: 10_001)

  [Consents::ChangeFeed.payload(link, consent, origin: 'lynomia_native', channel: 'any'),
   Consents::ChangeFeed.partner_payload(partner_row)]
end

ActiveRecord::Base.transaction do
  native, partner = build_samples

  # The only values normalised: they differ between any two installations and are not part of
  # the agreement. Everything else is verbatim producer output.
  [native, partner].each do |sample|
    sample[:account][:id] = 7001
    sample[:store][:external_store_id] = '4242'
  end
  native[:revision] = 9001
  partner[:revision] = 10_001

  doc = { 'contract' => 'consent_changed', 'version' => 1,
          'producer' => 'lynomia/custom/app/services/consents/change_feed.rb',
          'consumer' => 'storesyria/packages/workdo/LynomiaChat/src/app/Http/Controllers/EventIngressController.php',
          'samples' => { 'native_withdrawal' => native, 'partner_grant' => partner } }

  Rails.root.join('docs/partner-consent/contract/consent_changed.v1.json')
       .write("#{JSON.pretty_generate(doc)}\n")

  puts "written: #{Digest::SHA256.hexdigest(Rails.root.join('docs/partner-consent/contract/consent_changed.v1.json').read)}"

  raise ActiveRecord::Rollback
end
