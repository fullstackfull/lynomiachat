# The Lynomia Platform Support Desk, operator side — the SIX DECISIONS
# (docs/platform-support/12-refresh-against-product-refinement.md §2, §3).
#
# Separated from the reads along the line that matters here: every action in this class is a POST or a PATCH,
# so none of them can be triggered by a link somebody pastes into a chat. It INHERITS the acting-agent guard
# from `SuperAdmin::PlatformSupportController` rather than restating it, so there is exactly one place that
# decides who may act on this desk.
#
# TWO INTEGRATION SEAMS, named here so neither is discovered by surprise:
#   1. each decision writes its own event row and its own `Custom::AuditLog` row inline, copying
#      `Operations::SignalLifecycle`. If a `PlatformSupport::` lifecycle service lands, these private methods
#      collapse into calls to it and nothing else on this surface changes.
#   2. an operator public reply is the one trigger for the `platform_support_reply` notification and for the
#      first-response SLA stamp. Neither is written here, because both belong to the SLA and notification
#      owner; `record_reply` is deliberately the single call site that has to grow those two calls.
class SuperAdmin::PlatformSupportActionsController < SuperAdmin::PlatformSupportController
  # A public reply. This is what the customer reads, what moves `last_operator_message_at`, and the only
  # operator action that reaches them at all.
  def reply
    with_ticket do
      body = params[:body].to_s.strip
      next 'A reply cannot be empty.' if body.blank?

      message = @ticket.messages.create!(author_type: 'PlatformSupport::Agent', author_id: @agent.id,
                                         author_name: @agent.display_name, body: body)
      record_reply(message)
      nil
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

      @ticket.internal_notes.create!(agent_id: @agent.id, author_name: @agent.display_name, body: body)
      @ticket.with_lock { @ticket.update!(last_activity_at: Time.current) }
      record_event('internal_note_added')
      audit('platform_support.internal_note_added', {})
      nil
    end
  end

  def status
    with_ticket do
      target = params[:status].to_s
      next "#{target.presence || 'That'} is not a status." unless PlatformSupport::Ticket.statuses.key?(target)
      next nil if target == @ticket.status

      previous = @ticket.status
      event_type = event_for_status(target, previous)
      @ticket.with_lock { @ticket.update!(status_attributes(target)) }
      record_event(event_type, from: previous, to: target)
      audit("platform_support.#{event_type}", 'from' => previous, 'to' => target)
      nil
    end
  end

  def triage
    with_ticket do
      changes = triage_changes
      next changes if changes.is_a?(String)
      next nil if changes.empty?

      @ticket.with_lock { @ticket.update!(changes.merge(last_activity_at: Time.current)) }
      changes.each { |field, value| record_triage_event(field, value) }
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

  # Resolving stamps `resolved_at`, closing stamps `closed_at`, and moving back to any open status clears both
  # — a reopened ticket that kept its resolution timestamp would read as resolved to everything that asks.
  def status_attributes(target)
    attributes = { status: target, last_activity_at: Time.current }
    return attributes.merge(resolved_at: nil, closed_at: nil) if PlatformSupport::Ticket::OPEN_STATUSES.include?(target)

    attributes[:resolved_at] = Time.current if target == 'resolved'
    attributes[:closed_at] = Time.current if target == 'closed'
    attributes
  end

  def event_for_status(target, previous)
    return target if %w[resolved closed].include?(target)

    PlatformSupport::Ticket::CLOSED_STATUSES.include?(previous) ? 'reopened' : 'status_changed'
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

  def record_triage_event(field, value)
    event_type = field == :priority ? 'priority_changed' : 'category_changed'
    record_event(event_type, to: value)
    audit("platform_support.#{event_type}", 'to' => value)
  end

  # A lead may reassign another agent's ticket; an agent may not. Taking an unassigned ticket, and handing
  # back one's own, are always allowed. Unassigning is explicit and writes its own event — it never happens as
  # a side effect of a status change, which is how a ticket gets forgotten.
  def apply_assignment
    target = params[:assignee_id].to_s
    return 'Choose an agent, or Unassign.' if target.blank?
    return lead_required_message unless may_reassign?
    return write_assignment(nil) if target == 'unassigned'

    assignee = PlatformSupport::Agent.find_by(id: target, active: true)
    return 'That agent does not exist, or is not active.' if assignee.nil?

    write_assignment(assignee)
  end

  def write_assignment(assignee)
    return nil if assignee&.id == @ticket.assignee_id

    @ticket.with_lock { @ticket.update!(assignee_id: assignee&.id, last_activity_at: Time.current) }
    record_event(assignee ? 'assigned' : 'unassigned', to: assignee&.display_name)
    audit(assignee ? 'platform_support.assigned' : 'platform_support.unassigned', 'assignee_id' => assignee&.id)
    nil
  end

  def may_reassign?
    @ticket.assignee_id.nil? || @ticket.assignee_id == @agent.id || @agent.lead?
  end

  def lead_required_message
    t('super_admin.platform_support.lead_required',
      default: "Only a lead may reassign another agent's ticket.")
  end

  # The reply's three consequences, in one place: the ticket's own operator-reply clock, the customer-visible
  # event, and the audit row. This is seam 2 from the header comment.
  #
  # THREE CALLS BELONG HERE AND ARE NOT YET MADE, because the classes live on the SLA and notification branch
  # and this one does not carry them. Integration adds exactly these, in this method, and nothing else on this
  # surface changes:
  #
  #   PlatformSupport::Notifications::ReplyNotifier.new(ticket: @ticket).perform
  #   PlatformSupport::Sla::Clock.new(@ticket).record_first_response
  #   PlatformSupport::TicketMailer.operator_replied(@ticket, message).deliver_later
  #
  # The mailer refuses by itself when no recipient address exists, so this method does not pre-check one.
  def record_reply(message)
    @ticket.with_lock do
      @ticket.update!(last_operator_message_at: message.created_at, last_activity_at: message.created_at)
    end
    record_event('operator_replied')
    audit('platform_support.operator_replied', 'message_id' => message.id)
  end

  def record_event(event_type, from: nil, to: nil)
    metadata = {}
    metadata['from'] = from if from.present?
    metadata['to'] = to if to.present?

    @ticket.events.create!(event_type: event_type, actor_type: 'PlatformSupport::Agent', actor_id: @agent.id,
                           actor_name: @agent.display_name, metadata: metadata)
  end

  # `associated` is deliberately absent, which files the row installation-wide. `Custom::AuditLog.for_account`
  # serves account-associated rows to that account's own administrators, so associating this one would publish
  # Lynomia's operator activity into the customer's own audit page.
  #
  # `audited_changes` carries ids, enum values and the reference string only: never a message body, never a
  # note, never a provider payload, never a credential. The actor is the real Super Admin, passed explicitly,
  # because the `audited` gem's Sweeper resolves an actor through Devise's `:user` scope while this surface
  # authenticates under `:super_admin`.
  def audit(comment, changes)
    Custom::AuditLog.create!(
      auditable: @ticket, user: current_super_admin, action: 'update', comment: comment,
      audited_changes: {
        'ticket_id' => @ticket.id,
        'reference' => @ticket.reference,
        'subject_account_id' => @ticket.account_id,
        'agent_id' => @agent.id
      }.merge(changes)
    )
  end
end
