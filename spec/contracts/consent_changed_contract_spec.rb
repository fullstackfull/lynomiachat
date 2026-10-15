require 'rails_helper'

# THE PRODUCER HALF OF A CROSS-REPOSITORY CONTRACT TEST.
#
# WHY THIS EXISTS. Sender-side and receiver-side tests can both pass while disagreeing, and
# in this integration they already did: the consent feed shipped with a payload carrying no
# `account`, Lynomia's specs asserted the payload it built, Store Syria's asserted the
# payload it accepted, both were green, and every real delivery would have been rejected as
# `unknown_workspace`. Two mocks agreeing with their own authors is not a contract.
#
# HOW THIS IS DIFFERENT. There is ONE artifact --
# docs/partner-consent/contract/consent_changed.v1.json -- generated from this producer's real
# output. This spec asserts the producer still emits it. The consumer repository holds a
# byte-identical copy and feeds it through its REAL ingress route, signature check and
# projection (tests/Contract/LynomiaConsentContractTest.php). Neither side can change the
# contract alone without a test going red.
#
# THE SHA GUARD IS WHAT MAKES IT CROSS-REPOSITORY. Both repositories assert the same
# CONTRACT_SHA256 over the same bytes. Regenerating the artifact here without copying it
# there -- or editing it there -- breaks one of the two. Without that constant the two copies
# could drift apart silently, which is the exact failure the whole exercise is aimed at.
#
# WHAT IT IS NOT. This is CONTRACT verification, not deployed end-to-end verification. It
# proves the two codebases agree about the wire format, the identity fields, the ordering key
# and the refusal semantics. It proves nothing about DNS, TLS, real credentials, Sidekiq
# delivery, clock skew between two hosts, or a webhook subscription that was never created.
# Blocker A1 is about those and stays open.
RSpec.describe 'consent_changed contract', type: :model do
  include_context 'with commerce encryption'

  CONTRACT_PATH = Rails.root.join('docs/partner-consent/contract/consent_changed.v1.json')
  # Asserted identically in the consumer repository. Changing the artifact means changing
  # this constant in BOTH places, which is the point.
  CONTRACT_SHA256 = 'e69d400bfcef51e65738b484d4c98221517f4fc1f7eaca0aa3a561c799ec5808'.freeze

  let(:artifact) { JSON.parse(CONTRACT_PATH.read) }
  let(:account) { create(:account) }
  let(:store) do
    create(:commerce_store, account: account, provider: 'storesyria',
                            external_store_id: "c#{SecureRandom.hex(4)}", status: :active)
  end
  let(:contact) { create(:contact, account: account, name: 'Contract Shopper') }
  let(:link) do
    create(:commerce_customer_link, account: account, store: store, contact: contact,
                                    external_customer_id: 'cust-77')
  end

  # Deployment-specific ids are the only values the artifact normalises, because they differ
  # between any two installations and are not part of the agreement.
  def normalise(payload)
    payload = payload.deep_dup
    payload[:account][:id] = 7001
    payload[:store][:external_store_id] = '4242'
    payload
  end

  it 'is the artifact the consumer repository holds, byte for byte' do
    expect(Digest::SHA256.hexdigest(CONTRACT_PATH.read)).to eq(CONTRACT_SHA256),
                                                            'the contract artifact changed; copy it to ' \
                                                            'storesyria/tests/Contract/lynomia/ and update ' \
                                                            'CONTRACT_SHA256 in both repositories'
  end

  it 'still emits the native withdrawal exactly as the contract records it' do
    consent = Commerce::MessagingConsent.create!(
      account: account, contact: contact, purpose: :promotional, state: :withdrawn,
      source: 'shopper_keyword', decided_at: Time.utc(2026, 10, 20, 12, 0, 0), evidence: { 'keyword' => 'stop' }
    )

    produced = normalise(Consents::ChangeFeed.payload(link, consent, origin: 'lynomia_native', channel: 'any'))
    produced[:revision] = 9001

    expect(produced.deep_stringify_keys).to eq(artifact.dig('samples', 'native_withdrawal'))
  end

  it 'still emits the partner grant exactly as the contract records it' do
    consent = PartnerConsent.create!(
      platform_app: create(:platform_app), account: account, commerce_store: store, contact: contact,
      external_subject_id: 'cust-77', purpose: :promotional, channel: :whatsapp, state: :granted,
      source: 'checkout_optin', policy_version: 'v3',
      captured_at: Time.utc(2026, 10, 20, 13, 0, 0), revision: 10_001
    )

    produced = normalise(Consents::ChangeFeed.partner_payload(consent))

    expect(produced.deep_stringify_keys).to eq(artifact.dig('samples', 'partner_grant'))
  end

  # The consumer refuses a delivery whose account is not the one that store is linked to, so
  # this field is load-bearing rather than decorative. It is called out separately because
  # its absence is the defect that motivated the whole contract test.
  it 'names the workspace in every sample, because the consumer checks it' do
    artifact['samples'].each_value do |sample|
      expect(sample.dig('account', 'id')).to be_a(Integer)
    end
  end

  # The ordering key the consumer drops stale events on. A sample without it would let a
  # consumer accept events in arrival order, which is the property this design rejects.
  it 'carries the server-assigned ordering key in every sample' do
    artifact['samples'].each_value do |sample|
      expect(sample['revision']).to be_a(Integer)
    end
  end

  # THE SIGNATURE CONSTRUCTION ITSELF, pinned rather than assumed. The consumer recomputes
  # sha256=HMAC_SHA256(secret, "{timestamp}.{body}") and compares; if either side ever changed
  # the input -- dropping the dot, hashing the body alone, switching the key and message
  # arguments -- every delivery would fail authentication in production and no unit test on
  # either side would notice. Time is frozen so the producer's own timestamp is known and the
  # expected digest can be computed independently of it.
  it 'signs exactly what the consumer verifies' do
    body = artifact.dig('samples', 'native_withdrawal').to_json
    secret = 'shared-secret'

    travel_to(Time.zone.at(1_760_961_600)) do
      headers = Webhooks::Trigger.new(nil, {}, :account_webhook, secret: secret, delivery_id: 'd1')
                                 .send(:request_headers, body)

      expect(headers['X-Chatwoot-Timestamp']).to eq('1760961600')
      expect(headers['X-Chatwoot-Signature'])
        .to eq("sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "1760961600.#{body}")}")
      expect(headers['X-Chatwoot-Delivery']).to eq('d1')
    end
  end
end
