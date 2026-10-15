require 'rails_helper'

# WHICH INSTALLATION A CAMPAIGN BELONGS TO, and why a campaign that does not say is a
# different campaign from the one the merchant previewed.
#
# `commerce_store_id` has been read by three things since P5B and P5E -- the audience's
# Commerce aggregates, the send boundary's partner-consent half, and the preview -- and
# written by none of them, because upstream's `campaign_params` has no concept of it and does
# not permit it. So every campaign saved through the API was account-wide: the preview
# answered "40 of your customers" with the store id it was given, and the send then resolved
# against all 180 without it. These examples pin the field end to end.
RSpec.describe 'Campaign store scope', type: :request do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_sms, account: account)) }
  let(:store) { create(:commerce_store, account: account, provider: 'storesyria', status: :active) }

  def create_campaign(store_id)
    post "/api/v1/accounts/#{account.id}/campaigns",
         params: { campaign: { title: 'Autumn', message: 'hello', inbox_id: inbox.id, campaign_type: 'one_off',
                               scheduled_at: 1.hour.from_now, commerce_store_id: store_id } },
         headers: administrator.create_new_auth_token, as: :json
  end

  it 'records the installation the campaign belongs to' do
    create_campaign(store.id)

    expect(response).to have_http_status(:success)
    expect(Campaign.last.commerce_store_id).to eq(store.id)
  end

  # ANOTHER TENANT'S STORE IS REFUSED, not silently dropped. A campaign that quietly became
  # account-wide because the id was ignored is worse than one that was not created: the
  # merchant asked to message one store's customers and would have messaged everybody's.
  it 'refuses a store that is not this account’s, with a 422' do
    foreign = create(:commerce_store, account: create(:account), provider: 'storesyria', status: :active)

    create_campaign(foreign.id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Campaign.count).to eq(0)
  end

  it 'leaves a campaign with no store account-wide, which is every campaign before this' do
    create_campaign(nil)

    expect(response).to have_http_status(:success)
    expect(Campaign.last.commerce_store_id).to be_nil
  end
end
