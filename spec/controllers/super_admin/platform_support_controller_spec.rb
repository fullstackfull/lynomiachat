require 'rails_helper'

# The Super Admin Platform Support Desk.
#
# ---------------------------------------------------------------------------------------------------------
# PARALLEL-DEVELOPMENT SCAFFOLD. Read this before anything else in this file.
#
# This branch owns the surfaces, not the domain: the migrations, the models and the route drawer belong to the
# backend branch and do not exist here yet. So that these examples exercise the REAL controller against the
# REAL schema contract rather than a pile of doubles, this file builds three things at load time, each guarded
# so that it steps aside the moment the real one lands:
#
#   PLATFORM_SUPPORT_SCHEMA_STUB  the five tables, exactly as §1 of
#                                 docs/platform-support/12-refresh-against-product-refinement.md declares them,
#                                 created with `if_not_exists` so the real migration wins.
#   PLATFORM_SUPPORT_MODEL_STUB   the five models, with only the enums, associations, constants and `#reference`
#                                 this surface reads. Defined only when the constant does not already resolve.
#   PLATFORM_SUPPORT_ROUTE_STUB   the staff half of the route drawer, verbatim what §2 freezes, drawn only when
#                                 `super_admin_platform_support_path` does not already exist.
#
# ALL THREE MUST BE DELETED AT INTEGRATION. They are listed in this branch's report for exactly that reason.
# ---------------------------------------------------------------------------------------------------------

PLATFORM_SUPPORT_SCHEMA_STUB = lambda do
  connection = ActiveRecord::Base.connection

  connection.create_table :platform_support_agents, if_not_exists: true do |t|
    t.bigint :user_id, null: false
    t.integer :role, null: false, default: 0
    t.boolean :active, null: false, default: true
    t.string :display_name, null: false
    t.timestamps
  end

  connection.create_table :platform_support_tickets, if_not_exists: true do |t|
    t.integer :reference_number, null: false
    t.bigint :account_id
    t.string :account_name_at_creation, null: false
    t.bigint :reporter_id
    t.string :reporter_name, null: false
    t.string :category, null: false, default: 'other'
    t.string :subject, null: false
    t.text :description
    t.integer :status, null: false, default: 0
    t.integer :priority, null: false, default: 1
    t.bigint :assignee_id
    t.bigint :sla_policy_id
    t.bigint :plan_id_at_creation
    t.string :plan_name_at_creation
    t.string :subscription_status_at_creation
    t.datetime :first_response_due_at
    t.datetime :resolution_due_at
    t.datetime :first_responded_at
    t.datetime :first_response_breached_at
    t.datetime :resolution_breached_at
    t.datetime :sla_paused_at
    t.integer :sla_paused_seconds, null: false, default: 0
    t.datetime :last_customer_message_at
    t.datetime :last_operator_message_at
    t.datetime :customer_last_viewed_at
    t.datetime :last_activity_at, null: false
    t.datetime :resolved_at
    t.datetime :closed_at
    t.timestamps
  end

  connection.create_table :platform_support_messages, if_not_exists: true do |t|
    t.bigint :platform_support_ticket_id, null: false
    t.string :author_type, null: false
    t.bigint :author_id
    t.string :author_name, null: false
    t.text :body, null: false
    t.timestamps
  end

  connection.create_table :platform_support_internal_notes, if_not_exists: true do |t|
    t.bigint :platform_support_ticket_id, null: false
    t.bigint :agent_id, null: false
    t.string :author_name, null: false
    t.text :body, null: false
    t.timestamps
  end

  connection.create_table :platform_support_events, if_not_exists: true do |t|
    t.bigint :platform_support_ticket_id, null: false
    t.string :event_type, null: false
    t.string :actor_type
    t.bigint :actor_id
    t.string :actor_name
    t.jsonb :metadata, null: false, default: {}
    t.datetime :created_at, null: false
  end
end

