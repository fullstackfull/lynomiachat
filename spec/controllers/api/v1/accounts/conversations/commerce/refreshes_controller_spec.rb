require 'rails_helper'

# An agent's Refresh in the conversation's Commerce section (docs/commerce/24-realtime-architecture.md): the open view is
# read again from the stores even when cached, at most once per COOLDOWN per contact and view, never past a store's
# rate-limit backoff.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Commerce refresh', type: :request do
  include_context 'with four commerce stores'

  let(:refresh_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/refresh" }
  let(:refresh) do
    lambda do |store_id = nil, user = agent|
      post refresh_path, params: { store_id: store_id }.compact, headers: user.create_new_auth_token, as: :json
      response.parsed_body
    end
  end

  before do
    Redis::Alfred.scan_each(match: "COMMERCE::REFRESH_REQUEST::ACCOUNT::#{account.id}::*") { |key| Redis::Alfred.delete(key) }
    Redis::Alfred.delete("COMMERCE::SALLA::MERCHANT::#{salla.external_store_id}::BACKOFF")
  end

  it 'reads every store again although its orders are cached, then waits out the cooldown, shared by everyone' do
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/overview", headers: agent.create_new_auth_token, as: :json
    WebMock.reset_executed_requests!

    body = refresh.call

    expect(response).to have_http_status(:ok)
    expect(body).to include('linked_stores_count' => 4, 'orders_count_visible' => 16, 'partial' => false)
    expect(woo_search).to have_been_requested.once
    expect(salla_customer_orders).to have_been_requested.once
    expect(zid_customer_orders).to have_been_requested.once

    WebMock.reset_executed_requests!
    body = refresh.call(nil, admin)
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers['Retry-After'].to_i).to be_between(1, 30)
    expect(body).to eq('error' => { 'code' => 'RATE_LIMITED', 'retry_after' => response.headers['Retry-After'].to_i })
    expect(a_request(:any, /shop\.example|salla|zid|myshopify/)).not_to have_been_made

    travel(31.seconds) { refresh.call }
    expect(response).to have_http_status(:ok)
  end

  it 'reads only the open store, with its own cooldown apart from the overview\'s' do
    body = refresh.call(zid.id)

    expect(response).to have_http_status(:ok)
    expect(body).to include('state' => 'linked', 'stale' => false)
    expect(zid_customer_orders).to have_been_requested.once
    expect(a_request(:any, /shop\.example|salla|myshopify/)).not_to have_been_made

    refresh.call(zid.id)
    expect(response).to have_http_status(:too_many_requests)
    refresh.call(woo.id)
    expect(response).to have_http_status(:ok)
    refresh.call
    expect(response).to have_http_status(:ok)
  end

  it 'does not read a store past its rate-limit backoff, and serves its last orders as stale' do
    refresh.call(salla.id)
    Redis::Alfred.set("COMMERCE::SALLA::MERCHANT::#{salla.external_store_id}::BACKOFF", 1, ex: 60)
    WebMock.reset_executed_requests!

    body = travel(31.seconds) { refresh.call(salla.id) }

    expect(response).to have_http_status(:ok)
    expect(body).to include('stale' => true, 'error' => 'RATE_LIMITED')
    expect(body['orders'].size).to eq(5)
    expect(a_request(:any, /salla/)).not_to have_been_made
  end

  it 'refuses a store that is not an active store of an enabled provider in this account' do
    other_store = create(:commerce_store, account: create(:account))
    InstallationConfig.find_by!(name: 'ZID_ENABLED').update!(value: false)
    GlobalConfig.clear_cache
    woo.update!(status: :disabled)

    [other_store, zid, woo].each do |store|
      refresh.call(store.id)
      expect(response).to have_http_status(:not_found)
    end
    expect(a_request(:any, /shop\.example|zid/)).not_to have_been_made
  end

  it 'is refused without Commerce, to agents who cannot see the conversation, and to other accounts' do
    outsider = create(:user, account: account, role: :agent)
    other = create(:user, account: create(:account), role: :administrator)

    refresh.call(nil, outsider)
    expect(response).to have_http_status(:unauthorized)
    refresh.call(nil, other)
    expect(response).to have_http_status(:unauthorized)
    account.disable_features!('lynomia_commerce')
    refresh.call
    expect(response).to have_http_status(:unauthorized)
    expect(a_request(:any, /shop\.example|salla|zid|myshopify/)).not_to have_been_made
    expect(Redis::Alfred.scan_each(match: "COMMERCE::REFRESH_REQUEST::ACCOUNT::#{account.id}::*").to_a).to be_empty
  end
end
# rubocop:enable RSpec/MultipleExpectations
