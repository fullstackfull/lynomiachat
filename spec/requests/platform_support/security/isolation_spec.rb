require 'rails_helper'

# CROSS-ACCOUNT IDOR ON EVERY MEMBER ROUTE, and the role narrowing D-1 defines.
#
# Every tenant lookup in this module goes through `PlatformSupport::TicketPolicy::Scope`, which supplies the
# account predicate ITSELF rather than depending on a caller to remember one. So a foreign or invisible id is
# `ActiveRecord::RecordNotFound`, rendered as 404 -- never a 403, which would confirm the row exists. The
# reference lookup needs the same proof separately, because `LYN-` numbers are GLOBAL: `find_by!` on the bare
# column would reach any account's ticket, and only resolving it inside the already-scoped relation stops that.
RSpec.describe 'Platform Support tenant isolation', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:reporter) { create(:user, account: account, role: :agent) }
  let(:bystander) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }

  let(:ticket) { create(:platform_support_ticket, account: account, reporter: reporter) }
  let(:foreign_ticket) { create(:platform_support_ticket, account: other_account) }

  def base(for_account = account)
    "/api/v1/accounts/#{for_account.id}/platform_support"
  end

  # Every member route the contract defines, so a route added later without a proof is visible as an omission.
  def member_requests(ticket_id, for_account: account)
    [
      [:get, "#{base(for_account)}/tickets/#{ticket_id}"],
      [:get, "#{base(for_account)}/tickets/#{ticket_id}/messages"],
      [:post, "#{base(for_account)}/tickets/#{ticket_id}/messages"],
      [:get, "#{base(for_account)}/tickets/#{ticket_id}/events"],
      [:post, "#{base(for_account)}/tickets/#{ticket_id}/mark_viewed"]
    ]
  end

  def send_as(user, verb, path)
    public_send(verb, path, headers: user.create_new_auth_token, params: { message: { body: 'A reply' } },
                            as: :json)
  end

  describe 'an id belonging to another account' do
    it '404s on every member route, through the asking account path' do
      member_requests(foreign_ticket.id, for_account: other_account).each do |verb, path|
        send_as(other_administrator, verb, path)
        expect(response).to have_http_status(:success), "#{verb} #{path} should be the owner's own ticket"
      end

      member_requests(foreign_ticket.id).each do |verb, path|
        send_as(administrator, verb, path)
        expect(response).to have_http_status(:not_found), "#{verb} #{path} leaked another account's ticket"
      end
    end

    it 'writes no message onto a ticket of another account' do
      expect { send_as(administrator, :post, "#{base}/tickets/#{foreign_ticket.id}/messages") }
        .not_to change(PlatformSupport::Message, :count)
    end

    # The global LYN- series, resolved inside the scope rather than off the bare column.
    it '404s on another account reference number' do
      send_as(administrator, :get, "#{base}/tickets/#{foreign_ticket.reference}")

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(foreign_ticket.subject)
    end

    it 'still resolves the reference of the caller own ticket' do
      send_as(reporter, :get, "#{base}/tickets/#{ticket.reference}")

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['reference']).to eq(ticket.reference)
    end
  end

  describe '404, never 403' do
    it 'answers identically for a nonexistent id and another account id' do
      answers = [0, foreign_ticket.id].map do |id|
        send_as(administrator, :get, "#{base}/tickets/#{id}")
        [response.status, response.body]
      end

      expect(answers.uniq.length).to eq(1)
      expect(answers.first.first).to eq(404)
    end

    it 'answers identically for a reference that never existed and one that belongs elsewhere' do
      answers = ['LYN-999999', foreign_ticket.reference].map do |reference|
        send_as(administrator, :get, "#{base}/tickets/#{reference}")
        [response.status, response.body]
      end

      expect(answers.uniq.length).to eq(1)
    end
  end

  describe 'the roles D-1 defines' do
    it 'shows an administrator every ticket of their account' do
      mine = create(:platform_support_ticket, account: account, reporter: reporter)
      theirs = create(:platform_support_ticket, account: account, reporter: bystander)

      send_as(administrator, :get, "#{base}/tickets")

      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(mine.id, theirs.id)
    end

    it 'shows a normal agent only the tickets they reported' do
      mine = create(:platform_support_ticket, account: account, reporter: bystander)
      create(:platform_support_ticket, account: account, reporter: reporter)

      send_as(bystander, :get, "#{base}/tickets")

      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(mine.id)
    end

    # No CustomRole::PERMISSIONS entry governs this module in V1, so a holder is narrowed exactly as an agent.
    it 'treats a custom-role holder exactly as an agent' do
      account.enable_features!('custom_roles')
      account.account_users.find_by(user: bystander)
             .update!(custom_role: create(:custom_role, account: account, permissions: ['conversation_manage']),
                      role: :agent)
      ticket

      send_as(bystander.reload, :get, "#{base}/tickets")

      expect(response.parsed_body['payload']).to be_empty
      expect(CustomRole::PERMISSIONS.grep(/platform_support/)).to be_empty
    end

    it 'resolves a user who is not a member of the account to nothing' do
      ticket

      resolved = PlatformSupport::TicketPolicy::Scope.new(
        { user: other_administrator, account: account, account_user: nil }, PlatformSupport::Ticket.all
      ).resolve

      expect(resolved).to be_empty
    end

    it 'resolves a nil account to nothing' do
      ticket

      resolved = PlatformSupport::TicketPolicy::Scope.new(
        { user: reporter, account: nil, account_user: nil }, PlatformSupport::Ticket.all
      ).resolve

      expect(resolved).to be_empty
    end
  end

  # An orphaned ticket -- subject account deleted, `account_id` NULL, `account_name_at_creation` kept -- must
  # stop being readable by any tenant, because the scope requires a non-nil match.
  it 'makes an orphaned ticket unreadable by every tenant' do
    ticket.update!(account_id: nil)

    send_as(administrator, :get, "#{base}/tickets/#{ticket.id}")

    expect(response).to have_http_status(:not_found)
  end

  # `params[:account_id]` is never read by the module's controllers; `Current.account` comes from the base
  # controller. Asserted by asking for a ticket through an account the caller does not belong to.
  it 'refuses a request routed through an account the caller is not a member of' do
    send_as(reporter, :get, "#{base(other_account)}/tickets")

    expect(response).to have_http_status(:unauthorized)
  end
end
