require 'rails_helper'

# P9.8: one place that proves every P9 write and read surface is account-scoped, against a MIRRORED fixture --
# two accounts given the same shape of data, so a missing account predicate shows up as a doubled number or a
# borrowed record rather than as nothing at all. A spec that creates data in only one account cannot catch a
# missing predicate, because the wrong answer and the right answer look identical.
RSpec.describe 'P9 tenant isolation', type: :request do
  let(:range) { { since: 6.days.ago.to_date.to_s, until: Date.current.to_s } }

  let!(:mine) { build_tenant('p9-mine') }
  let!(:theirs) { build_tenant('p9-theirs') }

  def build_tenant(name)
    account = create(:account, name: name, settings: { 'reporting_timezone' => 'Asia/Kuwait' })
    account.enable_features!('lynomia_support_tickets', 'reports')
    admin = create(:user, account: account, role: :administrator)
    agent = create(:user, account: account, role: :agent)
    inbox = create(:inbox, account: account)
    contact = create(:contact, account: account)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    team = create(:team, account: account)
    policy = create(:support_sla_policy, account: account, name: "#{name} standard")
    ticket = create(:support_ticket, account: account, title: "#{name} case", contact: contact,
                                     conversation: conversation, inbox: inbox, assignee: agent,
                                     team: team, created_by: admin, sla_policy: policy)
    Support::Tickets::EventRecorder.new(ticket: ticket, user: admin).record('note', body: "#{name} private note")

    { account: account, admin: admin, agent: agent, inbox: inbox, contact: contact,
      conversation: conversation, team: team, policy: policy, ticket: ticket }
  end

  def auth(tenant, role = :admin) = tenant[role].create_new_auth_token

  def support_path(tenant, suffix = '') = "/api/v1/accounts/#{tenant[:account].id}/support/tickets#{suffix}"

  describe 'the case list' do
    it "returns only the caller's own cases, though both tenants have one of the same shape" do
      get support_path(mine), headers: auth(mine)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('title')).to eq(['p9-mine case'])
      expect(response.parsed_body['meta']['total_entries']).to eq(1)
    end

    it 'counts only the caller’s own cases in every tab' do
      get support_path(mine), headers: auth(mine)

      counts = response.parsed_body['meta']['counts']
      expect(counts.values.max).to eq(1)
    end

    it 'refuses an administrator of the other account' do
      get support_path(mine), headers: auth(theirs)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a filter id belonging to the other account rather than returning an empty page' do
      get support_path(mine), params: { contact_id: theirs[:contact].id }, headers: auth(mine)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('contact_id')
    end

    it 'rejects a team id belonging to the other account' do
      get support_path(mine), params: { team_id: theirs[:team].id }, headers: auth(mine)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects an assignee id belonging to the other account' do
      get support_path(mine), params: { assignee_id: theirs[:agent].id }, headers: auth(mine)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'one case' do
    it "answers 404 for the other account's case id, not 403" do
      get support_path(mine, "/#{theirs[:ticket].id}"), headers: auth(mine)

      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 for the other account's reference, which is the same number in both tenants" do
      expect(theirs[:ticket].reference).to eq(mine[:ticket].reference)

      get support_path(mine, "/#{theirs[:ticket].reference}"), headers: auth(mine)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['id']).to eq(mine[:ticket].id)
    end

    it "will not accept the other account's conversation as a link" do
      patch support_path(mine, "/#{mine[:ticket].id}"),
            params: { ticket: { conversation_id: theirs[:conversation].id } }, headers: auth(mine)

      expect(response).to have_http_status(:not_found)
      expect(mine[:ticket].reload.conversation_id).to eq(mine[:conversation].id)
    end

    it "will not accept the other account's SLA policy" do
      patch support_path(mine, "/#{mine[:ticket].id}"),
            params: { ticket: { sla_policy_id: theirs[:policy].id } }, headers: auth(mine)

      expect(response).to have_http_status(:not_found)
    end

    it "will not open a case against the other account's contact" do
      post support_path(mine), params: { ticket: { title: 'Cross tenant', contact_id: theirs[:contact].id } },
                               headers: auth(mine)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'history' do
    it "answers 404 for history on the other account's case" do
      get support_path(mine, "/#{theirs[:ticket].id}/events"), headers: auth(mine)

      expect(response).to have_http_status(:not_found)
    end

    it "will not write a note onto the other account's case" do
      post support_path(mine, "/#{theirs[:ticket].id}/events"),
           params: { event: { body: 'leaked' } }, headers: auth(mine)

      expect(response).to have_http_status(:not_found)
      expect(theirs[:ticket].events.where(body: 'leaked')).to be_empty
    end

    it "returns only the caller's own history" do
      get support_path(mine, "/#{mine[:ticket].id}/events"), headers: auth(mine)

      bodies = response.parsed_body['payload'].pluck('body').compact
      expect(bodies).to eq(['p9-mine private note'])
    end
  end

  describe 'SLA policies' do
    def policy_path(tenant, suffix = '') = "/api/v1/accounts/#{tenant[:account].id}/support/sla_policies#{suffix}"

    it "lists only the caller's own policies" do
      get policy_path(mine), headers: auth(mine)

      expect(response.parsed_body['payload'].pluck('name')).to eq(['p9-mine standard'])
    end

    it "answers 404 for the other account's policy" do
      get policy_path(mine, "/#{theirs[:policy].id}"), headers: auth(mine)

      expect(response).to have_http_status(:not_found)
    end

    it "will not update the other account's policy" do
      patch policy_path(mine, "/#{theirs[:policy].id}"), params: { sla_policy: { name: 'hijacked' } },
                                                         headers: auth(mine)

      expect(response).to have_http_status(:not_found)
      expect(theirs[:policy].reload.name).to eq('p9-theirs standard')
    end

    it "will not destroy the other account's policy" do
      delete policy_path(mine, "/#{theirs[:policy].id}"), headers: auth(mine)

      expect(response).to have_http_status(:not_found)
      expect(theirs[:policy].reload).to be_present
    end
  end

  describe 'case analytics' do
    it "counts only the caller's own cases" do
      get "/api/v1/accounts/#{mine[:account].id}/analytics/tickets", params: range, headers: auth(mine)

      expect(response).to have_http_status(:success)
      counts = response.parsed_body['kpis']
                       .select { |kpi| kpi['unit'] == 'count' }
                       .pluck('value').compact
      expect(counts).to all(be <= 1)
      expect(counts).to include(1), 'the fixture produced no counted rows, so the assertion above proves nothing'
    end

    it 'refuses an administrator of the other account' do
      get "/api/v1/accounts/#{mine[:account].id}/analytics/tickets", params: range, headers: auth(theirs)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'the contact activity timeline' do
    it "returns only the caller's own case history" do
      get "/api/v1/accounts/#{mine[:account].id}/contacts/#{mine[:contact].id}/activity",
          params: { limit: 100, category: 'tickets' }, headers: auth(mine)

      expect(response).to have_http_status(:success)
      summaries = response.parsed_body['payload'].pluck('summary').compact.uniq
      expect(summaries).to eq(['p9-mine case'])
    end

    it 'never carries a note body into the timeline' do
      get "/api/v1/accounts/#{mine[:account].id}/contacts/#{mine[:contact].id}/activity",
          params: { limit: 100, category: 'tickets' }, headers: auth(mine)

      expect(response.body).not_to include('private note')
    end
  end

  describe 'the ownership rule for an agent without support_ticket_manage' do
    it "shows an agent only the cases that are theirs, their team's, or that they opened" do
      others = create(:support_ticket, account: mine[:account], title: 'not mine')

      get support_path(mine), headers: auth(mine, :agent)

      expect(response.parsed_body['payload'].pluck('title')).to eq(['p9-mine case'])
      expect(Support::Ticket.where(id: others.id)).to be_present
    end

    it 'answers 404 for a case in the same account the agent has no claim on' do
      others = create(:support_ticket, account: mine[:account], title: 'not mine')

      get support_path(mine, "/#{others.id}"), headers: auth(mine, :agent)

      expect(response).to have_http_status(:not_found)
    end
  end
end
