require 'rails_helper'

# An agent removes a link the contact's WhatsApp phone made automatically (docs/commerce/25-customer-360.md §identity):
# the phone must not link the same customer again on the next read, in any provider, until someone links by hand.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Commerce link suppression', type: :request do
  include_context 'with four commerce stores'

  let(:unlink) { ->(store) { delete "#{stores_path}/#{store.id}/link", headers: agent.create_new_auth_token, as: :json } }

  it 'keeps a removed link removed in every store, offering the matched customer instead, and audits it without identifiers' do
    stores = [woo, salla, zid, shopify]
    stores.each do |store|
      expect(panel.call(store)).to include('state' => 'linked')
      unlink.call(store)
    end

    expect(stores.map { |store| panel.call(store)['state'] }).to eq(%w[suggested suggested suggested suggested])
    expect(Commerce::CustomerLink.where(contact: contact).pluck(:match_source)).to all(eq('suppressed'))
    get stores_path, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('linked')).to eq([false, false, false, false])
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/overview", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('linked_stores_count' => 0, 'orders_count_visible' => 0)

    unlink.call(woo)
    expect(response).to have_http_status(:not_found)

    removed = Custom::AuditLog.where(comment: 'commerce.customer_link_removed')
    expect(removed.pluck(:audited_changes)).to all(eq('match_source' => %w[verified_phone suppressed]))
    expect(removed.pluck(:user_id).uniq).to eq([agent.id])
    expect(removed.to_json).not_to include('551112233', 'guest:', '1227534533', '90001')
  end

  it 'lets an agent link the customer again by hand' do
    panel.call(salla)
    unlink.call(salla)
    token = panel.call(salla)['candidates'].sole['token']

    post "#{stores_path}/#{salla.id}/link", headers: agent.create_new_auth_token, as: :json, params: { token: token }

    expect(response.parsed_body).to include('state' => 'linked')
    expect(salla.customer_links.sole).to have_attributes(contact: contact, match_source: 'manual', confirmed_by: agent)
    expect(Custom::AuditLog.where(auditable_type: 'Commerce::CustomerLink').last)
      .to have_attributes(comment: 'commerce.customer_link_changed', audited_changes: { 'match_source' => %w[suppressed manual] })
  end

  it 'no longer refreshes a removed link on the store\'s order events' do
    panel.call(zid)
    link = zid.customer_links.sole
    unlink.call(zid)
    clear_enqueued_jobs

    Commerce::Realtime.order_event(zid, { 'customer' => { 'id' => 90_001 } })
    Commerce::RefreshJob.perform_now(link.id)

    expect(enqueued_jobs.pluck('job_class')).not_to include('Commerce::RefreshJob', 'ActionCableBroadcastJob')
  end
end
# rubocop:enable RSpec/MultipleExpectations
