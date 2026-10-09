require 'rails_helper'

RSpec.describe 'Analytics commerce', type: :request do
  include_context 'with commerce encryption'

  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'America/New_York') }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }
  let(:store) { create(:commerce_store, :zid, account: account, name: 'Zid Shop') }
  let(:range) { { since: '2026-10-01', until: '2026-10-07' } }

  def get_commerce(params = range, as: administrator, for_account: account)
    get "/api/v1/accounts/#{for_account.id}/analytics/commerce",
        params: params, headers: as.create_new_auth_token
  end

  def cart(state: :abandoned, targeted: nil, completed: nil, currency: 'SAR')
    Commerce::Cart.create!(
      account: account, commerce_store: store, provider: store.provider,
      provider_cart_id: "cart-#{SecureRandom.hex(6)}", state: state,
      first_seen_at: Time.utc(2026, 10, 2, 9, 0), last_provider_event_at: Time.utc(2026, 10, 2, 9, 0),
      abandoned_at: Time.utc(2026, 10, 2, 9, 0), targeted_at: targeted, completed_at: completed,
      currency: currency, visible_total: 250.0
    )
  end

  describe 'authorization' do
    it 'refuses an unauthenticated caller' do
      get "/api/v1/accounts/#{account.id}/analytics/commerce", params: range
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an agent, following the reporting permission' do
      get_commerce(as: agent)
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an administrator of another account on this account's endpoint" do
      get_commerce(as: other_administrator)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'payload' do
    before do
      cart(state: :completed, targeted: Time.utc(2026, 10, 2, 10, 0), completed: Time.utc(2026, 10, 2, 11, 0))
      cart(state: :completed, completed: Time.utc(2026, 10, 2, 11, 0))
      cart
      Commerce::ActionRun.create!(
        account: account, store: store, provider: store.provider, action_type: 'refund_partial',
        external_resource_id: '15', idempotency_key: "commerce-action:#{SecureRandom.uuid}",
        request_digest: 'd' * 64, status: :failed, error_code: 'PROVIDER_REFUSED',
        created_at: Time.utc(2026, 10, 2, 9, 0)
      )
    end

    it 'returns the shared envelope' do
      get_commerce
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']).to include('family' => 'commerce', 'timezone' => 'Asia/Kuwait')
    end

    it 'reports the cart funnel' do
      get_commerce
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['carts_seen']['value']).to eq(3)
      expect(kpis['carts_abandoned']['value']).to eq(3)
      expect(kpis['carts_targeted']['value']).to eq(1)
      expect(kpis['carts_completed']['value']).to eq(2)
    end

    it 'separates a completion that followed outreach from one that had none' do
      get_commerce
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['post_target_completions']['value']).to eq(1)
      expect(kpis['untargeted_completions']['value']).to eq(1)
    end

    it 'labels the open readings as current state' do
      get_commerce
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['open_abandoned_now']['kind']).to eq('current_state')
      expect(kpis['actions_unresolved_now']['kind']).to eq('current_state')
    end

    it 'publishes no money figure anywhere in the payload' do
      get_commerce
      keys = response.parsed_body['kpis'].pluck('key')

      expect(keys).not_to include('revenue', 'gmv', 'cart_value', 'visible_total', 'profit')
      expect(response.parsed_body['kpis'].pluck('unit').uniq).to contain_exactly('count', 'percent')
    end

    it 'reports cart counts per currency rather than a money total' do
      get_commerce(range.merge(breakdown_by: 'currency'))
      breakdown = response.parsed_body['breakdowns'].first

      expect(breakdown['unit']).to eq('count')
      expect(breakdown['rows'].first).to include('label' => 'SAR', 'value' => 3)
    end

    it 'breaks down failed actions by their code' do
      get_commerce(range.merge(breakdown_by: 'action_error'))

      expect(response.parsed_body['breakdowns'].first['rows'].first)
        .to include('label' => 'PROVIDER_REFUSED', 'value' => 1)
    end
  end

  describe 'rejected requests' do
    it 'refuses an unknown breakdown with 422 and the allowed list' do
      get_commerce(range.merge(breakdown_by: 'inbox'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('provider, store, currency, action_type, action_error')
    end

    it 'refuses a provider this product does not support' do
      get_commerce(range.merge(provider: 'etsy'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('provider')
    end
  end
end