# `const_set` plus anonymous classes rather than `class PlatformSupport::Ticket`: a constant declared with the
# keyword inside this file would be a second, competing declaration of a name the backend branch owns, and the
# linter is right to say so. Declared this way, these five exist only while the real ones do not.
PLATFORM_SUPPORT_MODEL_STUB = lambda do
  Object.const_set(:PlatformSupport, Module.new) unless Object.const_defined?(:PlatformSupport)

  PlatformSupport.const_set(:Agent, Class.new(ApplicationRecord) do
    self.table_name = 'platform_support_agents'

    enum :role, { agent: 0, lead: 1 }

    belongs_to :user
  end)

  PlatformSupport.const_set(:Message, Class.new(ApplicationRecord) do
    self.table_name = 'platform_support_messages'

    has_many_attached :platform_support_message_files
  end)

  PlatformSupport.const_set(:InternalNote, Class.new(ApplicationRecord) do
    self.table_name = 'platform_support_internal_notes'

    has_many_attached :platform_support_note_files
  end)

  PlatformSupport.const_set(:Event, Class.new(ApplicationRecord) do
    self.table_name = 'platform_support_events'
  end)

  PlatformSupport.const_set(:Ticket, Class.new(ApplicationRecord) do
    self.table_name = 'platform_support_tickets'

    const_set(:CATEGORIES, %w[billing account_access channel_connection whatsapp commerce campaigns automation
                              performance data_export bug other].freeze)
    const_set(:OPEN_STATUSES, %w[open in_progress waiting_on_customer waiting_on_lynomia].freeze)
    const_set(:CLOSED_STATUSES, %w[resolved closed].freeze)

    enum :status, { open: 0, in_progress: 1, waiting_on_customer: 2, waiting_on_lynomia: 3, resolved: 4, closed: 5 }
    enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }

    belongs_to :account, optional: true
    belongs_to :assignee, class_name: 'PlatformSupport::Agent', optional: true
    has_many :messages, class_name: 'PlatformSupport::Message', foreign_key: :platform_support_ticket_id,
                        inverse_of: false, dependent: :destroy
    has_many :internal_notes, class_name: 'PlatformSupport::InternalNote', foreign_key: :platform_support_ticket_id,
                              inverse_of: false, dependent: :destroy
    has_many :events, class_name: 'PlatformSupport::Event', foreign_key: :platform_support_ticket_id,
                      inverse_of: false, dependent: :destroy

    define_method(:reference) { format('LYN-%<number>06d', number: reference_number) }
  end)
end

PLATFORM_SUPPORT_ROUTE_STUB = lambda do
  Rails.application.routes.disable_clear_and_finalize = true
  Rails.application.routes.draw do
    namespace :super_admin do
      resource :platform_support, only: [:show], controller: 'platform_support' do
        collection do
          get 'tickets/:id', action: :ticket, as: :ticket
          get 'attachments/:id', action: :attachment, as: :attachment
          post 'tickets/:id/reply', action: :reply, as: :reply, controller: 'platform_support_actions'
          post 'tickets/:id/note', action: :note, as: :note, controller: 'platform_support_actions'
          patch 'tickets/:id/status', action: :status, as: :status, controller: 'platform_support_actions'
          patch 'tickets/:id/triage', action: :triage, as: :triage, controller: 'platform_support_actions'
          post 'tickets/:id/assign', action: :assign, as: :assign, controller: 'platform_support_actions'
        end
      end
    end
  end
  Rails.application.routes.disable_clear_and_finalize = false
end

PLATFORM_SUPPORT_SCHEMA_STUB.call
PLATFORM_SUPPORT_MODEL_STUB.call unless defined?(PlatformSupport::Ticket)
PLATFORM_SUPPORT_ROUTE_STUB.call unless Rails.application.routes.url_helpers.respond_to?(:super_admin_platform_support_path)

