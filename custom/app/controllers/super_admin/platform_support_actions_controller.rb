# The Lynomia Platform Support Desk, operator side — the SIX DECISIONS
# (docs/platform-support/12-refresh-against-product-refinement.md §2, §3).
#
# Separated from the reads along the line that matters here: every action in this class is a POST or a PATCH,
# so none of them can be triggered by a link somebody pastes into a chat. It INHERITS the acting-agent guard
# from `SuperAdmin::PlatformSupportController` rather than restating it, so there is exactly one place that
# decides who may act on this desk.
#
# THIS CLASS WRITES NOTHING ITSELF. Every action validates its input, refuses what is outside an allow-list,
# and then hands the decision to the one domain service that owns it -- `MessageCreation`, `NoteCreation`,
# `TicketTransition`, `TicketAssignment`. The ticket row, the history event, the audit row, the SLA clock, the
# notification and the email are consequences those services own, so the staff surface and the tenant API
# cannot drift apart: a reply typed here and a reply posted to the API are literally the same write.
#
# WHAT IS DECIDED HERE AND NOWHERE ELSE is the operator's half of the conversation: whether the input is
# acceptable, what the refusal says, and where the operator lands afterwards.
class SuperAdmin::PlatformSupportActionsController < SuperAdmin::PlatformSupportController
  # A public reply. This is what the customer reads, what moves `last_operator_message_at`, and the only
  # operator action that reaches them at all.
  def reply
    with_ticket do
      body = params[:body].to_s.strip
      next 'A reply cannot be empty.' if body.blank?

      PlatformSupport::MessageCreation.new(ticket: @ticket, author: @agent, body: body).perform
      nil
    rescue CustomExceptions::PlatformTickets::TicketClosed
      # The single writer refuses a reply to a closed thread, for the operator as well as for the customer:
      # a closed thread is one nobody is reading. Reopening it is a decision with its own event, so the
      # operator makes it deliberately rather than having a reply make it silently.
      t('super_admin.platform_support.ticket_closed',
        default: 'This ticket is closed. Reopen it before replying.')
    end
  end

  # An internal note. Never reaches the customer, and never moves `last_operator_message_at` — a desk where
  # internal triage looks like a customer reply makes every "customer replied" reading lie. Its event type
  # sits outside the customer-visible allow-list, so even the existence of internal discussion cannot be
  # inferred from the tenant surface.
  def note
    with_ticket do
      body = params[:body].to_s.strip
      next 'A note cannot be empty.' if body.blank?

      PlatformSupport::NoteCreation.new(ticket: @ticket, agent: @agent, body: body).perform
      nil
    end
  end

  def status
    with_ticket do
      target = params[:status].to_s
      next "#{target.presence || 'That'} is not a status." unless PlatformSupport::Ticket.statuses.key?(target)
      next nil if target == @ticket.status

      transition(status: target)
      nil
    end
  end

  def triage
    with_ticket do
      changes = triage_changes
      next changes if changes.is_a?(String)
      next nil if changes.empty?

      transition(**changes)
      nil
    end
  end

  # Assign or unassign. Only a `PlatformSupport::Agent` row may be an assignee — the FK says so — and no
  # AccountUser membership is ever created for Lynomia staff.
  def assign
    with_ticket { apply_assignment }
  end

  private

  # Every operator decision goes through here, so the not-found answer, the invalid-input answer and the
  # redirect target are decided once rather than per action. The block returns a refusal sentence, or nil when
  # the change applied or when there was nothing to apply.
  def with_ticket
    return if load_ticket.nil?

    refusal = yield
    return redirect_to(ticket_super_admin_platform_support_path(id: @ticket.id), alert: refusal) if refusal.present?

    redirect_to ticket_super_admin_platform_support_path(id: @ticket.id),
                notice: t('super_admin.platform_support.ticket_updated', default: 'Ticket updated.')
  end

  # Status, priority and category all travel the same road: the lifecycle timestamps, the SLA pause rule, one
  # history row per field that really changed, the audit row naming this operator, and the customer email the
  # two asking statuses send. None of that is this surface's to reproduce.
  def transition(**attributes)
    PlatformSupport::TicketTransition.new(ticket: @ticket, actor: @agent, attributes: attributes).perform
  end

  # The attributes to apply, or a refusal sentence. A value outside its allow-list is refused rather than
  # coerced, so an operator never silently re-files a ticket into a category that does not exist.
  def triage_changes
    changes = {}

    %i[priority category].each do |field|
      value = params[field].presence
      next if value.nil?
      return "#{value} is not a #{field}." unless valid_triage_value?(field, value)

      changes[field] = value unless value == @ticket.public_send(field)
    end

    changes
  end

  def valid_triage_value?(field, value)
    return PlatformSupport::Ticket.priorities.key?(value) if field == :priority

    PlatformSupport::Ticket::CATEGORIES.include?(value)
  end

  # A lead may reassign another agent's ticket; an agent may not. Taking an unassigned ticket, and handing
  # back one's own, are always allowed. Unassigning is explicit and writes its own event — it never happens as
  # a side effect of a status change, which is how a ticket gets forgotten.
  def apply_assignment
    target = params[:assignee_id].to_s
    return 'Choose an agent, or Unassign.' if target.blank?
    return lead_required_message unless PlatformSupport::StaffAuthorizer.new(@agent).may_assign?(@ticket)
    return write_assignment(nil) if target == 'unassigned'

    assignee = PlatformSupport::Agent.find_by(id: target, active: true)
    return 'That agent does not exist, or is not active.' if assignee.nil?

    write_assignment(assignee)
  end

  # The service answers the no-op case by returning the ticket unchanged, so this does not pre-check it.
  def write_assignment(assignee)
    PlatformSupport::TicketAssignment.new(ticket: @ticket, actor: @agent, assignee: assignee).perform
    nil
  end

  def lead_required_message
    t('super_admin.platform_support.lead_required',
      default: "Only a lead may reassign another agent's ticket.")
  end
end
