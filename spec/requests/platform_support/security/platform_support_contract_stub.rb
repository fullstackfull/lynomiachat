# CONTRACT STUB -- the Platform Support domain, as the frozen contract specifies it, supplied ONLY where the
# real thing is absent.
#
# WHY THIS FILE EXISTS. Three agents build this module in parallel against
# `docs/platform-support/12-refresh-against-product-refinement.md`. Agent 1 owns the migrations, the models,
# the policies, the tenant ticket/message/event controllers, the serializers and the routes; Agent 3 owns the
# SLA engine, the notification path, the attachment download, the throttles and this security suite. Agent 3's
# code and its proofs cannot run against nothing, so this file supplies the six tables of §1, the models, the
# policy and the tenant routes/controllers of §2-§3 -- and supplies each of them ONLY if the real constant is
# not already defined.
#
# SO IT DISAPPEARS AT INTEGRATION, BY CONSTRUCTION. Every definition below is wrapped in `defined?`, every
# table is created `if_not_exists`, and the routes are drawn only when the real ones are not in the route set.
# Once Agent 1's branch is merged these specs bind to the real models, the real policy, the real base
# controller and the real routes without a line changing -- which is the point: the proofs become proofs of the
# shipped code rather than of the stub.
#
# WHAT IS *NOT* STUBBED, and is therefore under test for real right now:
#   PlatformSupport::Sla::{Clock, PolicyResolver, Sweeper, State}      Agent 3
#   PlatformSupport::SlaSweepJob                                       Agent 3
#   PlatformSupport::Notifications::ReplyNotifier                      Agent 3
#   PlatformSupport::{TicketMailer, SupportAlias}                      Agent 3
#   Api::V1::Accounts::PlatformSupport::AttachmentsController          Agent 3
#   Notification, Notifications::ConversationVisibility,
#     Notification::RemoveDuplicateNotificationJob                     Agent 3
#
# The stub takes no decisions of its own. Every column, enum value, index predicate, policy rule and route is
# transcribed from §1-§4; anything the contract does not state is left out rather than invented.

require 'rails_helper'

