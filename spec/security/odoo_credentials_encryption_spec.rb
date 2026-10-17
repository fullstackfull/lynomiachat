require 'rails_helper'

# THE ODOO API KEY AT REST, under keys this process was GIVEN rather than keys the repository carries.
#
# Every other Odoo spec reaches encryption through the `with commerce encryption` shared context, which calls
# `ActiveRecord::Encryption.configure` with three literal strings committed under `spec/support`. That proves
# the model's behaviour, and it is what lets those specs run inside a shard whose environment holds no keys.
# What it cannot prove is the production arrangement: keys arriving from `ACTIVE_RECORD_ENCRYPTION_*` and from
# nowhere else, which is the only arrangement a deployed Lynomia Chat has.
#
# So this file deliberately does NOT include that context. It reads what `Chatwoot.encryption_configured?`
# reads -- the environment -- and skips when there is nothing there, which is what keeps it inert in the
# 16-way sharded run that supplies no keys. `.github/workflows/run_encryption_spec.yml` generates throwaway
# keys for a single step and then FAILS the job if any example here reported pending, because a skipped
# example is not a passing one and this file's whole purpose is to stop that being mistaken for proof.
# rubocop:disable RSpec/DescribeClass -- the subject is the GUARANTEE, which no single class owns: it is
# Odoo::DestinationProfile, Active Record Encryption's configuration, and what Postgres ends up holding.
RSpec.describe 'Odoo credential encryption at rest' do
  # Distinctive, so a substring match inside a column cannot be a coincidence.
  let(:api_key) { 'odoo-ci-at-rest-4f1c8a9e2b7d' }
  let(:profile) { create(:odoo_destination_profile, credentials: { 'api_key' => api_key }) }

  before do
    skip('ACTIVE_RECORD_ENCRYPTION_* absent; run_encryption_spec.yml supplies them') unless Chatwoot.encryption_configured?
  end

  # What Postgres holds, before Active Record casts or decrypts anything.
  def stored_column(record)
    record.reload.read_attribute_before_type_cast(:credentials).to_s
  end

  describe 'what the column holds' do
    it 'round-trips the API key through a column that does not contain it' do
      stored = stored_column(profile)

      expect(stored).to be_present
      expect(stored).not_to include(api_key)
      expect(profile.api_key).to eq(api_key)
      expect(profile.encrypted_attribute?(:credentials)).to be(true)
    end

    # The failure this guards against is not a weak cipher, it is NO cipher: a misconfiguration in which
    # `encrypts` degraded to storing an encoded copy would still satisfy the `not_to include` above, because
    # the plaintext would be sitting there base64'd. So every base64-shaped run in the envelope is decoded and
    # checked, which makes the assertion independent of Active Record's envelope format.
    it 'leaves no encoding of the API key in the column either' do
      stored = stored_column(profile)
      decoded = stored.scan(%r{[A-Za-z0-9+/=]{16,}}).map { |chunk| Base64.decode64(chunk) }

      expect(stored).not_to include(Base64.strict_encode64(api_key))
      expect(decoded).to all(satisfy { |blob| blob.exclude?(api_key) })
    end

    # Non-deterministic encryption. The same key under the same configuration has to land differently, or the
    # column would leak equality between two destinations to anyone holding a database dump.
    it 'writes different ciphertext for the same API key twice' do
      other = create(:odoo_destination_profile, credentials: { 'api_key' => api_key })

      expect(stored_column(other)).not_to eq(stored_column(profile))
      expect(other.api_key).to eq(api_key)
    end
  end

  describe 'what leaves the process' do
    # `#serializable_hash` is overridden on the model, and these are the three call sites that reach it. A
    # `render json:` on the Super Admin surface is the realistic way a credential escapes, so the override is
    # pinned at every one rather than only where it is defined.
    it 'carries no credentials through serializable_hash, as_json or to_json' do
      expect(profile.serializable_hash).not_to have_key('credentials')
      expect(profile.as_json).not_to have_key('credentials')
      expect(profile.to_json).not_to include('credentials')
      expect(profile.to_json).not_to include(api_key)
    end

    # What the operator is shown instead. A mask that returned the key would pass the serialization examples
    # above and still put the credential on screen.
    it 'shows a mask that is not the key' do
      expect(profile.masked_api_key).to be_present
      expect(profile.masked_api_key).not_to eq(api_key)
      expect(profile.masked_api_key).not_to include(api_key)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