RSpec.describe 'Super Admin Platform Support Desk', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account, name: 'Alnoor Trading') }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:tenant_agent) { create(:user, account: account, role: :agent) }

  let(:staff_user) { create(:super_admin, email: 'desk@lynomia.test') }
  let(:agent) do
    PlatformSupport::Agent.create!(user_id: super_admin.id, role: :agent, display_name: 'Hana')
  end
  let(:lead) do
    PlatformSupport::Agent.create!(user_id: staff_user.id, role: :lead, display_name: 'Faisal')
  end

  let(:reference_sequence) { PlatformSupport::Ticket.maximum(:reference_number).to_i }

  def ticket(**attributes)
    defaults = {
      reference_number: reference_sequence + 1,
      account: account,
      account_name_at_creation: account.name,
      reporter_id: administrator.id,
      reporter_name: administrator.available_name,
      category: 'billing',
      subject: 'Invoices are not arriving',
      description: 'Nothing since Tuesday.',
      priority: :high,
      last_activity_at: 2.hours.ago
    }
    PlatformSupport::Ticket.create!(defaults.merge(attributes))
  end

  describe 'the Super Admin boundary' do
    it 'redirects an unauthenticated caller away from the queue and the detail' do
      target = ticket

      ['/super_admin/platform_support', "/super_admin/platform_support/tickets/#{target.id}"].each do |path|
        get path
        expect(response).to have_http_status(:redirect)
      end
    end

    # The decisive check: a tenant user is not an operator, whatever their role inside their own account.
    it 'does not let a tenant administrator or a tenant agent in' do
      [administrator, tenant_agent].each do |user|
        sign_in(user, scope: :user)
        get '/super_admin/platform_support'
        expect(response).to have_http_status(:redirect)
        expect(response.body).not_to include('Customer support')
        sign_out(user)
      end
    end

    it 'refuses every mutation to an unauthenticated caller' do
      target = ticket

      post "/super_admin/platform_support/tickets/#{target.id}/reply", params: { body: 'hello' }

      expect(response).to have_http_status(:redirect)
      expect(target.reload.messages.count).to eq(0)
    end
  end

  # The one layer Operations does not have. Being a Super Admin is not being support staff.
  describe 'the acting-agent layer' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'refuses a Super Admin who has no agent row' do
      get '/super_admin/platform_support'

      expect(response).to redirect_to('/super_admin')
      expect(flash[:alert]).to include('not an active Lynomia support agent')
    end

    it 'refuses a Super Admin whose agent row is inactive' do
      PlatformSupport::Agent.create!(user_id: super_admin.id, role: :agent, display_name: 'Hana', active: false)

      get '/super_admin/platform_support'

      expect(response).to redirect_to('/super_admin')
    end

    it 'refuses a mutation from a Super Admin with no agent row, and writes nothing' do
      target = ticket

      post "/super_admin/platform_support/tickets/#{target.id}/reply", params: { body: 'hello' }

      expect(response).to redirect_to('/super_admin')
      expect(PlatformSupport::Message.count).to eq(0)
      expect(Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket').count).to eq(0)
    end

    it 'admits a Super Admin with an active agent row' do
      agent

      get '/super_admin/platform_support'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Customer support')
    end
  end

  describe 'the queue' do
    before do
      agent
      sign_in(super_admin, scope: :super_admin)
    end

    it 'shows the reference, the account, the plan snapshot and the state of each ticket' do
      ticket(plan_name_at_creation: 'Growth')

      get '/super_admin/platform_support'

      expect(response.body).to include('LYN-000001')
      expect(response.body).to include('Invoices are not arriving')
      expect(response.body).to include('Alnoor Trading')
      expect(response.body).to include('Growth')
      expect(response.body).to include('Unassigned')
    end

    it 'orders by status, then priority worst first, then the stalest activity' do
      ticket(subject: 'Open and urgent', priority: :urgent, last_activity_at: 1.hour.ago)
      ticket(subject: 'Open and low', priority: :low, last_activity_at: 1.minute.ago)
      ticket(subject: 'Already resolved', status: :resolved, priority: :urgent, last_activity_at: 1.minute.ago)

      get '/super_admin/platform_support'

      body = response.body
      expect(body.index('Open and urgent')).to be < body.index('Open and low')
      expect(body.index('Open and low')).to be < body.index('Already resolved')
    end

    it 'filters by status, priority, category, assignee and account' do
      wanted = ticket(subject: 'The one', category: 'whatsapp', priority: :urgent, assignee: agent)
      ticket(subject: 'Not this one', category: 'billing', priority: :low)

      get '/super_admin/platform_support', params: { status: 'open', priority: 'urgent', category: 'whatsapp',
                                                     assignee_id: agent.id, account_id: account.id }

      expect(response.body).to include(wanted.subject)
      expect(response.body).not_to include('Not this one')
    end

    it 'finds the unassigned ones through a literal, because a NULL cannot be a query string' do
      ticket(subject: 'Nobody owns this')
      ticket(subject: 'Hana owns this', assignee: agent)

      get '/super_admin/platform_support', params: { assignee_id: 'unassigned' }

      expect(response.body).to include('Nobody owns this')
      expect(response.body).not_to include('Hana owns this')
    end

    # The recorded reason: an operator pasting a reference out of an email should not have to strip it.
    it 'searches by reference with or without the LYN- prefix, by subject and by account name' do
      target = ticket(subject: 'Templates stuck')

      %w[LYN-000001 1 Templates Alnoor].each do |term|
        get '/super_admin/platform_support', params: { q: term }
        expect(response.body).to include(target.subject), "searching #{term.inspect} did not find the ticket"
      end
    end

    it 'drops a filter value outside its allow-list rather than querying it' do
      target = ticket

      get '/super_admin/platform_support', params: { status: 'not_a_status', category: 'not_a_category' }

      expect(response.body).to include(target.subject)
    end

    it 'says nothing has been raised yet, and separately that filters are too narrow' do
      get '/super_admin/platform_support'
      expect(response.body).to include('No customer has raised a ticket with Lynomia yet')

      ticket
      get '/super_admin/platform_support', params: { q: 'nothing matches this' }
      expect(response.body).to include('Clear them to see the whole desk')
    end

    it 'paginates for real' do
      (SuperAdmin::PlatformSupportController::PER_PAGE + 1).times do |index|
        ticket(subject: "Ticket number #{index}", reference_number: 500 + index)
      end

      get '/super_admin/platform_support'
      expect(response.body).to include('Page 1 of 2')

      get '/super_admin/platform_support', params: { page: 2 }
      expect(response).to have_http_status(:success)
    end

    it 'marks a ticket whose last word was the customer\'s' do
      ticket(last_customer_message_at: 10.minutes.ago, last_operator_message_at: 2.hours.ago)

      get '/super_admin/platform_support'

      expect(response.body).to include('customer replied last')
    end

    it 'keeps a deactivated agent\'s tickets assigned and asks for a reassignment' do
      stale = PlatformSupport::Agent.create!(user_id: administrator.id, display_name: 'Departed', active: false)
      ticket(assignee: stale)

      get '/super_admin/platform_support'

      expect(response.body).to include('Departed')
      expect(response.body).to include('reassign needed')
    end
  end

  describe 'the ticket detail' do
    let(:target) { ticket(sla_policy_id: 7, resolution_due_at: 3.hours.from_now, plan_name_at_creation: 'Starter') }

    before do
      agent
      sign_in(super_admin, scope: :super_admin)
    end

    it 'redirects with an alert for a ticket that no longer exists, rather than raising' do
      get '/super_admin/platform_support/tickets/0'

      expect(response).to redirect_to('/super_admin/platform_support')
      expect(flash[:alert]).to include('no longer exists')
    end

    it 'renders the public thread, the internal notes and the events in one chronological list' do
      target.messages.create!(author_type: 'User', author_id: administrator.id, author_name: 'Dana',
                              body: 'Still nothing today.', created_at: 3.hours.ago)
      target.messages.create!(author_type: 'PlatformSupport::Agent', author_id: agent.id, author_name: 'Hana',
                              body: 'Looking at the billing export now.', created_at: 2.hours.ago)
      target.internal_notes.create!(agent_id: agent.id, author_name: 'Hana',
                                    body: 'Their card expired; finance is checking.', created_at: 1.hour.ago)
      target.events.create!(event_type: 'created', actor_type: 'User', actor_name: 'Dana', created_at: 4.hours.ago)

      get "/super_admin/platform_support/tickets/#{target.id}"

      body = response.body
      expect(body).to include('Still nothing today.')
      expect(body).to include('Looking at the billing export now.')
      expect(body).to include('Their card expired; finance is checking.')
      expect(body).to include('Internal note')
      expect(body.index('Still nothing today.')).to be < body.index('Looking at the billing export now.')
      expect(body.index('Looking at the billing export now.')).to be < body.index('Their card expired')
    end

    it 'shows the operator\'s own name on a reply, which the customer\'s view never does' do
      target.messages.create!(author_type: 'PlatformSupport::Agent', author_id: agent.id, author_name: 'Hana',
                              body: 'On it.')

      get "/super_admin/platform_support/tickets/#{target.id}"

      expect(response.body).to include('Hana (Lynomia)')
    end

    it 'offers two visibly distinct compose boxes with different submit labels' do
      get "/super_admin/platform_support/tickets/#{target.id}"

      expect(response.body).to include('Send reply to customer')
      expect(response.body).to include('Save internal note')
      expect(response.body).to include('The customer never sees this')
    end

    it 'pins the reference and the account name in the reply box, not only in the header' do
      get "/super_admin/platform_support/tickets/#{target.id}"

      expect(response.body.scan('LYN-000001').length).to be >= 2
      expect(response.body.scan('Alnoor Trading').length).to be >= 2
    end

    it 'renders the account and billing context, and both plans when they differ' do
      get "/super_admin/platform_support/tickets/#{target.id}"

      expect(response.body).to include('Account')
      expect(response.body).to include('Billing')
      expect(response.body).to include('At creation: Starter')
    end

    it 'links to Operations Account 360 and to the account\'s other tickets' do
      get "/super_admin/platform_support/tickets/#{target.id}"

      expect(response.body).to include("/super_admin/operations/account?id=#{account.id}")
      expect(response.body).to include("/super_admin/platform_support?account_id=#{account.id}")
    end

    it 'labels the SLA as calendar time, and says so plainly when no policy applies' do
      get "/super_admin/platform_support/tickets/#{target.id}"
      expect(response.body).to include('Calendar time, not business hours')

      bare = ticket(reference_number: 900, subject: 'No policy here')
      get "/super_admin/platform_support/tickets/#{bare.id}"
      expect(response.body).to include('No SLA policy applies')
      expect(response.body).not_to include('Calendar time, not business hours')
    end

    it 'keeps a breach visible after the ticket was resolved' do
      breached = ticket(reference_number: 901, status: :resolved, resolved_at: 1.hour.ago,
                        sla_policy_id: 7, resolution_breached_at: 2.hours.ago)

      get "/super_admin/platform_support/tickets/#{breached.id}"

      expect(response.body).to include('breached')
    end

    it 'says the account is gone rather than linking nowhere' do
      orphan = ticket(reference_number: 902, account: nil, account_name_at_creation: 'Deleted Co')

      get "/super_admin/platform_support/tickets/#{orphan.id}"

      expect(response.body).to include('Deleted Co')
      expect(response.body).to include('This account was deleted')
    end
  end

  describe 'a public reply' do
    let(:target) { ticket }

    before do
      agent
      sign_in(super_admin, scope: :super_admin)
    end

    it 'writes the message, moves the operator clock, and audits installation-wide' do
      post "/super_admin/platform_support/tickets/#{target.id}/reply", params: { body: '  Fixed the export.  ' }

      message = target.reload.messages.sole
      expect(message.body).to eq('Fixed the export.')
      expect(message.author_type).to eq('PlatformSupport::Agent')
      expect(message.author_name).to eq('Hana')
      expect(target.last_operator_message_at).to be_present
      expect(target.events.pluck(:event_type)).to eq(['operator_replied'])

      entry = Custom::AuditLog.find_by(comment: 'platform_support.operator_replied')
      expect(entry.user_id).to eq(super_admin.id)
      expect(entry.associated_id).to be_nil
    end

    it 'puts no body, payload or credential in the audit row' do
      post "/super_admin/platform_support/tickets/#{target.id}/reply", params: { body: 'secret-token-abc123' }

      entry = Custom::AuditLog.find_by(comment: 'platform_support.operator_replied')
      expect(entry.audited_changes.to_json).not_to include('secret-token-abc123')
      expect(entry.audited_changes.keys).to contain_exactly('ticket_id', 'reference', 'subject_account_id',
                                                            'agent_id', 'message_id')
    end

    it 'refuses an empty reply and writes nothing' do
      post "/super_admin/platform_support/tickets/#{target.id}/reply", params: { body: '   ' }

      expect(flash[:alert]).to eq('A reply cannot be empty.')
      expect(target.reload.messages.count).to eq(0)
    end
  end

  describe 'an internal note' do
    let(:target) { ticket(last_operator_message_at: 3.hours.ago) }

    before do
      agent
      sign_in(super_admin, scope: :super_admin)
    end

    # A desk where internal triage looks like a customer reply makes every "customer replied" reading lie.
    it 'writes a note that is not a message and does not move the operator clock' do
      previous = target.last_operator_message_at

      post "/super_admin/platform_support/tickets/#{target.id}/note", params: { body: 'Finance is checking.' }

      expect(target.reload.internal_notes.sole.body).to eq('Finance is checking.')
      expect(target.messages.count).to eq(0)
      expect(target.last_operator_message_at.to_i).to eq(previous.to_i)
    end

    # The event type is outside CUSTOMER_VISIBLE_EVENT_TYPES, so the customer cannot infer that internal
    # discussion happened.
    it 'writes an event the customer-visible allow-list does not contain' do
      customer_visible = %w[created status_changed customer_replied operator_replied resolved reopened closed]

      post "/super_admin/platform_support/tickets/#{target.id}/note", params: { body: 'Finance is checking.' }

      expect(target.reload.events.pluck(:event_type)).to eq(['internal_note_added'])
      expect(customer_visible).not_to include('internal_note_added')
    end

    it 'refuses an empty note' do
      post "/super_admin/platform_support/tickets/#{target.id}/note", params: { body: '' }

      expect(flash[:alert]).to eq('A note cannot be empty.')
      expect(target.reload.internal_notes.count).to eq(0)
    end
  end

  describe 'a status transition' do
    before do
      agent
      sign_in(super_admin, scope: :super_admin)
    end

    it 'moves to any of the six statuses and records which' do
      target = ticket

      patch "/super_admin/platform_support/tickets/#{target.id}/status", params: { status: 'waiting_on_customer' }

      expect(target.reload.status).to eq('waiting_on_customer')
      expect(target.events.sole.metadata).to eq('from' => 'open', 'to' => 'waiting_on_customer')
      expect(Custom::AuditLog.exists?(comment: 'platform_support.status_changed')).to be(true)
    end

    it 'stamps resolved_at on resolve and closed_at on close' do
      target = ticket

      patch "/super_admin/platform_support/tickets/#{target.id}/status", params: { status: 'resolved' }
      expect(target.reload.resolved_at).to be_present
      expect(target.events.pluck(:event_type)).to eq(['resolved'])

      patch "/super_admin/platform_support/tickets/#{target.id}/status", params: { status: 'closed' }
      expect(target.reload.closed_at).to be_present
      expect(target.events.pluck(:event_type)).to eq(%w[resolved closed])
    end

    # A reopened ticket that kept its resolution timestamp would read as resolved to everything that asks.
    it 'records a reopen and clears both terminal timestamps' do
      target = ticket(status: :resolved, resolved_at: 1.hour.ago, closed_at: 30.minutes.ago)

      patch "/super_admin/platform_support/tickets/#{target.id}/status", params: { status: 'open' }

      expect(target.reload.status).to eq('open')
      expect(target.resolved_at).to be_nil
      expect(target.closed_at).to be_nil
      expect(target.events.sole.event_type).to eq('reopened')
    end

    it 'refuses a status outside the six and changes nothing' do
      target = ticket

      patch "/super_admin/platform_support/tickets/#{target.id}/status", params: { status: 'escalated' }

      expect(flash[:alert]).to eq('escalated is not a status.')
      expect(target.reload.status).to eq('open')
      expect(target.events.count).to eq(0)
    end

    it 'writes nothing when the status it was given is the one it already has' do
      target = ticket

      patch "/super_admin/platform_support/tickets/#{target.id}/status", params: { status: 'open' }

      expect(target.reload.events.count).to eq(0)
      expect(Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket').count).to eq(0)
    end
  end

  describe 'triage' do
    before do
      agent
      sign_in(super_admin, scope: :super_admin)
    end

    it 'changes priority and category together, and records one event each' do
      target = ticket

      patch "/super_admin/platform_support/tickets/#{target.id}/triage",
            params: { priority: 'urgent', category: 'whatsapp' }

      expect(target.reload.priority).to eq('urgent')
      expect(target.category).to eq('whatsapp')
      expect(target.events.pluck(:event_type)).to contain_exactly('priority_changed', 'category_changed')
    end

    it 'refuses a value outside either allow-list rather than coercing it' do
      target = ticket

      patch "/super_admin/platform_support/tickets/#{target.id}/triage", params: { category: 'escalations' }
      expect(flash[:alert]).to eq('escalations is not a category.')

      patch "/super_admin/platform_support/tickets/#{target.id}/triage", params: { priority: 'critical' }
      expect(flash[:alert]).to eq('critical is not a priority.')

      expect(target.reload.category).to eq('billing')
      expect(target.priority).to eq('high')
    end
  end

  describe 'assignment' do
    before { agent }

    it 'lets an agent take an unassigned ticket' do
      sign_in(super_admin, scope: :super_admin)
      target = ticket

      post "/super_admin/platform_support/tickets/#{target.id}/assign", params: { assignee_id: agent.id }

      expect(target.reload.assignee_id).to eq(agent.id)
      expect(target.events.sole.event_type).to eq('assigned')
      expect(Custom::AuditLog.exists?(comment: 'platform_support.assigned')).to be(true)
    end

    it 'refuses an agent who tries to reassign another agent\'s ticket' do
      sign_in(super_admin, scope: :super_admin)
      target = ticket(assignee: lead)

      post "/super_admin/platform_support/tickets/#{target.id}/assign", params: { assignee_id: agent.id }

      expect(flash[:alert]).to include('Only a lead may reassign')
      expect(target.reload.assignee_id).to eq(lead.id)
    end

    it 'lets a lead reassign another agent\'s ticket' do
      lead
      sign_in(staff_user, scope: :super_admin)
      target = ticket(assignee: agent)

      post "/super_admin/platform_support/tickets/#{target.id}/assign", params: { assignee_id: lead.id }

      expect(target.reload.assignee_id).to eq(lead.id)
    end

    it 'unassigns explicitly, with its own event' do
      sign_in(super_admin, scope: :super_admin)
      target = ticket(assignee: agent)

      post "/super_admin/platform_support/tickets/#{target.id}/assign", params: { assignee_id: 'unassigned' }

      expect(target.reload.assignee_id).to be_nil
      expect(target.events.sole.event_type).to eq('unassigned')
    end

    # Only an agent ROW may be an assignee. No AccountUser membership is ever created for Lynomia staff.
    it 'refuses a user id that is not an active agent row, and creates no membership' do
      sign_in(super_admin, scope: :super_admin)
      target = ticket
      before_memberships = AccountUser.count

      post "/super_admin/platform_support/tickets/#{target.id}/assign", params: { assignee_id: administrator.id }

      expect(flash[:alert]).to eq('That agent does not exist, or is not active.')
      expect(target.reload.assignee_id).to be_nil
      expect(AccountUser.count).to eq(before_memberships)
    end
  end

  describe 'the staff attachment download' do
    let(:target) { ticket }

    before do
      agent
      sign_in(super_admin, scope: :super_admin)
    end

    def attach(record, association)
      record.public_send(association).attach(
        io: StringIO.new('screenshot bytes'), filename: 'screenshot.png', content_type: 'image/png'
      )
      record.public_send(association).first
    end

    it 'streams a message attachment to an operator with an agent row' do
      message = target.messages.create!(author_type: 'User', author_id: administrator.id, author_name: 'Dana',
                                        body: 'See attached.')
      file = attach(message, :platform_support_message_files)

      get "/super_admin/platform_support/attachments/#{file.id}"

      expect(response).to have_http_status(:success)
    end

    it 'streams an internal note attachment, which the tenant surface never can' do
      note = target.internal_notes.create!(agent_id: agent.id, author_name: 'Hana', body: 'Evidence.')
      file = attach(note, :platform_support_note_files)

      get "/super_admin/platform_support/attachments/#{file.id}"

      expect(response).to have_http_status(:success)
    end

    # The route cannot be turned into a reader for another subsystem's blobs.
    it '404s an attachment that is not a Platform Support one' do
      conversation = create(:conversation, account: account)
      message = create(:message, account: account, conversation: conversation)
      message.attachments.create!(account_id: account.id, file_type: :image)
      foreign = ActiveStorage::Attachment.create!(
        name: 'file', record: message.attachments.first,
        blob: ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x'), filename: 'x.png',
                                                     content_type: 'image/png')
      )

      get "/super_admin/platform_support/attachments/#{foreign.id}"

      expect(response).to have_http_status(:not_found)
    end

    it '404s an id that names nothing' do
      get '/super_admin/platform_support/attachments/0'

      expect(response).to have_http_status(:not_found)
    end

    it 'refuses the download to a Super Admin with no agent row' do
      message = target.messages.create!(author_type: 'User', author_id: administrator.id, author_name: 'Dana',
                                        body: 'See attached.')
      file = attach(message, :platform_support_message_files)
      sign_out(super_admin)
      sign_in(staff_user, scope: :super_admin)

      get "/super_admin/platform_support/attachments/#{file.id}"

      expect(response).to redirect_to('/super_admin')
    end
  end

  # §6: Account 360 gains one count and one link, and the ticket detail links back. Both directions, asserted
  # from the Operations page rather than from this desk, because that page is the one an operator is on when
  # they need to know whether this account has raised anything.
  describe 'the Operations Account 360 seam' do
    before do
      agent
      sign_in(super_admin, scope: :super_admin)
    end

    it 'shows the Platform Support row and links to this account\'s tickets' do
      ticket

      get "/super_admin/operations/account?id=#{account.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Open Lynomia support tickets')
      expect(response.body).to include("/super_admin/platform_support?account_id=#{account.id}")
    end

    # The count key arrives with the backend branch. Until it does, the row says so rather than breaking the
    # page an operator needs for everything else.
    it 'says the count is not recorded while the snapshot has no key for it' do
      get "/super_admin/operations/account?id=#{account.id}"

      expect(response.body).to include('not recorded')
    end
  end

  # §B-11: Administrate enumerates every controller under super_admin/ from the route table and raises for one
  # with no index route and no dashboard. Without the exclusion entry, adding these routes breaks the sidebar
  # on EVERY Super Admin page -- so this is asserted on a page that has nothing to do with this desk.
  describe 'the Administrate navigation' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'still renders every Super Admin page now that these routes exist' do
      ['/super_admin', '/super_admin/accounts', '/super_admin/operations'].each do |path|
        get path
        expect(response).to have_http_status(:success), "#{path} did not render"
      end
    end

    it 'puts Customer Support in the lower operator block, with an icon that exists' do
      get '/super_admin'

      expect(response.body).to include('Customer Support')
      expect(response.body).to include('href="http://www.example.com/super_admin/platform_support"')
      expect(response.body).to include('id="icon-chat-smile-3-line"')
    end
  end
end