# --- §1 the six tables -------------------------------------------------------------------------------------
#
# Created once, outside any example transaction, and idempotently: a migration is Agent 1's to write and this
# must not become a second one. The partial indexes matter to the proofs -- `PlatformSupport::Sla::Sweeper` is
# shaped to them, and `status < 4` is why `resolved` and `closed` are numbered last.
module PlatformSupportContractStub
  FIRST_RESPONSE_INDEX_PREDICATE = 'first_response_due_at IS NOT NULL AND first_responded_at IS NULL ' \
                                   'AND first_response_breached_at IS NULL AND status < 4'
  RESOLUTION_INDEX_PREDICATE = 'resolution_due_at IS NOT NULL AND resolution_breached_at IS NULL AND status < 4'

  def self.install_schema!
    connection = ActiveRecord::Base.connection
    return if connection.table_exists?(:platform_support_tickets)

    agents(connection)
    sla_policies(connection)
    tickets(connection)
    ticket_indexes(connection)
    messages(connection)
    internal_notes(connection)
    events(connection)
    foreign_keys(connection)
  end

  def self.agents(connection)
    connection.create_table :platform_support_agents, if_not_exists: true do |t|
      t.bigint :user_id, null: false, index: { unique: true }
      t.integer :role, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.string :display_name, null: false
      t.timestamps null: false
    end
  end

  def self.sla_policies(connection)
    connection.create_table :platform_support_sla_policies, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :description
      t.bigint :billing_plan_id
      t.integer :first_response_time_threshold
      t.integer :resolution_time_threshold
      t.boolean :active, null: false, default: true
      t.timestamps null: false
    end
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def self.tickets(connection)
    connection.create_table :platform_support_tickets, if_not_exists: true do |t|
      t.integer :reference_number, null: false, index: { unique: true }
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
      t.timestamps null: false
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def self.ticket_indexes(connection)
    connection.add_index :platform_support_tickets, [:account_id, :last_activity_at],
                         order: { last_activity_at: :desc }, if_not_exists: true
    connection.add_index :platform_support_tickets, [:assignee_id, :status], if_not_exists: true
    connection.add_index :platform_support_tickets, [:status, :priority, :last_activity_at], if_not_exists: true
    connection.add_index :platform_support_tickets, :first_response_due_at, if_not_exists: true,
                                                                            name: 'index_ps_tickets_on_open_first_response_due',
                                                                            where: FIRST_RESPONSE_INDEX_PREDICATE
    connection.add_index :platform_support_tickets, :resolution_due_at, if_not_exists: true,
                                                                        name: 'index_ps_tickets_on_open_resolution_due',
                                                                        where: RESOLUTION_INDEX_PREDICATE
    connection.add_index :platform_support_tickets, :status, if_not_exists: true,
                                                             name: 'index_ps_tickets_on_unassigned_open',
                                                             where: 'assignee_id IS NULL AND status < 4'
  end

  def self.messages(connection)
    connection.create_table :platform_support_messages, if_not_exists: true do |t|
      t.bigint :platform_support_ticket_id, null: false, index: true
      t.string :author_type, null: false
      t.bigint :author_id
      t.string :author_name, null: false
      t.text :body, null: false
      t.timestamps null: false
    end
  end

  def self.internal_notes(connection)
    connection.create_table :platform_support_internal_notes, if_not_exists: true do |t|
      t.bigint :platform_support_ticket_id, null: false, index: true
      t.bigint :agent_id, null: false
      t.string :author_name, null: false
      t.text :body, null: false
      t.timestamps null: false
    end
  end

  def self.events(connection)
    connection.create_table :platform_support_events, if_not_exists: true do |t|
      t.bigint :platform_support_ticket_id, null: false, index: true
      t.string :event_type, null: false
      t.string :actor_type
      t.bigint :actor_id
      t.string :actor_name
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end
  end

  # The foreign keys of §1, because two proofs depend on them rather than on application code: account
  # deletion NULLs `account_id` and keeps the name snapshot, and only a `platform_support_agents` row can ever
  # be an assignee.
  def self.foreign_keys(connection)
    connection.add_foreign_key :platform_support_agents, :users, on_delete: :cascade unless
      connection.foreign_key_exists?(:platform_support_agents, :users)
    add_ticket_foreign_keys(connection)
    [:platform_support_messages, :platform_support_internal_notes, :platform_support_events].each do |table|
      next if connection.foreign_key_exists?(table, :platform_support_tickets)

      connection.add_foreign_key table, :platform_support_tickets, column: :platform_support_ticket_id,
                                                                   on_delete: :cascade
    end
  end

  def self.add_ticket_foreign_keys(connection)
    unless connection.foreign_key_exists?(:platform_support_tickets, :accounts)
      connection.add_foreign_key :platform_support_tickets, :accounts, on_delete: :nullify
    end
    unless connection.foreign_key_exists?(:platform_support_tickets, :platform_support_agents)
      connection.add_foreign_key :platform_support_tickets, :platform_support_agents, column: :assignee_id,
                                                                                      on_delete: :nullify
    end
    return if connection.foreign_key_exists?(:platform_support_tickets, :platform_support_sla_policies)

    connection.add_foreign_key :platform_support_tickets, :platform_support_sla_policies, column: :sla_policy_id,
                                                                                          on_delete: :nullify
  end

  # Every NOT NULL column a ticket needs, in one place. Four of them (`reference_number`,
  # `account_name_at_creation`, `reporter_name`, `last_activity_at`) are required on every row, which is
  # repeated complexity worth hiding; everything an example cares about is still passed per example.
  def self.ticket!(account:, reporter: nil, **attributes)
    ::PlatformSupport::Ticket.create!(
      {
        reference_number: (::PlatformSupport::Ticket.maximum(:reference_number) || 0) + 1,
        account: account,
        account_name_at_creation: account&.name.to_s.presence || 'Deleted account',
        reporter: reporter,
        reporter_name: reporter&.available_name.presence || 'A reporter',
        subject: 'A subject',
        last_activity_at: Time.current
      }.merge(attributes)
    )
  end

  # Appended rather than redrawn: `disable_clear_and_finalize` makes `draw` additive, so Devise, the rest of
  # the API and everything a signed-in request needs stay in the route set.
  def self.install_routes!
    return if Rails.application.routes.url_helpers.respond_to?(:api_v1_account_platform_support_attachment_path)

    Rails.application.routes.disable_clear_and_finalize = true
    Rails.application.routes.draw do
      scope 'api/v1/accounts/:account_id', module: 'api/v1/accounts' do
        namespace :platform_support do
          resources :tickets, only: [:index, :show] do
            member { post :mark_viewed }
            resources :messages, only: [:index, :create]
            resources :events, only: [:index]
          end
          resources :attachments, only: [:show]
        end
      end
    end
  ensure
    Rails.application.routes.disable_clear_and_finalize = false
    Rails.application.routes.finalize!
  end
end

