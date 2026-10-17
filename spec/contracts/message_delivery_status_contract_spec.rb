require 'rails_helper'

# THE PRODUCER HALF OF A CROSS-REPOSITORY CONTRACT TEST, for the delivery feed.
#
# WHY A SECOND ONE. The consent feed got this treatment because sender-side and receiver-side
# tests both passed while disagreeing, and every real delivery would have been refused. The
# delivery feed has the identical exposure and, before this, the identical weakness: each
# repository pinned its own literals, and two sides can be consistently wrong about a payload
# shape that neither has ever seen the other produce.
#
# HOW THIS IS DIFFERENT FROM PINNING A CONSTANT. There is ONE artifact --
# docs/contracts/message_delivery_status.v1.json -- generated from this producer's real
# output. This spec asserts the producer still emits it. The consumer repository holds a
# byte-identical copy and feeds it through its REAL ingress route, signature check, ordering
# rule and projector (tests/Contract/LynomiaDeliveryStatusContractTest.php). Neither side can
# change the contract alone without a test going red.
#
# WHAT THE SAMPLES ARE FOR. Five, and each one is a distinction the receiver has to make:
#
#   queued            `status` is "sent" and there is no provider id. THE WHOLE POINT: `sent`
#                     is the column default written on INSERT, so it cannot mean a send, and a
#                     receiver that read the enum would record a message nothing had touched
#                     as delivered.
#   provider_accepted the same "sent", now WITH a provider id. The id is the only difference
#                     between the two, which is why it is in the payload.
#   delivered         the provider confirmed it.
#   policy_refusal    `failed`, with no provider id, because THIS INSTALLATION refused it
#                     before any provider saw it. The case the whole feed exists for.
#   provider_failure  also `failed`, and a different fact. A partner that could not tell these
#                     apart would retry a refusal for ever or give up on a transient failure.
#
# WHAT IT IS NOT. CONTRACT verification, not deployed end-to-end verification. It proves the
# two codebases agree about the wire format, the vocabulary and the ordering key. It proves
# nothing about DNS, TLS, real credentials, Sidekiq delivery, clock skew, or a webhook
# subscription that was never created upstream -- the last of which this integration has now
# actually made, so it is not a hypothetical. Blocker A1 is about those and stays open.
RSpec.describe 'message_delivery_status contract', type: :model do
  let(:contract_path) { Rails.root.join('docs/contracts/message_delivery_status.v1.json') }
  # Asserted identically in the consumer repository. Changing the artifact means changing this
  # digest in BOTH places, which is the point.
  let(:contract_sha256) { '5d7a5d897a68a435b0261fefa243bde5aec19393969f304a2431224f61abd8d5' }

  let(:artifact) { JSON.parse(contract_path.read) }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  # Deployment-specific ids and the clock are the only values the artifact normalises: they
  # differ between any two installations and are not part of the agreement.
  def normalise(payload)
    payload = payload.deep_dup
    payload[:account][:id] = 7001
    payload[:message][:id] = 4242
    payload[:message][:conversation_id] = 77
    payload[:occurred_at] = '2026-10-20T12:00:00.000000Z'
    payload[:occurred_at_us] = 1_792_195_200_000_000
    payload.deep_stringify_keys
  end

  def outgoing(attrs = {})
    create(:message, { conversation: conversation, account: account, inbox: inbox,
                       message_type: :outgoing }.merge(attrs))
  end

  it 'is the artifact the consumer repository holds, byte for byte' do
    expect(Digest::SHA256.hexdigest(contract_path.read)).to eq(contract_sha256),
                                                            'the contract artifact changed; copy it to ' \
                                                            'storesyria/tests/Contract/lynomia/ and update ' \
                                                            'the SHA in both repositories'
  end

  it 'still emits a queued message exactly as the contract records it' do
    expect(normalise(Delivery::StatusFeed.payload(outgoing)))
      .to eq(artifact.dig('samples', 'queued'))
  end

  it 'still emits a provider acceptance exactly as the contract records it' do
    expect(normalise(Delivery::StatusFeed.payload(outgoing(source_id: 'wamid.HBgMOTYz'))))
      .to eq(artifact.dig('samples', 'provider_accepted'))
  end

  it 'still emits a delivery exactly as the contract records it' do
    expect(normalise(Delivery::StatusFeed.payload(outgoing(source_id: 'wamid.HBgMOTYz', status: :delivered))))
      .to eq(artifact.dig('samples', 'delivered'))
  end

  it 'still emits a policy refusal exactly as the contract records it' do
    refused = outgoing(status: :failed,
                       content_attributes: { external_error: I18n.t('errors.whatsapp.consent.consent_withdrawn') })

    expect(normalise(Delivery::StatusFeed.payload(refused)))
      .to eq(artifact.dig('samples', 'policy_refusal'))
  end

  it 'still emits a provider failure exactly as the contract records it' do
    broke = outgoing(source_id: 'wamid.HBgMOTYz', status: :failed,
                     content_attributes: { external_error: '131026: Message undeliverable' })

    expect(normalise(Delivery::StatusFeed.payload(broke)))
      .to eq(artifact.dig('samples', 'provider_failure'))
  end

  # The consumer refuses a delivery whose account is not the configured platform workspace,
  # so this field is load-bearing rather than decorative. Its absence from the consent feed
  # is the defect that motivated these tests existing at all.
  it 'names the workspace in every sample, because the consumer checks it' do
    artifact['samples'].each_value { |sample| expect(sample.dig('account', 'id')).to be_a(Integer) }
  end

  # The ordering key the consumer drops stale events on. An Integer, because the consumer
  # compares it numerically -- a formatted timestamp parsed by two languages is how that goes
  # wrong, and a late receipt overwriting a newer one is the failure it prevents.
  it 'carries the ordering key as an integer in every sample' do
    artifact['samples'].each_value { |sample| expect(sample['occurred_at_us']).to be_a(Integer) }
  end

  # `sent` IS THE COLUMN DEFAULT. Pinned here because it is the whole reason this feed exists
  # and the easiest thing for a later change to lose: a producer that started reporting the
  # enum would send `sent` and a receiver would record a message nothing had touched.
  it 'never reports lynomia\'s own `sent` as an outcome' do
    outcomes = artifact['samples'].each_value.map { |sample| sample['outcome'] }

    expect(outcomes).not_to include('sent')
    expect(artifact.dig('samples', 'queued', 'status')).to eq('sent')
    expect(artifact.dig('samples', 'queued', 'outcome')).to eq('queued')
  end
end
