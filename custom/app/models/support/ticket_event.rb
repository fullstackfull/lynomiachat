# One entry in a support case's history, and also one internal note (docs/p9/01-architecture.md §7).
#
# Both live in one table because an internal note IS an entry in the history: an agent reading a case wants the
# status change, the reassignment and the colleague's note in one order, and two tables would mean merging two
# orderings in the UI for no gain.
#
# This table is also what makes a case's history queryable, which a conversation's is not: only
# `conversation_status_changed` carries a structured payload (app/models/concerns/activity_message_handler.rb:50-61)
# and every other conversation change is localized prose that cannot be read back.
class Support::TicketEvent < ApplicationRecord
  self.table_name = 'support_ticket_events'

  NOTE = 'note'.freeze

  EVENT_TYPES = %w[
    created note status_changed priority_changed assigned team_changed category_changed
    conversation_linked conversation_unlinked
    sla_applied sla_first_response_met sla_first_response_breached sla_resolution_breached
    resolved reopened closed
  ].freeze

  belongs_to :account
  belongs_to :support_ticket, class_name: 'Support::Ticket', inverse_of: :events
  # Nil for an event the system wrote: the SLA sweeper, or a case opened by an operator rather than an agent.
  belongs_to :user, optional: true

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :body, presence: true, length: { maximum: 10_000 }, if: :note?
  validate :ticket_in_account

  scope :notes, -> { where(event_type: NOTE) }

  def note? = event_type == NOTE

  private

  def ticket_in_account
    return if support_ticket.nil? || support_ticket.account_id == account_id

    errors.add(:support_ticket, 'must belong to the same account')
  end
end