PlatformSupportContractStub.install_schema!

# --- §1 the models -----------------------------------------------------------------------------------------

unless defined?(::PlatformSupport::Agent)
  class PlatformSupport::Agent < ApplicationRecord
    self.table_name = 'platform_support_agents'
    belongs_to :user
    enum :role, { agent: 0, lead: 1 }
  end
end

unless defined?(::PlatformSupport::SlaPolicy)
  class PlatformSupport::SlaPolicy < ApplicationRecord
    self.table_name = 'platform_support_sla_policies'

    # A policy with neither target cannot do anything, and attaching one would make a ticket look governed
    # when it is not (§1 M2).
    validate :at_least_one_threshold

    private

    def at_least_one_threshold
      return if first_response_time_threshold.present? || resolution_time_threshold.present?

      errors.add(:base, 'must set a first response or a resolution target')
    end
  end
end

unless defined?(::PlatformSupport::Ticket)
  class PlatformSupport::Ticket < ApplicationRecord
    self.table_name = 'platform_support_tickets'

    # §4, in this order because the partial indexes depend on `status < 4`.
    enum :status, { open: 0, in_progress: 1, waiting_on_customer: 2, waiting_on_lynomia: 3, resolved: 4, closed: 5 }
    enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }

    OPEN_STATUSES = %w[open in_progress waiting_on_customer waiting_on_lynomia].freeze
    CLOSED_STATUSES = %w[resolved closed].freeze
    REFERENCE_PREFIX = 'LYN'.freeze
    CATEGORIES = %w[billing account_access channel_connection whatsapp commerce campaigns automation performance
                    data_export bug other].freeze

    belongs_to :account, optional: true
    belongs_to :reporter, class_name: 'User', optional: true
    belongs_to :assignee, class_name: 'PlatformSupport::Agent', optional: true
    belongs_to :sla_policy, class_name: 'PlatformSupport::SlaPolicy', optional: true
    has_many :messages, class_name: 'PlatformSupport::Message', dependent: :destroy,
                        foreign_key: :platform_support_ticket_id, inverse_of: :ticket
    has_many :internal_notes, class_name: 'PlatformSupport::InternalNote', dependent: :destroy,
                              foreign_key: :platform_support_ticket_id, inverse_of: :ticket
    has_many :events, class_name: 'PlatformSupport::Event', dependent: :destroy,
                      foreign_key: :platform_support_ticket_id, inverse_of: :ticket

    def self.reference_number_from(value)
      value.to_s.delete_prefix("#{REFERENCE_PREFIX}-").to_i
    end

    def reference
      format("#{REFERENCE_PREFIX}-%06d", reference_number)
    end

    # Required by `app/views/api/v1/accounts/notifications/index.json.jbuilder:17`, which calls it on every
    # primary actor unconditionally. Tenant-safe keys only: no assignee, no SLA, no plan snapshot.
    def push_event_data
      { id: id, reference: reference, subject: subject, status: status, priority: priority, account_id: account_id }
    end
  end
end

unless defined?(::PlatformSupport::Message)
  class PlatformSupport::Message < ApplicationRecord
    self.table_name = 'platform_support_messages'
    belongs_to :ticket, class_name: 'PlatformSupport::Ticket', foreign_key: :platform_support_ticket_id,
                        inverse_of: :messages
    has_many_attached :platform_support_message_files
  end
end

unless defined?(::PlatformSupport::InternalNote)
  class PlatformSupport::InternalNote < ApplicationRecord
    self.table_name = 'platform_support_internal_notes'
    belongs_to :ticket, class_name: 'PlatformSupport::Ticket', foreign_key: :platform_support_ticket_id,
                        inverse_of: :internal_notes
    has_many_attached :platform_support_note_files
  end
end

unless defined?(::PlatformSupport::Event)
  class PlatformSupport::Event < ApplicationRecord
    self.table_name = 'platform_support_events'
    belongs_to :ticket, class_name: 'PlatformSupport::Ticket', foreign_key: :platform_support_ticket_id,
                        inverse_of: :events

    # A positive 7-of-18 allow-list, so a type added later is invisible until deliberately listed. Every
    # `sla_*` type is deliberately absent: Lynomia's internal commitments are not the customer's business.
    CUSTOMER_VISIBLE_EVENT_TYPES = %w[created status_changed customer_replied operator_replied resolved reopened
                                      closed].freeze
  end
end

