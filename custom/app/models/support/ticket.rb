# One support case (docs/p9/01-architecture.md §3).
#
# WHAT THIS IS NOT: a second conversation. Messages, private notes, attachments, mentions, CSAT, the channel and
# the customer identity all stay where they already are. A ticket adds exactly what Conversation has no column
# for -- a title, a category, a due date, an SLA clock, a resolve-versus-close distinction, a queryable history,
# and an operational origin -- and links to the conversation when there is one.
#
# WHY IT IS A SEPARATE TABLE: a Conversation cannot exist without an inbox (`conversations.inbox_id` is NOT NULL
# at db/schema.rb:1024 and validated at app/models/conversation.rb:77) and cannot be created without a contact
# (validated at :78, dereferenced in before_create at :308). An internal operational case -- "this account's IMAP
# inbox has been failing since Tuesday" -- has neither. The three links this table makes optional are precisely
# the three a conversation requires.
class Support::Ticket < ApplicationRecord
  include Labelable

  self.table_name = 'support_tickets'

  # The same four values, in the same order, as Conversation (app/models/conversation.rb:87), so an agent learns
  # one scale. No separate severity field: see docs/p9/01-architecture.md §5.
  enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }, prefix: :priority

  # Six states. `waiting_on_customer` is the only one that pauses the SLA clock -- waiting on ourselves is our own
  # delay (docs/p9/03-sla-workflow.md).
  enum :status, {
    open: 0, in_progress: 1, waiting_on_customer: 2, waiting_on_internal: 3, resolved: 4, closed: 5
  }

  ACTIVE_STATUSES = %w[open in_progress waiting_on_customer waiting_on_internal].freeze
  TERMINAL_STATUSES = %w[resolved closed].freeze
  SLA_PAUSING_STATUSES = %w[waiting_on_customer].freeze

  CATEGORIES = %w[technical billing account integration whatsapp commerce campaign automation operational other].freeze

  # The only operational origin P9 recognises. A frozen allow-list on a plain string column, which is this
  # repository's own pattern for a constrained type (custom/app/models/commerce/action_run.rb:66); there is no
  # polymorphic type allow-list anywhere here to copy, and `conversations.ai_assignee_type` is unconstrained at
  # both layers, so copying that would copy the hole.
  SOURCE_TYPES = %w[Operations::Signal].freeze

  REFERENCE_PREFIX = 'TCK'.freeze
  REFERENCE_DIGITS = 6

  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true
  belongs_to :inbox, optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :team, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :sla_policy, class_name: 'Support::SlaPolicy', optional: true
  belongs_to :source, polymorphic: true, optional: true

  has_many :events, -> { order(created_at: :asc) }, class_name: 'Support::TicketEvent', dependent: :destroy,
                                                    inverse_of: :support_ticket, foreign_key: :support_ticket_id

  validates :title, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 10_000 }
  validates :category, inclusion: { in: CATEGORIES }
  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true
  validates :reference_number, presence: true, uniqueness: { scope: :account_id }
  validate :linked_records_belong_to_account

  before_validation :assign_reference_number, on: :create
  before_validation :set_last_activity_at, on: :create

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :terminal, -> { where(status: TERMINAL_STATUSES) }
  scope :unassigned, -> { where(assignee_id: nil) }
  scope :overdue, -> { active.where.not(resolution_due_at: nil).where(resolution_due_at: ...Time.current) }
  scope :breached, -> { where.not(first_response_breached_at: nil).or(where.not(resolution_breached_at: nil)) }

  # Rendered form. The column holds a bare per-account integer; the prefix is presentation, so changing it never
  # needs a migration.
  def reference
    "#{REFERENCE_PREFIX}-#{reference_number.to_s.rjust(REFERENCE_DIGITS, '0')}"
  end

  # Accepts either form, because an operator pasting a reference from an email should not have to strip it.
  def self.reference_number_from(value)
    digits = value.to_s[/\d+/]
    digits&.to_i
  end

  def active? = ACTIVE_STATUSES.include?(status)
  def terminal? = TERMINAL_STATUSES.include?(status)
  def sla_paused? = sla_paused_at.present?
  def sla_applied? = sla_policy_id.present?
  def breached? = first_response_breached_at.present? || resolution_breached_at.present?

  private

  # Per-account sequential, assigned inside the creating transaction. The advisory lock is taken on
  # (namespace, account_id) and released when the transaction ends, so two simultaneous creates in the same
  # account serialise and creates in different accounts do not block each other at all.
  #
  # The alternative was to copy Conversation#display_id's Postgres trigger plus per-account dynamic sequence
  # (app/models/conversation.rb:429-431, app/models/account.rb:205-207). That needs a second named trigger on
  # accounts, a backfill creating a sequence for every existing account -- the sequences are not in db/schema.rb,
  # so a fresh schema load has none and the first insert raises -- an addition to Account#remove_account_sequences
  # or every account deletion leaks one, and a post-create re-fetch. For an object a human creates a few times an
  # hour, this is the smaller correct answer.
  def assign_reference_number
    return if reference_number.present? || account_id.blank?

    self.reference_number = Support::Tickets::ReferenceAllocator.next_for(account_id)
  end

  def set_last_activity_at
    self.last_activity_at ||= Time.current
  end

  # The controller resolves every link through Current.account, so a foreign id is a 404 before it reaches here.
  # This is the net under that: a service, a console or a future caller cannot write a cross-tenant link.
  def linked_records_belong_to_account
    {
      conversation: conversation, contact: contact, inbox: inbox, team: team, sla_policy: sla_policy
    }.each do |name, record|
      next if record.nil? || record.account_id == account_id

      errors.add(name, 'must belong to the same account')
    end

    validate_user_in_account(:assignee, assignee)
    validate_user_in_account(:created_by, created_by)
  end

  # A User is global in Chatwoot and joins an account through AccountUser, so membership is the check, not a
  # column comparison.
  def validate_user_in_account(name, user)
    return if user.nil?
    return if AccountUser.exists?(account_id: account_id, user_id: user.id)

    errors.add(name, 'must be a member of the same account')
  end
end
