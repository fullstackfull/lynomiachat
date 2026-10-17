require 'rails_helper'

# What a shopper agreed to receive, over HTTP (docs/commerce/31-messaging-consent.md).
#
# WHY THIS SURFACE EXISTS AT ALL. Phase 3 built the consent model and the one gate that reads it,
# and nothing could read or write a decision except the keyword listener and the provider's own
# suppression reports. A merchant whose customer says "stop sending me offers" in a phone call
# had no way to record it. These examples are written against the boundary: what a REQUEST can
# read and change, because that is what a merchant and an attacker both have.
RSpec.describe 'Commerce consents API', type: :request do
  let(:account) { create(:account).tap { |record| record.enable_features!('lynomia_commerce') } }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Rasha') }
  let(:base) { "/api/v1/accounts/#{account.id}/commerce/consents" }

  it 'is for administrators of a Commerce account, and only for their own contacts' do
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    foreign = create(:contact, account: create(:account))
    get "#{base}/#{foreign.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    account.disable_features!('lynomia_commerce')
    get base, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  # The merchant's real question is "will this person be messaged", and a state alone cannot
  # answer it: no row means allowed for one class and refused for the other.
  it 'answers what would happen now, not only what is stored' do
    get "#{base}/#{contact.id}", headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body['purposes']
    expect(body['transactional']).to include('state' => nil, 'refusal' => nil)
    expect(body['promotional']).to include('state' => nil, 'refusal' => 'promotional_consent_missing')
  end

  it 'records what a shopper told the merchant, with the note that says where it came from' do
    put "#{base}/#{contact.id}", params: { purpose: 'promotional', state: 'granted', note: 'Agreed on the phone, 12 Feb' },
                                 headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['purposes']['promotional'])
      .to include('state' => 'granted', 'source' => 'merchant', 'note' => 'Agreed on the phone, 12 Feb',
                  'refusal' => nil)
    expect(Commerce::MessagingEligibility.allows?(contact.reload, :promotional)).to be(true)
  end

  # A grant typed in by a merchant is a claim about a conversation that happened elsewhere.
  # Without a note it is indistinguishable from adding somebody to a marketing list.
  it 'refuses a decision with no note, no purpose or a state a merchant may not set' do
    [{ purpose: 'promotional', state: 'granted' },
     { purpose: 'promotional', state: 'granted', note: '  ' },
     { purpose: 'marketing', state: 'granted', note: 'x' },
     { purpose: 'promotional', state: 'suppressed', note: 'x' },
     { state: 'granted', note: 'x' }].each do |params|
      put "#{base}/#{contact.id}", params: params, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity), params.inspect
    end

    expect(Commerce::MessagingConsent.where(contact_id: contact.id)).to be_empty
  end

  # A withdrawal of order updates leaves nothing sendable, and the two classes say WHY
  # separately: one was refused, the other was never granted. The merchant needs both answers --
  # getting the promotional grant back would still leave the order updates refused.
  it 'records a withdrawal, after which neither class may be sent' do
    put "#{base}/#{contact.id}", params: { purpose: 'transactional', state: 'withdrawn', note: 'Asked to stop' },
                                 headers: admin.create_new_auth_token, as: :json

    purposes = response.parsed_body['purposes']
    expect(purposes['transactional']).to include('state' => 'withdrawn', 'refusal' => 'consent_withdrawn')
    expect(purposes['promotional']).to include('state' => nil, 'refusal' => 'promotional_consent_missing')
    expect(Commerce::MessagingEligibility.allows?(contact.reload, :transactional)).to be(false)
    expect(Commerce::MessagingEligibility.allows?(contact, :promotional)).to be(false)
  end

  # An operator fixing a delivery fault must not be able to overturn an opt-out by doing so.
  it 'clears a suppression and leaves a withdrawal exactly where it was' do
    Commerce::MessagingConsents.record(account: account, contact: contact,
                                       decision: Commerce::MessagingConsents::Decision.new(
                                         state: :suppressed, source: 'provider', purposes: ['transactional']
                                       ))
    Commerce::MessagingConsents.record(account: account, contact: contact,
                                       decision: Commerce::MessagingConsents::Decision.new(
                                         state: :withdrawn, source: 'keyword', purposes: ['promotional']
                                       ))

    delete "#{base}/#{contact.id}", headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body['purposes']
    expect(body['transactional']).to include('state' => nil, 'refusal' => nil)
    expect(body['promotional']).to include('state' => 'withdrawn')
  end

  it 'lists recent decisions of this account only, newest first' do
    other = create(:contact, account: account, name: 'Omar')
    Commerce::MessagingConsents.record(account: account, contact: contact,
                                       decision: Commerce::MessagingConsents::Decision.new(
                                         state: :granted, source: 'checkout', purposes: ['promotional']
                                       ))
    travel(1.minute) do
      Commerce::MessagingConsents.record(account: account, contact: other,
                                         decision: Commerce::MessagingConsents::Decision.new(
                                           state: :withdrawn, source: 'keyword', purposes: ['promotional']
                                         ))
    end
    foreign_account = create(:account)
    Commerce::MessagingConsents.record(account: foreign_account, contact: create(:contact, account: foreign_account, name: 'Elsewhere'),
                                       decision: Commerce::MessagingConsents::Decision.new(
                                         state: :granted, source: 'checkout', purposes: ['promotional']
                                       ))

    get base, params: { purpose: 'promotional' }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['payload'].pluck('contact_name')).to eq(%w[Omar Rasha])
    expect(response.body).not_to include('Elsewhere')
  end

  # A FILTER THE SERVER DOES NOT UNDERSTAND IS A PARAMETER ERROR. Dropping it answered a narrower
  # question with the whole list, and the question that matters is "who has opted out": a merchant
  # shown every decision instead reads the opt-ins as opt-outs.
  it 'refuses a filter it does not recognise rather than answering a different question' do
    get base, params: { state: 'opted_out' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    get base, params: { purpose: 'marketing' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    # An absent filter is still "no filter", not a bad one.
    get base, params: { state: '' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'audits every decision with its author' do
    put "#{base}/#{contact.id}", params: { purpose: 'promotional', state: 'granted', note: 'Told us in store' },
                                 headers: admin.create_new_auth_token, as: :json

    entry = Custom::AuditLog.where(comment: 'commerce.consent_changed').sole
    expect(entry).to have_attributes(user_id: admin.id, auditable_id: contact.id, auditable_type: 'Contact')
  end
end
