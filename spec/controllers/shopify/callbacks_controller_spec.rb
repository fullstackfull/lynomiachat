require 'rails_helper'

RSpec.describe Shopify::CallbacksController, type: :request do
  include Shopify::IntegrationHelper

  let(:account) { create(:account) }
  let(:code) { SecureRandom.hex(10) }
  let(:shop) { 'my-store.myshopify.com' }
  let(:client_secret) { 'shopify-client-secret' }
  let(:frontend_url) { 'http://www.example.com' }
  let(:shopify_redirect_uri) { "#{frontend_url}/app/accounts/#{account.id}/settings/integrations/shopify" }
  let(:access_token) { SecureRandom.hex(10) }
  let(:response_body) { { 'access_token' => access_token, 'scope' => 'read_products,write_products' } }
  let(:state) { generate_shopify_token(account.id, shop) }

  # Shopify signs the callback query: every parameter except hmac, sorted, joined as key=value with &.
  def signed_query(query, secret: client_secret)
    message = query.stringify_keys.sort.map { |key, value| "#{key}=#{value}" }.join('&')
    query.merge(hmac: OpenSSL::HMAC.hexdigest('SHA256', secret, message))
  end

  def callback(query)
    get shopify_callback_path, params: signed_query(query)
  end

  before do
    stub_const('ENV', ENV.to_hash.merge('FRONTEND_URL' => frontend_url))
    create(:installation_config, name: 'SHOPIFY_CLIENT_ID', value: 'shopify-client-id')
    create(:installation_config, name: 'SHOPIFY_CLIENT_SECRET', value: client_secret)
    GlobalConfig.clear_cache
    stub_request(:post, "https://#{shop}/admin/oauth/access_token")
      .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'GET /shopify/callback' do
    context 'when the callback is valid' do
      it 'creates a new integration hook' do
        expect do
          callback(code: code, shop: shop, state: state, timestamp: Time.current.to_i)
        end.to change(Integrations::Hook, :count).by(1)

        hook = Integrations::Hook.last
        expect(hook.access_token).to eq(access_token)
        expect(hook.app_id).to eq('shopify')
        expect(hook.status).to eq('enabled')
        expect(hook.reference_id).to eq(shop)
        expect(hook.settings).to include('scope' => 'read_products,write_products', 'connected_at' => be_present,
                                         'installation_id' => be_present)
        expect(response).to redirect_to(shopify_redirect_uri)
      end

      it 'reconnects a retained hook and ignores an older uninstall' do
        hook = create(:integrations_hook, app_id: 'shopify', account: account, reference_id: shop)
        hook.update!(status: :disabled, access_token: nil, settings: {})

        expect do
          callback(code: code, shop: shop, state: state, timestamp: Time.current.to_i)
        end.not_to change(Integrations::Hook, :count)
        expect(hook.reload).to be_enabled
        expect(hook.access_token).to eq(access_token)
        expect(Shopify::UninstallationService.new(hook: hook, occurred_at: 2.days.ago).perform).to eq(:stale)
        expect(hook.reload).to be_enabled
      end
    end

    context 'when Shopify rejects the code' do
      before do
        stub_request(:post, "https://#{shop}/admin/oauth/access_token")
          .to_return(status: 400, body: { error: 'invalid_grant' }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'redirects to the shopify_redirect_uri with error' do
        callback(code: code, shop: shop, state: state, timestamp: Time.current.to_i)

        expect(response).to redirect_to("#{shopify_redirect_uri}?error=true")
        expect(Integrations::Hook.count).to eq(0)
      end
    end

    context 'when the shop is not a myshopify domain' do
      %w[
        attacker.example.com
        my-store.myshopify.com.attacker.com
        my-store.myshopify.com@attacker.com
        attacker.com/my-store.myshopify.com
        attacker.com#my-store.myshopify.com
        127.0.0.1
      ].each do |forged_shop|
        it "never sends the client secret to #{forged_shop}" do
          forged_state = generate_shopify_token(account.id, forged_shop)
          callback(code: code, shop: forged_shop, state: forged_state, timestamp: Time.current.to_i)

          expect(a_request(:post, /oauth/)).not_to have_been_made
          expect(response).to redirect_to("#{frontend_url}?error=true")
          expect(Integrations::Hook.count).to eq(0)
        end
      end
    end

    context 'when the state was issued for another shop' do
      it 'rejects the callback before the token exchange' do
        other_state = generate_shopify_token(account.id, 'other-store.myshopify.com')
        callback(code: code, shop: shop, state: other_state, timestamp: Time.current.to_i)

        expect(a_request(:post, /oauth/)).not_to have_been_made
        expect(response).to redirect_to("#{frontend_url}?error=true")
      end
    end

    context 'when the state has expired' do
      it 'rejects the callback before the token exchange' do
        expired_state = state
        travel(described_class::STATE_TTL + 1.minute) do
          callback(code: code, shop: shop, state: expired_state, timestamp: Time.current.to_i)
        end

        expect(a_request(:post, /oauth/)).not_to have_been_made
        expect(response).to redirect_to("#{frontend_url}?error=true")
      end
    end

    context 'when the state has no expiry (previous token format)' do
      it 'rejects the callback before the token exchange' do
        legacy_state = JWT.encode({ sub: account.id, iat: Time.current.to_i }, client_secret, 'HS256')
        callback(code: code, shop: shop, state: legacy_state, timestamp: Time.current.to_i)

        expect(a_request(:post, /oauth/)).not_to have_been_made
        expect(response).to redirect_to("#{frontend_url}?error=true")
      end
    end

    context 'when the state is not signed with the client secret' do
      it 'rejects the callback before the token exchange' do
        forged_state = JWT.encode({ sub: account.id, shop: shop, iat: Time.current.to_i, exp: 5.minutes.from_now.to_i },
                                  'attacker-secret', 'HS256')
        callback(code: code, shop: shop, state: forged_state, timestamp: Time.current.to_i)

        expect(a_request(:post, /oauth/)).not_to have_been_made
        expect(response).to redirect_to("#{frontend_url}?error=true")
      end
    end

    context 'when the Shopify signature is missing or wrong' do
      it 'rejects an unsigned callback' do
        get shopify_callback_path, params: { code: code, shop: shop, state: state, timestamp: Time.current.to_i }

        expect(a_request(:post, /oauth/)).not_to have_been_made
        expect(response).to redirect_to("#{frontend_url}?error=true")
      end

      it 'rejects a callback signed with another secret' do
        get shopify_callback_path,
            params: signed_query({ code: code, shop: shop, state: state, timestamp: Time.current.to_i }, secret: 'wrong')

        expect(a_request(:post, /oauth/)).not_to have_been_made
        expect(response).to redirect_to("#{frontend_url}?error=true")
      end

      it 'rejects a callback whose parameters were changed after signing' do
        query = signed_query({ code: code, shop: shop, state: state, timestamp: Time.current.to_i })
        get shopify_callback_path, params: query.merge(code: 'swapped-code')

        expect(a_request(:post, /oauth/)).not_to have_been_made
        expect(response).to redirect_to("#{frontend_url}?error=true")
      end
    end
  end
end
