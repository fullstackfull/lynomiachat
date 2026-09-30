require 'rails_helper'

# Stub class for ShopifyAPI response
class ShopifyAPIResponse
  attr_reader :body

  def initialize(body)
    @body = body
  end
end

RSpec.describe 'Shopify Integration API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:unauthorized_agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, email: 'test@example.com', phone_number: '+1234567890') }

  describe 'POST /api/v1/accounts/:account_id/integrations/shopify/auth' do
    let(:shop_domain) { 'test-store.myshopify.com' }

    context 'when it is an administrator' do
      before do
        create(:installation_config, name: 'SHOPIFY_CLIENT_SECRET', value: 'shopify-client-secret')
        GlobalConfig.clear_cache
      end

      it 'returns a redirect URL for Shopify OAuth with a state bound to the shop' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
             params: { shop_domain: shop_domain },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:ok)
        redirect_url = URI.parse(response.parsed_body['redirect_url'])
        expect(redirect_url.host).to eq(shop_domain)
        state = Rack::Utils.parse_query(redirect_url.query)['state']
        payload = JWT.decode(state, 'shopify-client-secret', true, algorithm: 'HS256').first
        expect(payload).to include('sub' => account.id, 'shop' => shop_domain, 'exp' => be_present)
      end

      it 'returns error when shop domain is missing' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Shop domain is required')
      end

      # Lynomia: one connection per shop and account (docs/commerce/21-shopify-legacy-coexistence.md).
      context 'when the shop is a Lynomia Commerce store' do
        include_context 'with commerce encryption'

        it 'refuses a shop this account already connected through Lynomia Commerce, whatever its Commerce status' do
          store = create(:commerce_store, :shopify, account: account, base_url: "https://#{shop_domain}")

          %w[active needs_reauth disabled].each do |status|
            store.update!(status: status)
            post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
                 params: { shop_domain: shop_domain.upcase },
                 headers: administrator.create_new_auth_token,
                 as: :json

            expect(response).to have_http_status(:unprocessable_entity)
            expect(response.parsed_body).to eq('error' => 'This Shopify store is already connected through Commerce')
          end
          expect(account.hooks.where(app_id: 'shopify')).to be_empty
        end

        it 'connects a shop whose Commerce store is disconnected, belongs to another account or is another shop' do
          create(:commerce_store, :shopify, account: account, base_url: "https://#{shop_domain}", status: :disconnected, credentials: nil)
          create(:commerce_store, :shopify, account: create(:account), base_url: 'https://other-account-shop.myshopify.com')
          create(:commerce_store, :shopify, account: account, base_url: 'https://another-shop.myshopify.com')

          post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
               params: { shop_domain: shop_domain },
               headers: administrator.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['redirect_url']).to start_with("https://#{shop_domain}/admin/oauth/authorize?")
        end
      end

      it 'rejects a shop domain that is not a myshopify domain' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
             params: { shop_domain: 'attacker.example.com' },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Invalid shop domain')
      end
    end

    context 'when it is an agent' do
      it 'does not issue an authorization state' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
             params: { shop_domain: shop_domain },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
             params: { shop_domain: shop_domain },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/integrations/shopify/orders' do
    before do
      create(:integrations_hook, :shopify, account: account)
    end

    context 'when it is an authenticated user' do
      # rubocop:disable RSpec/AnyInstance
      let(:shopify_client) { instance_double(ShopifyAPI::Clients::Rest::Admin) }

      let(:customers_response) do
        instance_double(
          ShopifyAPIResponse,
          body: { 'customers' => [{ 'id' => '123' }] }
        )
      end

      let(:orders_response) do
        instance_double(
          ShopifyAPIResponse,
          body: {
            'orders' => [{
              'id' => '456',
              'email' => 'test@example.com',
              'created_at' => Time.now.iso8601,
              'total_price' => '100.00',
              'currency' => 'USD',
              'fulfillment_status' => 'fulfilled',
              'financial_status' => 'paid'
            }]
          }
        )
      end

      before do
        allow_any_instance_of(Api::V1::Accounts::Integrations::ShopifyController).to receive(:shopify_client).and_return(shopify_client)

        allow_any_instance_of(Api::V1::Accounts::Integrations::ShopifyController).to receive(:client_id).and_return('test_client_id')
        allow_any_instance_of(Api::V1::Accounts::Integrations::ShopifyController).to receive(:client_secret).and_return('test_client_secret')

        allow(shopify_client).to receive(:get).with(
          path: 'customers/search.json',
          query: { query: "email:#{contact.email} OR phone:#{contact.phone_number}", fields: 'id,email,phone' }
        ).and_return(customers_response)

        allow(shopify_client).to receive(:get).with(
          path: 'orders.json',
          query: { customer_id: '123', status: 'any', fields: 'id,email,created_at,total_price,currency,fulfillment_status,financial_status' }
        ).and_return(orders_response)
      end

      it 'returns orders for the contact' do
        get "/api/v1/accounts/#{account.id}/integrations/shopify/orders",
            params: { contact_id: contact.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key('orders')
        expect(response.parsed_body['orders'].length).to eq(1)
        expect(response.parsed_body['orders'][0]['id']).to eq('456')
      end

      it 'returns error when contact has no email or phone' do
        contact_without_info = create(:contact, account: account)

        get "/api/v1/accounts/#{account.id}/integrations/shopify/orders",
            params: { contact_id: contact_without_info.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Contact information missing')
      end

      it 'returns empty array when no customers found' do
        empty_customers_response = instance_double(
          ShopifyAPIResponse,
          body: { 'customers' => [] }
        )

        allow(shopify_client).to receive(:get).with(
          path: 'customers/search.json',
          query: { query: "email:#{contact.email} OR phone:#{contact.phone_number}", fields: 'id,email,phone' }
        ).and_return(empty_customers_response)

        get "/api/v1/accounts/#{account.id}/integrations/shopify/orders",
            params: { contact_id: contact.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['orders']).to eq([])
      end
      # rubocop:enable RSpec/AnyInstance
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/integrations/shopify/orders",
            params: { contact_id: contact.id },
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/integrations/shopify' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    before do
      create(:integrations_hook, :shopify, account: account)
    end

    context 'when it is an administrator' do
      it 'deletes the shopify integration' do
        expect do
          delete "/api/v1/accounts/#{account.id}/integrations/shopify",
                 headers: admin.create_new_auth_token,
                 as: :json
        end.to change { account.hooks.count }.by(-1)

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized and keeps the integration' do
        expect do
          delete "/api/v1/accounts/#{account.id}/integrations/shopify",
                 headers: agent.create_new_auth_token,
                 as: :json
        end.not_to(change { account.hooks.count })

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/integrations/shopify",
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