# --- §3 the policy -----------------------------------------------------------------------------------------
#
# The Scope applies the ACCOUNT predicate itself and then narrows by role, deliberately unlike
# `Support::TicketPolicy::Scope`, which carries no account predicate and depends on two callers remembering
# one. A nil account, a nil membership or a role it does not recognise resolves to `none`.
unless defined?(::PlatformSupport::TicketPolicy)
  class PlatformSupport::TicketPolicy < ApplicationPolicy
    class Scope < ApplicationPolicy::Scope
      def resolve
        return scope.none if account.nil? || account_user.nil?

        base = scope.where(account_id: account.id)
        return base if account_user.administrator?
        # A custom-role holder has role `agent` and is treated exactly as an agent: V1 adds no
        # CustomRole::PERMISSIONS entry for this module (D-1).
        return base.where(reporter_id: user.id) if account_user.agent?

        scope.none
      end
    end

    def show?
      Scope.new(user_context, ::PlatformSupport::Ticket.all).resolve.exists?(id: record.id)
    end

    def index?
      account_user.present?
    end
  end
end

# --- §2/§3 the tenant base controller and the member routes ------------------------------------------------

unless defined?(::Api::V1::Accounts::PlatformSupport::BaseController)
  class Api::V1::Accounts::PlatformSupport::BaseController < Api::V1::Accounts::BaseController
    private

    # §3: the desk is exempt from Billing::AccessGuard, declared once on the module's base controller, so a
    # billing-locked customer can still complain about their bill. There is NO suspension exemption -- the
    # 401 in `ensure_current_account` fires one layer earlier and this module does not touch it.
    def billing_exempt?
      true
    end

    # The UNSCOPED relation: the Pundit Scope supplies the account predicate itself.
    def ticket_scope
      policy_scope(::PlatformSupport::Ticket.all)
    end
  end
end

unless defined?(::Api::V1::Accounts::PlatformSupport::TicketsController)
  class Api::V1::Accounts::PlatformSupport::TicketsController < Api::V1::Accounts::PlatformSupport::BaseController
    def index
      render json: { payload: ticket_scope.order(id: :asc).map { |ticket| serialize(ticket) } }
    end

    def show
      render json: serialize(fetch_ticket)
    end

    def mark_viewed
      fetch_ticket.update!(customer_last_viewed_at: Time.current)
      head :ok
    end

    private

    # Resolved INSIDE the already-account-scoped policy scope, so a numeric id or a `LYN-` reference from
    # another account raises RecordNotFound -- 404, never a 403 that confirms the row exists.
    def fetch_ticket
      if params[:id].to_s.match?(/\A\d+\z/)
        ticket_scope.find(params[:id])
      else
        ticket_scope.find_by!(reference_number: ::PlatformSupport::Ticket.reference_number_from(params[:id]))
      end
    end

    def serialize(ticket)
      { id: ticket.id, reference: ticket.reference, subject: ticket.subject, status: ticket.status,
        priority: ticket.priority, category: ticket.category, reporter_name: ticket.reporter_name,
        message_count: ticket.messages.size }
    end
  end
end

unless defined?(::Api::V1::Accounts::PlatformSupport::MessagesController)
  class Api::V1::Accounts::PlatformSupport::MessagesController < Api::V1::Accounts::PlatformSupport::BaseController
    def index
      render json: { payload: ticket.messages.order(id: :asc).map { |message| serialize(message) } }
    end

    def create
      message = ticket.messages.create!(
        author_type: 'User', author_id: Current.user.id, author_name: Current.user.available_name,
        body: params.require(:message).require(:body)
      )
      render json: serialize(message), status: :created
    end

    private

    def ticket
      @ticket ||= ticket_scope.find(params[:ticket_id])
    end

    # `author_name` is the literal "Lynomia Support" for every operator message; the individual is never
    # serialized (§2).
    def serialize(message)
      operator = message.author_type == 'PlatformSupport::Agent'
      { id: message.id, author_role: operator ? 'lynomia' : 'customer',
        author_name: operator ? 'Lynomia Support' : message.author_name, body: message.body }
    end
  end
end

unless defined?(::Api::V1::Accounts::PlatformSupport::EventsController)
  class Api::V1::Accounts::PlatformSupport::EventsController < Api::V1::Accounts::PlatformSupport::BaseController
    def index
      events = ticket_scope.find(params[:ticket_id]).events
                           .where(event_type: ::PlatformSupport::Event::CUSTOMER_VISIBLE_EVENT_TYPES)
                           .order(id: :asc)
      render json: { payload: events.map { |event| { id: event.id, event_type: event.event_type } } }
    end
  end
end

PlatformSupportContractStub.install_routes!
