require 'rails_helper'

# SC3 of the P10 security closure (docs/p11/00-p10-security-closure.md).
#
# P10 recorded that inbound WhatsApp routed on Meta's `display_phone_number` with `phone_number_id` applied
# only as a filter afterwards. That was true, and the first thing established here is what it did and did not
# mean: with a real Meta delivery the path could not misroute across tenants -- channel_whatsapp.phone_number
# is globally unique and every writer of phone_number_id takes it from a Graph response authorized for that
# number -- so the consequence was a DROP, not a leak.
#
# The hole was elsewhere. The filter was a bare `==`, so it matched nil against nil; a 360dialog channel never
# stores a phone_number_id; and the controller decided whether to require Meta's signature by resolving the
# channel from the same body. So omitting `phone_number_id` selected a 360dialog channel AND waived the
# signature on the way.
RSpec.describe 'WhatsApp inbound routing isolation', type: :request do
  let(:app_secret) { 'lynomia-meta-app-secret' }

  def cloud_channel(phone_number:, phone_number_id:)
    create(:channel_whatsapp, provider: 'whatsapp_cloud', phone_number: phone_number,
                              sync_templates: false, validate_provider_config: false)
      .tap { |c| c.update!(provider_config: { 'api_key' => 'k', 'phone_number_id' => phone_number_id }) }
  end

  def meta_body(display_phone_number:, phone_number_id: nil, wamid: 'wamid.routing')
    metadata = { display_phone_number: display_phone_number }
    metadata[:phone_number_id] = phone_number_id if phone_number_id
    {
      object: 'whatsapp_business_account',
      entry: [{ changes: [{ field: 'messages',
                            value: { metadata: metadata,
                                     messages: [{ id: wamid, from: '15550001111', type: 'text',
                                                  text: { body: 'hello' } }] } }] }]
    }.to_json
  end

  def signed(body)
    { 'CONTENT_TYPE' => 'application/json',
      'X-Hub-Signature-256' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', app_secret, body)}" }
  end

  before do
    InstallationConfig.where(name: %w[WHATSAPP_APP_SECRET INACTIVE_WHATSAPP_NUMBERS]).delete_all
    GlobalConfig.clear_cache
  end

  describe 'the unauthenticated-injection hole this closure fixes' do
    # A 360dialog channel is the one provider_config that legitimately never carries a phone_number_id, which
    # is what used to supply the nil on the stored side of the comparison.
    let!(:dialog_channel) do
      create(:channel_whatsapp, provider: 'default', phone_number: '+15551230001',
                                sync_templates: false, validate_provider_config: false)
        .tap { |c| c.update!(provider_config: { 'api_key' => 'dialog-key' }) }
    end

    it 'refuses a Meta-enveloped payload that carries no signature, even when it names a 360dialog number' do
      body = meta_body(display_phone_number: '15551230001')

      expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)

      with_modified_env(WHATSAPP_APP_SECRET: app_secret) do
        post '/webhooks/whatsapp', params: body, headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      expect(response).to have_http_status(:unauthorized)
    end

    it 'still exempts a 360dialog payload on the per-number route, which posts a different shape' do
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)

      with_modified_env(WHATSAPP_APP_SECRET: app_secret) do
        post "/webhooks/whatsapp/#{dialog_channel.phone_number}",
             params: { messages: [{ from: '15550001111', text: { body: 'hi' } }] }.to_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      expect(response).to have_http_status(:ok)
      expect(Webhooks::WhatsappEventsJob).to have_received(:perform_later)
    end

    it 'resolves nothing from a Meta envelope with no phone_number_id, rather than matching nil to nil' do
      resolved = Whatsapp::WebhookChannelFinderService.new(
        display_phone_number: '15551230001', phone_number_id: nil
      ).perform

      expect(resolved).to be_nil
    end
  end

  # The brief's required fixture: two accounts whose display values collide under normalization, with
  # distinct Meta identifiers. Argentina is the real case -- the normalizer strips the mobile 9, which names a
  # different real subscriber, so the two stored strings differ and the global unique index does not separate
  # them. Only the identifier does.
  describe 'two accounts with colliding display numbers and distinct Meta ids' do
    let!(:mobile) { cloud_channel(phone_number: '+5491145551234', phone_number_id: 'pn-mobile') }
    let!(:landline) { cloud_channel(phone_number: '+541145551234', phone_number_id: 'pn-landline') }

    it 'sends each payload to the channel whose Meta id it names, not to the other' do
      expect(
        described_resolution(display: '5491145551234', id: 'pn-mobile')
      ).to eq(mobile)

      expect(
        described_resolution(display: '5491145551234', id: 'pn-landline')
      ).to eq(landline)
    end

    it 'keeps the two accounts apart' do
      expect(mobile.account_id).not_to eq(landline.account_id)
      expect(described_resolution(display: '541145551234', id: 'pn-mobile').account_id).to eq(mobile.account_id)
    end

    def described_resolution(display:, id:)
      Whatsapp::WebhookChannelFinderService.new(display_phone_number: display, phone_number_id: id).perform
    end
  end

  describe 'a stored display number that no longer matches what Meta sends' do
    let!(:channel) { cloud_channel(phone_number: '+15559990001', phone_number_id: 'pn-stable') }

    # Before this change the only lookup keys were spellings of the display number, so a channel whose stored
    # number had drifted was reported `unroutable_payload` and the customer's message was discarded -- even
    # though Meta's stable identifier agreed.
    it 'is still routed, because the stable identifier is the lookup key' do
      resolved = Whatsapp::WebhookChannelFinderService.new(
        display_phone_number: '15558880002', phone_number_id: 'pn-stable'
      ).perform

      expect(resolved).to eq(channel)
    end

    it 'is not routed when neither identifier agrees' do
      resolved = Whatsapp::WebhookChannelFinderService.new(
        display_phone_number: '15558880002', phone_number_id: 'pn-unknown'
      ).perform

      expect(resolved).to be_nil
    end
  end

  describe 'a legacy channel that never recorded a phone_number_id' do
    let!(:legacy) do
      create(:channel_whatsapp, provider: 'whatsapp_cloud', phone_number: '+15557770001',
                                sync_templates: false, validate_provider_config: false)
        .tap { |c| c.update!(provider_config: { 'api_key' => 'k' }) }
    end

    it 'is still reachable by its display number' do
      resolved = Whatsapp::WebhookChannelFinderService.new(
        display_phone_number: '15557770001', phone_number_id: 'pn-anything'
      ).perform

      expect(resolved).to eq(legacy)
    end

    it 'does not absorb a payload for a different number' do
      resolved = Whatsapp::WebhookChannelFinderService.new(
        display_phone_number: '15556660001', phone_number_id: 'pn-anything'
      ).perform

      expect(resolved).to be_nil
    end
  end

  describe 'the inactive-number kill switch' do
    let!(:channel) { cloud_channel(phone_number: '+15554440001', phone_number_id: 'pn-inactive') }
    let(:body) { meta_body(display_phone_number: '15554440001', phone_number_id: 'pn-inactive') }

    before do
      create(:installation_config, name: 'INACTIVE_WHATSAPP_NUMBERS', value: '+15554440001')
      GlobalConfig.clear_cache
    end

    # The switch read only the URL segment, so the app-level route -- which has none, and is the one Meta
    # delivers to by default -- ignored it entirely.
    it 'is honoured on the app-level route, which has no number in its path' do
      expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)

      with_modified_env(WHATSAPP_APP_SECRET: app_secret) { post '/webhooks/whatsapp', params: body, headers: signed(body) }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'is still honoured on the per-number route' do
      expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)

      with_modified_env(WHATSAPP_APP_SECRET: app_secret) do
        post "/webhooks/whatsapp/#{channel.phone_number}", params: body, headers: signed(body)
      end

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'a correctly signed delivery' do
    let(:channel) { cloud_channel(phone_number: '+15552220001', phone_number_id: 'pn-good') }
    let(:body) { meta_body(display_phone_number: '15552220001', phone_number_id: 'pn-good') }

    it 'is accepted, enqueued, and resolves to the channel that owns the Meta id' do
      channel
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)

      with_modified_env(WHATSAPP_APP_SECRET: app_secret) { post '/webhooks/whatsapp', params: body, headers: signed(body) }

      expect(response).to have_http_status(:ok)
      expect(Webhooks::WhatsappEventsJob).to have_received(:perform_later)
      expect(
        Whatsapp::WebhookChannelFinderService.new(display_phone_number: '15552220001', phone_number_id: 'pn-good').perform
      ).to eq(channel)
    end
  end
end
