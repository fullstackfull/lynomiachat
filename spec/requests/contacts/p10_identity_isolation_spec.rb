require 'rails_helper'

# Two tenants holding THE SAME phone number and email address, which is the fixture that catches a filter keyed
# on the wrong thing: a query missing its `account_id` returns the other tenant's row and looks like a hit
# (docs/p10/07-security-performance.md §isolation).
RSpec.describe 'P10 identity tenant isolation', type: :request do
  let(:phone) { '+96560000002' }
  let(:email) { 'dana.alt@example.com' }

  # Deliberately identical on both sides. Eager, because one example asks about the rows directly rather than
  # through `mine` or `theirs`.
  let!(:tenants) do
    Array.new(2) do |index|
      account = create(:account, name: "tenant-#{index}")
      account.enable_features('lynomia_unified_identity')
      account.save!
      contact = create(:contact, account: account, name: 'Dana')
      administrator = create(:user, account: account, role: :administrator)
      inbox = create(:inbox, account: account)
      identity = create(:contact_identity, account: account, contact: contact, identity_type: :phone, value: phone)
      { account: account, contact: contact, administrator: administrator, inbox: inbox, identity: identity }
    end
  end
  let(:mine) { tenants[0] }
  let(:theirs) { tenants[1] }

  def url(tenant, suffix = '')
    "/api/v1/accounts/#{tenant[:account].id}/contacts/#{tenant[:contact].id}/identities#{suffix}"
  end

  describe 'the same value in two accounts' do
    it 'is allowed, because identity is per account' do
      expect(ContactIdentity.where(value: phone).count).to eq(2)
      expect(ContactIdentity.where(value: phone).pluck(:account_id).uniq.length).to eq(2)
    end

    it 'lists only this account identity' do
      get url(mine), headers: mine[:administrator].create_new_auth_token, as: :json

      ids = response.parsed_body['payload'].map { |row| row['id'] }
      expect(ids).to eq([mine[:identity].id])
      expect(ids).not_to include(theirs[:identity].id)
    end
  end

  describe 'reaching across the boundary' do
    it 'cannot read another account contact identities' do
      get "/api/v1/accounts/#{mine[:account].id}/contacts/#{theirs[:contact].id}/identities",
          headers: mine[:administrator].create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'cannot read its own contact through another account id' do
      get "/api/v1/accounts/#{theirs[:account].id}/contacts/#{mine[:contact].id}/identities",
          headers: mine[:administrator].create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'cannot unlink an identity belonging to another account' do
      delete url(mine, "/#{theirs[:identity].id}"),
             headers: mine[:administrator].create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(ContactIdentity.where(id: theirs[:identity].id)).to exist
    end

    it 'does not report a conflict against another account value' do
      post url(theirs), params: { identity_type: 'email', value: email },
                        headers: theirs[:administrator].create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      post url(mine), params: { identity_type: 'email', value: email },
                      headers: mine[:administrator].create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ContactIdentity.where(identity_type: :email, value: email).count).to eq(2)
    end
  end

  describe 'the inbound match' do
    it 'resolves to this account contact, not the other one holding the same number' do
      contact_inbox = ContactInboxWithContactBuilder.new(
        inbox: mine[:inbox], source_id: SecureRandom.uuid,
        contact_attributes: { name: 'Dana', phone_number: phone }
      ).perform

      expect(contact_inbox.contact_id).to eq(mine[:contact].id)
      expect(contact_inbox.contact.account_id).to eq(mine[:account].id)
    end
  end

  describe 'a merge' do
    it 'refuses a mergee from another account' do
      post "/api/v1/accounts/#{mine[:account].id}/actions/contact_merge",
           params: { base_contact_id: mine[:contact].id, mergee_contact_id: theirs[:contact].id },
           headers: mine[:administrator].create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Contact.where(id: theirs[:contact].id)).to exist
    end

    it 'leaves the other account identity in place' do
      other = create(:contact, account: mine[:account].id ? mine[:account] : nil)
      ContactMergeAction.new(account: mine[:account], base_contact: mine[:contact], mergee_contact: other).perform

      expect(theirs[:identity].reload.contact_id).to eq(theirs[:contact].id)
    end
  end
end
