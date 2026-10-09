require 'rails_helper'

RSpec.describe 'Support SLA policies API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before { account.enable_features!('lynomia_support_tickets') }

  def post_policy(payload, as: administrator)
    post "/api/v1/accounts/#{account.id}/support/sla_policies",
         params: { sla_policy: payload }, headers: as.create_new_auth_token
  end

  describe 'authorization' do
    it 'is administrator only, because SLA targets are an account-wide setting' do
      get "/api/v1/accounts/#{account.id}/support/sla_policies", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/accounts/#{account.id}/support/sla_policies", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:success)
    end

    it 'answers 404 when the account has no support module' do
      account.disable_features!('lynomia_support_tickets')
      get "/api/v1/accounts/#{account.id}/support/sla_policies", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'create' do
    it 'stores a policy on the existing sla_policies table' do
      post_policy({ name: 'Standard', first_response_time_threshold: 3600, resolution_time_threshold: 86_400 })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['payload']).to include('name' => 'Standard')
      expect(Support::SlaPolicy.last.account_id).to eq(account.id)
    end

    it 'refuses a policy with no target at all, which could never govern anything' do
      post_policy({ name: 'Empty' })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses a negative or absurd threshold' do
      post_policy({ name: 'Negative', resolution_time_threshold: -1 })
      expect(response).to have_http_status(:unprocessable_entity)

      post_policy({ name: 'Absurd', resolution_time_threshold: 400.days.to_i })
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'tenant isolation' do
    it "never lists or fetches another account's policies" do
      theirs = create(:support_sla_policy, account: other_account)
      mine = create(:support_sla_policy, account: account, name: 'Mine')

      get "/api/v1/accounts/#{account.id}/support/sla_policies", headers: administrator.create_new_auth_token
      expect(response.parsed_body['payload'].pluck('id')).to eq([mine.id])

      get "/api/v1/accounts/#{account.id}/support/sla_policies/#{theirs.id}",
          headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'destroy' do
    # Nullifying rather than cascading: a case keeps its history and the due times it was already given, because
    # those were a commitment made when the policy was attached.
    it 'detaches the policy from its cases without touching their due times' do
      policy = create(:support_sla_policy, account: account)
      ticket = create(:support_ticket, account: account, sla_policy: policy, resolution_due_at: 1.day.from_now)
      due = ticket.resolution_due_at

      delete "/api/v1/accounts/#{account.id}/support/sla_policies/#{policy.id}",
             headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:no_content)
      ticket.reload
      expect(ticket.sla_policy_id).to be_nil
      expect(ticket.resolution_due_at).to be_within(1.second).of(due)
    end
  end
end
