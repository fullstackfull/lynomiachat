require 'rails_helper'

# The §10 isolation, commercial and lifecycle proofs, taken against the real request stack rather than against
# the policy object, because what matters is what the HTTP boundary answers.
RSpec.describe 'Platform Support tenant API isolation', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:second_agent) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }
  let(:custom_role) { create(:custom_role, account: account) }
  let(:custom_role_holder) do
    user = create(:user, account: account, role: :agent)
    AccountUser.find_by(account_id: account.id, user_id: user.id).update!(custom_role: custom_role)
    user
  end

  let(:base) { "/api/v1/accounts/#{account.id}/platform_support" }

  def open_ticket(reporter, in_account: account)
    PlatformSupport::TicketCreation.new(
      account: in_account, reporter: reporter,
      attributes: { category: 'bug', subject: "Raised by #{reporter.id}", description: 'Details' }
    ).perform
  end

  describe 'cross-account isolation' do
    let(:theirs) { open_ticket(other_administrator, in_account: other_account) }

    # Every member route, one at a time: the policy scope is the only thing between a guessed id and another
    # account's complaint.
    it 'answers 404 on every member route for a ticket belonging to another account' do
      requests = [
        [:get, "#{base}/tickets/#{theirs.id}"],
        [:patch, "#{base}/tickets/#{theirs.id}"],
        [:get, "#{base}/tickets/#{theirs.id}/messages"],
        [:post, "#{base}/tickets/#{theirs.id}/messages"],
        [:get, "#{base}/tickets/#{theirs.id}/events"],
        [:post, "#{base}/tickets/#{theirs.id}/mark_viewed"]
      ]

      requests.each do |verb, path|
        public_send(verb, path, params: { ticket: { priority: 'low' }, message: { body: 'Hello' } },
                                headers: administrator.create_new_auth_token)
        expect(response).to have_http_status(:not_found), "#{verb.upcase} #{path} answered #{response.status}"
      end
    end

    it 'answers 404 and not 403, so the existence of another account\'s ticket is never confirmed' do
      get "#{base}/tickets/#{theirs.id}", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('Resource could not be found')
    end

    it 'cannot be walked by reference either, although the LYN- series is global' do
      get "#{base}/tickets/#{theirs.reference}", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'lists nothing of another account' do
      mine = open_ticket(administrator)
      theirs

      get "#{base}/tickets", headers: administrator.create_new_auth_token

      expect(response.parsed_body['payload'].map { |ticket| ticket['id'] }).to eq([mine.id])
      expect(response.parsed_body['meta']['total_entries']).to eq(1)
    end

    it 'refuses an administrator of another account on this account at the account guard' do
      get "#{base}/tickets", headers: other_administrator.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'D-1 inside one account' do
    it 'shows an administrator every ticket of their account' do
      first = open_ticket(administrator)
      second = open_ticket(agent)

      get "#{base}/tickets", headers: administrator.create_new_auth_token

      expect(response.parsed_body['payload'].map { |ticket| ticket['id'] }).to contain_exactly(first.id, second.id)
    end

    it 'shows an agent only their own and 404s another member\'s' do
      mine = open_ticket(agent)
      theirs = open_ticket(second_agent)

      get "#{base}/tickets", headers: agent.create_new_auth_token
      expect(response.parsed_body['payload'].map { |ticket| ticket['id'] }).to eq([mine.id])

      get "#{base}/tickets/#{theirs.id}", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'treats a custom-role holder exactly as an agent' do
      mine = open_ticket(custom_role_holder)
      theirs = open_ticket(administrator)

      get "#{base}/tickets", headers: custom_role_holder.create_new_auth_token
      expect(response.parsed_body['payload'].map { |ticket| ticket['id'] }).to eq([mine.id])

      get "#{base}/tickets/#{theirs.id}", headers: custom_role_holder.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'still lets an agent open a ticket and read it back' do
      post "#{base}/tickets", params: { ticket: { category: 'bug', subject: 'Mine', description: 'Details' } },
                              headers: agent.create_new_auth_token

      expect(response).to have_http_status(:created)
      get "#{base}/tickets/#{response.parsed_body['payload']['id']}", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:success)
    end
  end

  describe 'the commercial rules' do
    # A customer whose plan lapsed must still be able to complain -- usually about the billing itself.
    it 'serves a billing-locked account, which every other account-scoped endpoint refuses' do
      # Enforcement is not a flag: `Billing::Settings.enforced?` is true once Stripe keys or a trial plan
      # exist, and `BILLING_TRIAL_ENABLED` already defaults to true. A cancelled subscription is therefore
      # all this setup needs -- a config row named BILLING_ENFORCED would be read by nothing.
      create(:billing_subscription, account: account, status: 'canceled')

      get "/api/v1/accounts/#{account.id}/conversations", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:payment_required)

      get "#{base}/tickets", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:success)

      post "#{base}/tickets", params: { ticket: { category: 'billing', subject: 'Locked out',
                                                  description: 'I cannot use the product' } },
                              headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:created)
    end

    # No exemption, ever: a spam or security suspension must never gain an automatic bypass into Lynomia's own
    # staff inbox, and the guard that does this is not edited by this module.
    it 'refuses an administratively suspended account with the existing 401' do
      account.update!(status: :suspended)

      get "#{base}/tickets", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('Account is suspended')
    end
  end

  describe 'account deletion' do
    it 'orphans the ticket, keeps the snapshot and makes it unreadable by the tenant' do
      ticket = open_ticket(administrator)
      account_id = account.id
      account_name = account.name
      Account.where(id: account_id).delete_all

      expect(ticket.reload).to have_attributes(account_id: nil, account_name_at_creation: account_name)
      expect(ticket.messages.count).to eq(1)

      get "/api/v1/accounts/#{account_id}/platform_support/tickets/#{ticket.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'keeps the staff history and the audit trail, which carry no foreign key to the account' do
      ticket = open_ticket(administrator)
      staff = PlatformSupport::Agent.create!(user: create(:super_admin))
      PlatformSupport::NoteCreation.new(ticket: ticket, agent: staff, body: 'Internal').perform
      Account.where(id: account.id).delete_all

      expect(ticket.reload.internal_notes.count).to eq(1)
      expect(Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket').count).to eq(1)
    end
  end

  describe 'the audit trail a tenant administrator can read' do
    it 'never contains a Platform Support row, because none carries an account association' do
      ticket = open_ticket(administrator)
      staff = PlatformSupport::Agent.create!(user: create(:super_admin))
      PlatformSupport::MessageCreation.new(ticket: ticket, author: staff, body: 'Looking into it').perform
      PlatformSupport::NoteCreation.new(ticket: ticket, agent: staff, body: 'Internal').perform

      expect(Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket').count).to eq(2)
      expect(Custom::AuditLog.for_account(account).where(auditable_type: 'PlatformSupport::Ticket')).to be_empty
    end
  end
end
