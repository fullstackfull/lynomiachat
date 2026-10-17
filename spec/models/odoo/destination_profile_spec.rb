require 'rails_helper'

# The Odoo destination: its credential handling, its validations, and the nine states it derives
# (custom/app/models/odoo/destination_profile.rb).
RSpec.describe Odoo::DestinationProfile do
  include_context 'with commerce encryption'

  describe 'credentials' do
    # The brief: "Never expose saved secrets in HTML, API responses, logs or exception messages."
    it 'stores the API key encrypted and keeps it out of serialization' do
      profile = create(:odoo_destination_profile)

      raw = profile.reload.read_attribute_before_type_cast(:credentials).to_s

      expect(raw).to be_present
      expect(raw).not_to include('odoo-api-key-factory')
      expect(profile.api_key).to eq('odoo-api-key-factory')
      expect(profile.serializable_hash).not_to have_key('credentials')
      expect(profile.serializable_hash.to_json).not_to include('odoo-api-key-factory')
    end

    it 'refuses to persist credentials at all without Active Record encryption keys' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
      profile = build(:odoo_destination_profile)

      expect(profile).not_to be_valid
      expect(profile.errors.full_messages.join).to include('Active Record encryption keys')
    end

    # The brief: "Leaving a secret field empty when editing must preserve its existing value."
    it 'keeps the stored key when assigned a blank value' do
      profile = create(:odoo_destination_profile)

      profile.api_key = ''
      profile.api_key = nil

      expect(profile.api_key).to eq('odoo-api-key-factory')
    end

    it 'clears the key only when asked explicitly' do
      profile = create(:odoo_destination_profile)

      profile.clear_api_key!

      expect(profile.reload.api_key).to be_nil
      expect(profile.credentials_present?).to be(false)
    end

    it 'masks a long key and says nothing but that a short one is set' do
      profile = build(:odoo_destination_profile)

      profile.api_key = 'odoo_live_abcdefghijklmnopqrstuvwxyz'
      expect(profile.masked_api_key).to eq('odoo_li...wxyz')

      profile.credentials = { 'api_key' => 'short' }
      expect(profile.masked_api_key).to eq(Billing::Settings::SHORT_VALUE_MASK)
    end
  end

  describe 'base URL' do
    # An accounting credential is never sent over plain HTTP, and a URL carrying userinfo would put one in an
    # unencrypted column and in every log line that prints the URL.
    it 'refuses plain HTTP, userinfo in the URL, and an unparseable URL' do
      expect(build(:odoo_destination_profile, base_url: 'http://odoo.example.com')).not_to be_valid
      expect(build(:odoo_destination_profile, base_url: 'https://u:pw@odoo.example.com')).not_to be_valid
      expect(build(:odoo_destination_profile, base_url: 'not a url at all')).not_to be_valid
    end

    it 'accepts an ordinary https URL' do
      expect(build(:odoo_destination_profile, base_url: 'https://odoo.example.com')).to be_valid
    end
  end

  describe 'the nine configuration and activation states' do
    let(:profile) { build(:odoo_destination_profile) }

    it 'answers not_configured at the class level when no destination exists' do
      expect(described_class.status).to eq(:not_configured)
      create(:odoo_destination_profile)
      expect(described_class.status).to eq(:configured)
    end

    # THE FUNNEL AS A TABLE, asserted in one expectation because the thing being tested is the ORDER. Eight
    # separate examples would each pass while the sequence they describe was wrong, which is the only way this
    # can actually break: a reordered funnel tells an operator to fix the wrong thing next.
    it 'walks the funnel, naming the next thing an operator must do' do
      steps = [
        [{ credentials: {} }, :credentials_missing],
        [{ api_key: 'odoo-key', last_connection_test_at: nil }, :connection_untested],
        [{ last_connection_test_at: Time.current, last_connection_result: { 'ok' => false } }, :connection_failed],
        [{ last_connection_result: { 'ok' => true }, journal_id: nil }, :scope_incomplete],
        [{ journal_id: 11, last_capability_proof: { 'ok' => false } }, :capability_unproven],
        [{ last_capability_proof: { 'ok' => true } }, :ready_disabled],
        [{ sync_enabled: true }, :active],
        [{ blocked_reason: 'journal_missing' }, :error]
      ]

      observed = steps.map do |changes, _expected|
        changes.each { |attribute, value| profile.public_send(:"#{attribute}=", value) }
        profile.status
      end

      expect(observed).to eq(steps.map(&:last))
    end
  end

  describe 'posting and payment registration' do
    # The brief: both are separately configurable AND disabled until validated. The validation is the
    # capability proof, so a tick alone cannot turn posting on.
    it 'refuses posting until the capability probe has passed, however the box is ticked' do
      profile = build(:odoo_destination_profile, :posting, last_capability_proof: { 'ok' => false })

      expect(profile.post_invoices?).to be(true)
      expect(profile.may_post?).to be(false)
      expect(profile.may_register_payments?).to be(false)
    end

    it 'requires posting before payment registration, since there is nothing to pay against' do
      profile = build(:odoo_destination_profile, :enabled, register_payments: true, post_invoices: false)

      expect(profile.may_register_payments?).to be(false)
    end

    it 'allows both once the probe has passed and both boxes are ticked' do
      profile = build(:odoo_destination_profile, :registering_payments)

      expect(profile.may_post?).to be(true)
      expect(profile.may_register_payments?).to be(true)
    end
  end

  describe 'exclusivity' do
    # TWO ENABLED DESTINATIONS WOULD POST EVERY INVOICE TWICE, so the database refuses rather than a callback.
    it 'allows only one enabled destination per app and environment' do
      create(:odoo_destination_profile, :enabled, environment: 'live')

      expect { create(:odoo_destination_profile, :enabled, environment: 'live') }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows any number of disabled destinations in the same environment' do
      create(:odoo_destination_profile, environment: 'live')

      expect { create(:odoo_destination_profile, environment: 'live') }.not_to raise_error
    end

    it 'finds the one enabled destination for an environment and ignores the others' do
      create(:odoo_destination_profile, environment: 'live')
      enabled = create(:odoo_destination_profile, :enabled, environment: 'live')
      create(:odoo_destination_profile, :enabled, environment: 'test')

      expect(described_class.active(environment: 'live')).to eq(enabled)
    end
  end
end
