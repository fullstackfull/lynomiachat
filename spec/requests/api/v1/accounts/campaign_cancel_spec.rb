require 'rails_helper'

# THE ROUTE, NOT THE MODEL. spec/models/campaign_cancellation_spec covers `Campaign#cancel!`
# and the guard that reads the status; nothing covered the surface a merchant actually
# reaches, and the surface was broken in a way no model spec can see.
#
# `Api::V1::Accounts::CampaignsController` declares `before_action :check_authorization` with
# no `only:`, so it runs for the prepended `cancel` action too, and `check_authorization`
# calls `authorize(Campaign)` with no query. Pundit then derives the query from the action
# name -- `cancel?` -- which CampaignPolicy did not answer. The result was a NoMethodError, a
# 500, and a cancel button that could not stop a campaign that was sending.
RSpec.describe 'Campaign cancellation', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_sms, account: account)) }
  let(:campaign) do
    create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago)
  end

  it 'stops the campaign for an administrator and reports its new state' do
    post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/cancel",
         params: { reason: 'wrong audience' }, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['campaign_status']).to eq('cancelled')
    expect(campaign.reload).to be_cancelled
  end

  # Cancelling is gated as an update, which is an administrator's act -- the same bar as
  # editing the campaign, and a lower one than deleting it.
  it 'refuses an agent' do
    post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/cancel",
         headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(campaign.reload).not_to be_cancelled
  end

  it 'refuses a campaign that has already finished, without a 500' do
    campaign.update!(campaign_status: :completed)

    post "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/cancel",
         headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  # ANOTHER ACCOUNT'S CAMPAIGN IS NOT FOUND, not refused -- the lookup is scoped to the
  # account in the path, and the account in the path is checked against the token.
  it 'does not reach another account’s campaign' do
    other = create(:campaign, account: create(:account), campaign_type: :one_off)

    post "/api/v1/accounts/#{account.id}/campaigns/#{other.display_id}/cancel",
         headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(other.reload).not_to be_cancelled
  end
end
