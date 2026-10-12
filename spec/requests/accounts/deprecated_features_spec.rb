require 'rails_helper'

# The account payload the dashboard reads on every load (app/views/api/v1/models/_account.json.jbuilder).
#
# TWO THINGS ARE ASSERTED HERE, and the first one is why this file exists: the payload must RENDER. It carried
# a `Shopify::FeatureGate` call that was left behind when the legacy Shopify integration was retired -- the
# class was deleted and the reference was not -- so `GET /api/v1/accounts/:id` answered 500 and the dashboard
# could not load at all. Nothing asserted that this view renders, which is how a deleted constant reached a
# pushed commit (docs/product-refinement/02-shopify-retirement.md §correction).
RSpec.describe 'Account payload features', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:deprecated) { BillingPlan.deprecated_features.first }

  def payload
    get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json
    response.parsed_body
  end

  it 'renders' do
    expect(payload['id']).to eq(account.id)
    expect(response).to have_http_status(:success)
  end

  # A retired feature's line stays in config/features.yml so persisted bit positions do not shift. It must
  # still never reach the dashboard: a flag that unlocks a page which no longer exists is a menu entry
  # that 404s.
  it 'never advertises a deprecated feature, even when the account has it enabled' do
    expect(deprecated).to be_present
    account.enable_features!(deprecated)

    expect(account.reload.enabled_features).to have_key(deprecated)
    expect(payload['features']).not_to have_key(deprecated)
  end

  it 'still advertises a feature that is not deprecated' do
    account.enable_features!('inbound_emails')

    expect(payload['features']).to have_key('inbound_emails')
  end

  # The list is read from the one file that declares it, so a feature retired later is covered without
  # anybody editing the view.
  it 'reads the deprecated list from the feature declarations rather than a second list' do
    expect(BillingPlan.deprecated_features).to include('shopify_integration')
    expect(BillingPlan.assignable_features.map { |feature| feature['name'] }).not_to include('shopify_integration')
  end
end
