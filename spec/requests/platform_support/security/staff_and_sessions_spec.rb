require 'rails_helper'

# STAFF AUTHORITY, SESSION ISOLATION AND AUDIT ATTRIBUTION.
#
# One browser can hold BOTH a tenant session (Devise scope `:user`) and a Super Admin session (scope
# `:super_admin`) at once -- Warden keys both into one cookie, and the Super Admin navigation links straight to
# the agent dashboard, which is how an operator acquires both with one click. Three rules follow, and all
# three are asserted here: staff authority is never derived from `Current.user`, tenant authority is never
# derived from `current_super_admin`, and the `audited` macro is never allowed to infer an actor.
RSpec.describe 'Platform Support staff authority and sessions', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:reporter) { create(:user, account: account, role: :agent) }
  let(:super_admin) { create(:super_admin) }
  let(:ticket) { create(:platform_support_ticket, account: account, reporter: reporter) }
  let(:base) { "/api/v1/accounts/#{account.id}/platform_support" }

  describe 'being a Super Admin is not being support staff' do
    it 'gives a Super Admin with no agent row no tenant visibility at all' do
      ticket

      resolved = PlatformSupport::TicketPolicy::Scope.new(
        { user: super_admin, account: account, account_user: nil }, PlatformSupport::Ticket.all
      ).resolve

      expect(PlatformSupport::Agent.where(user_id: super_admin.id)).to be_empty
      expect(resolved).to be_empty
    end

    # The tenant API answers a Super Admin session with nothing: the two code paths share no authorization
    # helper, and `authenticate_user!` is not satisfied by a `:super_admin` principal that is not a member.
    it 'answers the tenant API for a Super Admin who is not a member with 401' do
      get "#{base}/tickets", headers: super_admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'only an agent row can be an assignee' do
    it 'accepts a PlatformSupport::Agent id' do
      agent = PlatformSupport::Agent.create!(user_id: super_admin.id, display_name: super_admin.name)

      expect { ticket.update!(assignee_id: agent.id) }.not_to raise_error
      expect(ticket.reload.assignee).to eq(agent)
    end

    # The foreign key is to `platform_support_agents`, so a User id cannot be written even by a caller that
    # bypasses the application entirely.
    it 'refuses a User id at the database level' do
      # A real user id that is NOT an agent row id. The two tables have separate sequences, so an id that is
      # valid in `users` is almost never valid in `platform_support_agents` -- and the FK is to the latter.
      PlatformSupport::Agent.delete_all
      expect(PlatformSupport::Agent.exists?(reporter.id)).to be(false)

      # Bypassing the application entirely is the point: the refusal must come from the foreign key.
      expect { ticket.update_column(:assignee_id, reporter.id) } # rubocop:disable Rails/SkipsModelValidations
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end

    # No AccountUser membership is ever created for Lynomia staff. Becoming a member of the customer's account
    # is the one thing this product must never do -- it is why `Support::Ticket` could not be reused.
    it 'creates no AccountUser for the staff user' do
      PlatformSupport::Agent.create!(user_id: super_admin.id, display_name: super_admin.name)

      expect(AccountUser.where(user_id: super_admin.id)).to be_empty
      expect(account.reload.users).not_to include(super_admin)
    end
  end

  describe 'co-resident tenant and Super Admin sessions' do
    it 'does not let a tenant session reach another account through a staff principal' do
      other_account = create(:account)
      foreign = create(:platform_support_ticket, account: other_account)
      PlatformSupport::Agent.create!(user_id: super_admin.id, display_name: super_admin.name)

      get "#{base}/tickets/#{foreign.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    # The tenant API never answers staff-only data: the serializer emits no assignee, no SLA object and no plan
    # snapshot, whoever is asking.
    it 'emits no staff-only field on the tenant payload' do
      agent = PlatformSupport::Agent.create!(user_id: super_admin.id, display_name: 'Zaphod Beeblebrox')
      ticket.update!(assignee: agent, plan_name_at_creation: 'INTERNAL-PLAN-NAME',
                     subscription_status_at_creation: 'past_due', first_response_due_at: 1.hour.from_now)

      get "#{base}/tickets/#{ticket.id}", headers: administrator.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body.keys).not_to include('assignee_id', 'assignee_name', 'sla', 'first_response_due_at',
                                       'plan_name_at_creation', 'subscription_status_at_creation')
      expect(response.body).not_to include('Zaphod Beeblebrox', 'INTERNAL-PLAN-NAME')
    end
  end

  describe 'audit attribution' do
    # The `audited` macro resolves its actor through Devise's `:user` scope while a Super Admin authenticates
    # under `:super_admin`, so declaring it here would file operator activity under nobody -- or, with a
    # co-resident session, under the tenant principal. Explicit writes only.
    it 'declares the audited macro on no platform_support model' do
      models = [PlatformSupport::Ticket, PlatformSupport::Message, PlatformSupport::InternalNote,
                PlatformSupport::Event, PlatformSupport::Agent, PlatformSupport::SlaPolicy]

      models.each do |model|
        expect(model.respond_to?(:audited_options)).to be(false), "#{model} declares `audited`"
      end
    end

    it 'names the real Super Admin as the actor on an explicit write' do
      row = Custom::AuditLog.create!(
        auditable: ticket, user: super_admin, action: 'update', comment: 'platform_support.status_changed',
        audited_changes: { 'status' => %w[open in_progress], 'reference' => ticket.reference }
      )

      expect(row.user).to eq(super_admin)
      expect(row.username).to eq(super_admin.name)
    end

    # `associated` deliberately absent, which files the row installation-wide. `Custom::AuditLog.for_account`
    # serves account-associated rows to that account's own administrators, so associating it would publish
    # Lynomia's operator activity onto the customer's Audit Logs page.
    it 'keeps the row off the customer audit page' do
      account.enable_features!('audit_logs')
      Custom::AuditLog.delete_all
      row = Custom::AuditLog.create!(
        auditable: ticket, user: super_admin, action: 'update', comment: 'platform_support.status_changed',
        audited_changes: { 'status' => %w[open in_progress] }
      )

      get "/api/v1/accounts/#{account.id}/audit_logs", headers: administrator.create_new_auth_token, as: :json

      expect(row.associated).to be_nil
      expect(Custom::AuditLog.for_account(account)).not_to include(row)
      expect(response.body).not_to include('platform_support.status_changed')
    end

    it 'scrubs a credential out of audited_changes whatever the writer passed' do
      row = Custom::AuditLog.create!(
        auditable: ticket, user: super_admin, action: 'update', comment: 'platform_support.assigned',
        audited_changes: { 'api_key' => 'sk_live_should_never_land', 'assignee_id' => [nil, 7] }
      )

      expect(row.reload.audited_changes).not_to have_key('api_key')
      expect(row.audited_changes['assignee_id']).to eq([nil, 7])
    end
  end
end
