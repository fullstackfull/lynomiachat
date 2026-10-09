# This contact's support cases, as the durable trail of what happened to them
# (docs/p9/01-architecture.md §9).
#
# The source is `support_ticket_events`, not the ticket row: a case's history is already recorded there as typed
# rows with structured `data`, which is exactly the shape a timeline wants. This is the one source in the
# timeline whose history is queryable rather than prose -- a conversation's own assignee, team, label and
# priority changes are localized text with no structured payload
# (app/models/concerns/activity_message_handler.rb), which is why P8 had to leave them out.
#
# VISIBILITY IS OWNERSHIP, NOT CHANNEL. A case may have no inbox and no conversation, so neither
# the visibility value's `conversations` nor its `inbox_ids` can narrow it. The adapter therefore asks the case's own policy
# through Support::TicketPolicy::Scope, which is the same rule the ticket list uses.
#
# NOTE BODIES ARE NEVER EMITTED. An internal note is written for colleagues working the case, and a timeline is
# a wider audience; the entry says a note was added and by whom, and the note itself stays on the case.
class Contacts::ActivityTimeline::TicketsAdapter < Contacts::ActivityTimeline::BaseAdapter
  CATEGORY = 'tickets'.freeze

  def fetch(limit)
    scope = cursor_scope(events(limit), :created_at)
    scope.map { |event| entry_for(event) }
  end

  private

  def events(limit)
    Support::TicketEvent.where(account_id: @account.id, support_ticket_id: visible_ticket_ids)
                        .includes(:support_ticket)
                        .reorder(created_at: :desc, id: :desc)
                        .limit(limit)
  end

  # The contact's cases that this caller may see. `select(:id)` so it stays a subquery rather than a second
  # round trip whose result is interpolated.
  def visible_ticket_ids
    Support::TicketPolicy::Scope.for(user: caller_user, account: @account)
                                .where(contact_id: @contact.id)
                                .select(:id)
  end

  def entry_for(event)
    ticket = event.support_ticket
    Contacts::ActivityTimeline::Entry.new(
      source: 'support_ticket', record_id: event.id, category: CATEGORY,
      kind: "ticket_#{event.event_type}", occurred_at: event.created_at,
      conversation_id: ticket&.conversation_id, summary: ticket&.title,
      meta: {
        ticket_id: event.support_ticket_id, reference: ticket&.reference, status: ticket&.status,
        priority: ticket&.priority, ticket_category: ticket&.category, user_id: event.user_id
      }.merge(event.data.slice('from', 'to'))
    )
  end
end
