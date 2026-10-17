require 'rails_helper'

RSpec.describe 'Account link code API', type: :request do
  include_context 'with account link codes'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:platform_app) { create(:platform_app) }
  let(:path) { "/api/v1/accounts/#{account.id}/integrations/account_link_code" }
  let(:mint) { { platform_app_id: platform_app.id } }

  it 'gives an administrator a one-time code, then reports progress without leaking the digest' do
    post path, params: mint, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('code' => /\A[A-Z2-9-]{19}\z/)

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('status' => 'waiting')
    expect(response.body).not_to include('digest')
  end

  it 'is refused to an agent of the same account' do
    post path, params: mint, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  # The one that matters most: an administrator is only an administrator of their OWN account. Were this to
  # pass, any Lynomia customer could mint a proof of ownership over any other customer's workspace.
  it 'is refused to an administrator of a different account' do
    outsider = create(:user, account: create(:account), role: :administrator)

    post path, params: mint, headers: outsider.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(Integrations::AccountLinkCode.status(account)).to eq({ status: 'none' })
  end

  it 'is refused without a session' do
    post path, params: mint, as: :json
    expect(response).to have_http_status(:unauthorized)

    get path, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  # The audience is what stops a code being a bearer token for whichever integration gets it first.
  it 'requires the merchant to name the integration the code is for' do
    post path, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post path, params: { platform_app_id: 0 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    expect(Integrations::AccountLinkCode.status(account)).to eq({ status: 'none' })
  end

  it 'reports which integration the code was minted for' do
    post path, params: mint, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['platform_app']).to include('id' => platform_app.id, 'name' => platform_app.name)

    get path, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['intended_app']).to eq(platform_app.name)
  end

  it 'replaces the previous code rather than leaving two live' do
    post path, params: mint, headers: admin.create_new_auth_token, as: :json
    first = response.parsed_body['code']

    post path, params: mint, headers: admin.create_new_auth_token, as: :json

    expect(Integrations::AccountLinkCode.redeem(first, platform_app: platform_app)).to eq(:unknown)
  end
end
