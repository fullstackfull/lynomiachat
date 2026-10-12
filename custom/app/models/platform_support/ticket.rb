# One complaint a customer raised with Lynomia itself
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M3, §4).
#
# WHAT THIS IS NOT: a tenant `Support::Ticket`. That is the customer's own helpdesk for their own end users;
# this is the customer's channel to their vendor. The two desks share a vocabulary on purpose -- the same four
# priorities, the same six-state shape -- so an operator learns one scale, and share nothing else.
#
# `account_id` IS THE SUBJECT, NOT AN OWNER, and it is nullable. It is required on create so a live ticket
# always has a subject; the column stays nullable so deleting an account ORPHANS the complaint history rather
# than erasing it. The tenant policy scope matches on a concrete account id, so an orphan falls out of every
# tenant read automatically rather than needing a rule, while staff and the audit trail keep it.
#
# `reporter_name` is the only personal-data snapshot here, and `reporter_email` must never be added: while the
# user exists the live address is reachable through `reporter_id`, and once it does not there is nobody to
# reply to. Operators reply in-thread, not by address.
class PlatformSupport::Ticket < ApplicationRecord
  self.table_name = 'platform_support_tickets'

  # DELIBERATELY NOT `audited`. The gem's Sweeper resolves its actor through Devise's `:user` scope while a
  # Super Admin authenticates under `:super_admin`, so an inferred actor here would be nil -- or, with a
  # co-resident tenant session, the tenant principal, which is worse than nothing. Staff accountability is an
  # explicit Custom::AuditLog write with an explicit actor: PlatformSupport::AuditWriter.
  #
  # `resolved` and `closed` are 4 and 5 because three partial indexes on this table use `status < 4`. Same
  # convention, and the same reason, as the tenant helpdesk.
  enum :status, { open: 0, in_progress: 1, waiting_on_customer: 2, waiting_on_lynomia: 3, resolved: 4, closed: 5 }
  # The same four values, in the same order, as Conversation and Support::Ticket.
  enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }, prefix: :priority

  OPEN_STATUSES = %w[open in_progress waiting_on_customer waiting_on_lynomia].freeze
  CLOSED_STATUSES = %w[resolved closed].freeze
  # `waiting_on_lynomia` pauses nothing: waiting on ourselves is our own delay. That is the tenant helpdesk's
  # own recorded reasoning and it is the right answer here too.
  SLA_PAUSING_STATUSES = %w[waiting_on_customer].freeze

  # The approved eleven, a frozen allow-list on a plain string column -- this repository's own pattern for a
  # constrained type. A value outside the list is a 422 at the request boundary, never coerced to `other`.
  CATEGORIES = %w[billing account_access channel_connection whatsapp commerce campaigns automation
                  performance data_export bug other].freeze

  MAX_SUBJECT = 255
  MAX_DESCRIPTION = 10_000

  # Global, six digits. The prefix and the padding are presentation and live here rather than in the column, so
  # changing either never needs a migration.
  REFERENCE_PREFIX = 'LYN'.freeze
  REFERENCE_DIGITS = 6

  belongs_to :account, optional: true
  belongs_to :reporter, class_name: 'User', optional: true
  belongs_to :assignee, class_name: 'PlatformSupport::Agent', optional: true
  belongs_to :sla_policy, class_name: 'PlatformSupport::SlaPolicy', optional: true

  has_many :messages, -> { order(created_at: :asc) }, class_name: 'PlatformSupport::Message',
                                                      foreign_key: :platform_support_ticket_id,
                                                      dependent: :destroy, inverse_of: :ticket
  # Reachable from the staff surface only. No tenant controller, serializer or query object names this
  # association, which is what makes the secrecy a table nobody joined rather than a predicate somebody forgot.
  has_many :internal_notes, -> { order(created_at: :asc) }, class_name: 'PlatformSupport::InternalNote',
                                                            foreign_key: :platform_support_ticket_id,
                                                            dependent: :destroy, inverse_of: :ticket
  has_many :events, -> { order(created_at: :asc) }, class_name: 'PlatformSupport::Event',
                                                    foreign_key: :platform_support_ticket_id,
                                                    dependent: :destroy, inverse_of: :ticket

  validates :account_id, presence: true, on: :create
  validates :account_name_at_creation, presence: true, length: { maximum: 255 }
  validates :reporter_name, presence: true, length: { maximum: 255 }
  validates :subject, presence: true, length: { maximum: MAX_SUBJECT }
  validates :description, length: { maximum: MAX_DESCRIPTION }
  validates :category, inclusion: { in: CATEGORIES }
  validates :reference_number, presence: true, uniqueness: true
  validate :reporter_belongs_to_the_subject_account, on: :create

  before_validation :assign_reference_number, on: :create
  before_validation :set_last_activity_at, on: :create

  scope :open_tickets, -> { where(status: OPEN_STATUSES) }
  scope :closed_tickets, -> { where(status: CLOSED_STATUSES) }
  scope :unassigned, -> { where(assignee_id: nil) }
  scope :newest_activity_first, -> { order(last_activity_at: :desc, id: :desc) }
  # The unread dot, as a predicate rather than a stored flag, so nothing has to be kept in step with the
  # thread. Expressed in SQL as well as in Ruby because the tenant list's `unread` count is one query.
  scope :unread, lambda {
    where.not(last_operator_message_at: nil)
         .where('customer_last_viewed_at IS NULL OR last_operator_message_at > customer_last_viewed_at')
  }

  # Rendered form. The column holds a bare global integer.
  def reference
    "#{REFERENCE_PREFIX}-#{reference_number.to_s.rjust(REFERENCE_DIGITS, '0')}"
  end

  # Accepts either form, because a customer pasting `LYN-000123` from an email should not have to strip it.
  def self.reference_number_from(value)
    value.to_s[/\d+/]&.to_i
  end

  def unread?
    last_operator_message_at.present? &&
      (customer_last_viewed_at.nil? || last_operator_message_at > customer_last_viewed_at)
  end

  # What the notification feed renders for a Platform Support row.
  #
  # NOT OPTIONAL, and not a convenience. `api/v1/accounts/notifications/index.json.jbuilder` calls
  # `push_event_data` on a notification's primary actor UNCONDITIONALLY, so once
  # `'PlatformSupport::Ticket'` is on `Notification::PRIMARY_ACTORS` the whole tenant feed raises for every
  # account on every read without this method.
  #
  # TENANT-SAFE KEYS ONLY, and the same list the ticket serializer is allowed: no assignee, no SLA field, no
  # due or breach stamp, no plan snapshot, no reporter identity beyond what the row already carries. The feed
  # is read by whoever can see the notification, so this is a published surface and is reviewed as one.
  def push_event_data
    {
      id: id,
      reference: reference,
      subject: subject,
      status: status,
      priority: priority,
      account_id: account_id
    }
  end

  def sla_paused? = sla_paused_at.present?
  def sla_applied? = sla_policy_id.present?
  def breached? = first_response_breached_at.present? || resolution_breached_at.present?

  private

  def assign_reference_number
    self.reference_number ||= PlatformSupport::ReferenceAllocator.next_reference_number
  end

  def set_last_activity_at
    self.last_activity_at ||= Time.current
  end

  # The controller resolves the reporter from the authenticated session, so a foreign id never reaches here.
  # This is the net under that: a service, a console or a future caller cannot open a ticket attributing it to
  # somebody outside the subject account.
  #
  # On create ONLY, deliberately. A ticket outlives the membership that opened it by design -- `reporter_id`
  # nullifies and `reporter_name` is the snapshot -- so re-checking membership on every save would make an
  # operator's reply fail on a ticket whose reporter has since left the account.
  def reporter_belongs_to_the_subject_account
    return if reporter_id.nil? || account_id.nil?
    return if AccountUser.exists?(account_id: account_id, user_id: reporter_id)

    errors.add(:reporter, 'must be a member of the subject account')
  end
end
