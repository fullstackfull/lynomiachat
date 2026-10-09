require 'rails_helper'

RSpec.describe 'Contact Merge Action API', type: :request do
  let(:account) { create(:account) }
  let!(:base_contact) { create(:contact, account: account) }
  let!(:mergee_contact) { create(:contact, account: account) }

  describe 'POST /api/v1/accounts/{account.id}/actions/contact_merge' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/actions/contact_merge"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    # Lynomia (docs/p10/04-contact-merge-linking.md): a merge destroys a contact and moves its campaign,
    # commerce and support-case rows, so it follows the same boundary as deleting one -- an administrator, or an
    # agent whose custom role grants `contact_manage`. Before P10 this endpoint had no authorize call at all and
    # a plain agent could merge; that is what the second context below now asserts is refused.
    context 'when it is an administrator' do
      let(:administrator) { create(:user, account: account, role: :administrator) }
      let(:merge_action) { double }

      before do
        allow(ContactMergeAction).to receive(:new).and_return(merge_action)
        allow(merge_action).to receive(:perform)
      end

      it 'merges two contacts by calling contact merge action' do
        post "/api/v1/accounts/#{account.id}/actions/contact_merge",
             params: { base_contact_id: base_contact.id, mergee_contact_id: mergee_contact.id },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['id']).to eq(base_contact.id)
        expected_params = { account: account, base_contact: base_contact, mergee_contact: mergee_contact }
        expect(ContactMergeAction).to have_received(:new).with(expected_params)
        expect(merge_action).to have_received(:perform)
      end
    end

    context 'when it is a plain agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'refuses, because a merge is destructive' do
        expect(ContactMergeAction).not_to receive(:new)

        post "/api/v1/accounts/#{account.id}/actions/contact_merge",
             params: { base_contact_id: base_contact.id, mergee_contact_id: mergee_contact.id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent whose custom role grants contact management' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:custom_role) { create(:custom_role, account: account, permissions: ['contact_manage']) }
      let(:merge_action) { double }

      before do
        agent.account_users.find_by(account: account).update!(custom_role: custom_role)
        allow(ContactMergeAction).to receive(:new).and_return(merge_action)
        allow(merge_action).to receive(:perform)
      end

      it 'allows the merge' do
        post "/api/v1/accounts/#{account.id}/actions/contact_merge",
             params: { base_contact_id: base_contact.id, mergee_contact_id: mergee_contact.id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
      end
    end

    context 'when the mergee belongs to another account' do
      let(:administrator) { create(:user, account: account, role: :administrator) }
      let(:foreign_contact) { create(:contact, account: create(:account)) }

      it 'answers not found rather than merging across accounts' do
        post "/api/v1/accounts/#{account.id}/actions/contact_merge",
             params: { base_contact_id: base_contact.id, mergee_contact_id: foreign_contact.id },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
