# Writes one row of a support case's history (docs/p9/01-architecture.md §7).
#
# One place, because the alternative is sixteen call sites each deciding for itself what goes in `data` -- and
# `data` is where the no-secrets rule has to hold. Callers pass ids, enum values, counts and timestamps; nothing
# here ever receives a message body, a provider payload or a credential.
class Support::Tickets::EventRecorder
  def initialize(ticket:, user: nil)
    @ticket = ticket
    @user = user
  end

  def record(event_type, data: {}, body: nil)
    Support::TicketEvent.create!(
      account_id: @ticket.account_id, support_ticket: @ticket, user: @user,
      event_type: event_type, body: body, data: data.compact.transform_keys(&:to_s)
    )
  end
end
