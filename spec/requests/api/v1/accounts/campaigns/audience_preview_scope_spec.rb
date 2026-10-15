require 'rails_helper'

# STORE-SCOPED AUDIENCE PREVIEW (P5B).
#
# A preview and a send have to be the same query or the preview is decoration. A store-scoped
# campaign reads its audience's Commerce aggregates against that installation's links only, so
# a preview that omitted the store would answer "more than three orders anywhere" while the
# send answers "more than three orders with us" -- and the merchant would be shown a number
# their campaign cannot reach.
RSpec.describe 'Campaign audience preview, store scope', type: :request do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/campaigns/audience_preview" }
  let(:ours) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-1', status: :active) }
  let(:theirs) { create(:commerce_store, account: account, provider: 'shopify', external_store_id: 'sh-1', status: :active) }
  let(:shopper) { create(:contact, account: account, name: 'Shopper', email: 'shopper@example.test') }
  let(:buyers) do
    create(:custom_filter, account: account, user: admin, filter_type: :contact, shared: true, name: 'Buyers',
                           query: { 'payload' => [{ 'attribute_key' => 'commerce_orders_count',
                                                    'filter_operator' => 'is_greater_than', 'values' => ['3'] }] })
  end

  before do
    create(:installation_config, name: 'STORESYRIA_ENABLED', value: true)
    create(:installation_config, name: 'SHOPIFY_COMMERCE_ENABLED', value: true)
    account.enable_features!('lynomia_commerce')
    # The grant, because a preview counts the contacts a campaign could actually reach and a
    # campaign with no provider template category is promotional.
    Commerce::MessagingConsents.record(
      account: account, contact: shopper,
      decision: Commerce::MessagingConsents::Decision.new(state: :granted, source: 'merchant')
    )
    # Four orders at the OTHER store, none here. The shape that tells a scoped aggregate from
    # an unscoped one; a contact who only ever bought from one store proves nothing.
    link = create(:commerce_customer_link, account: account, store: theirs, contact: shopper, external_customer_id: 'c-sh')
    Commerce::ContactMetric.create!(account: account, customer_link: link, orders_count: 4, active_orders_count: 0,
                                    spend: {}, order_statuses: [], fetched_at: Time.current)
    create(:commerce_customer_link, account: account, store: ours, contact: shopper, external_customer_id: 'c-sy')
  end

  def preview(params)
    post url, params: params, headers: headers, as: :json
    response.parsed_body['count']
  end

  it 'counts every store when no installation is named' do
    expect(preview(audience: [{ type: 'Audience', id: buyers.id }])).to eq(1)
  end

  it 'counts only the named installation, which is what that campaign would send' do
    expect(preview(audience: [{ type: 'Audience', id: buyers.id }], commerce_store_id: ours.id)).to eq(0)
  end

  it 'agrees with what the campaign itself resolves' do
    campaign = create(:campaign, account: account, campaign_type: :one_off,
                                 inbox: create(:inbox, account: account, channel: create(:channel_sms, account: account)),
                                 commerce_store: ours, audience: [{ type: 'Audience', id: buyers.id }])

    expect(campaign.audience_contacts.count)
      .to eq(preview(audience: [{ type: 'Audience', id: buyers.id }], commerce_store_id: ours.id))
  end

  # TENANCY: a store id that is not this account's is a refusal at the boundary, not a count
  # of zero. Zero reads as "nobody qualifies", which is the wrong thing to tell somebody whose
  # real mistake was naming a store that is not theirs.
  it 'refuses a store belonging to another account with 422 rather than answering zero' do
    stranger = create(:commerce_store, account: create(:account), provider: 'storesyria', external_store_id: 'sy-x')

    post url, params: { audience: [{ type: 'Audience', id: buyers.id }], commerce_store_id: stranger.id },
              headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'refuses an unauthenticated caller' do
    post url, params: { audience: [{ type: 'Audience', id: buyers.id }] }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
