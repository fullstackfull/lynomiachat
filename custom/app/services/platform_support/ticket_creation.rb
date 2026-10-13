# Opens a Platform Support ticket
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M3, §2 "POST /tickets").
#
# EVERYTHING THE SERVER OWNS IS SET HERE AND NEVER ACCEPTED FROM A REQUEST: the reference number, the subject
# account, every snapshot, the assignee, the SLA policy, every SLA timestamp and the status. A new ticket always
# opens -- letting a client create one already `resolved` would skip the lifecycle and leave a ticket with a
# resolution it never had.
#
# THE FOUR SNAPSHOTS, and why each is taken at this moment rather than read later:
#   account_name_at_creation          deleting the account nullifies `account_id`; without this the orphaned
#                                     history is unattributable
#   reporter_name                     deleting the user nullifies `reporter_id`; this is the minimum that keeps
#                                     the thread attributable, and it is the ONLY personal-data snapshot
#   plan_id/plan_name_at_creation     `billing_plans.name` is free text an operator may edit and a plan may be
#                                     retired; the pair answers "what had they bought when they complained?"
#   subscription_status_at_creation   a ticket raised while past due reads differently from the same ticket
#                                     raised while trialling, and the live row will have moved on
#
# THE OPENING MESSAGE. The customer's own words start the thread, so the operator reads one chronological list
# rather than a header plus a list. It is also the only parent a create-time attachment can have: attachments
# live on messages and notes, never on the ticket, so `attachment_ids` on this endpoint would otherwise have
# nowhere to go.
#
# THE SLA IS RESOLVED HERE AND ITS ARITHMETIC IS NOWHERE IN THIS FILE. This service asks
# `Sla::PolicyResolver` which policy governs the account and lets `Sla::Clock` compute the due times; not one
# threshold value and not one date calculation lives here. A ticket created before any policy row exists
# carries no promise, which is the correct answer and what both surfaces say -- no policy is invented.
class PlatformSupport::TicketCreation
  def initialize(account:, reporter:, attributes:, blobs: [])
    @account = account
    @reporter = reporter
    @attributes = attributes.symbolize_keys
    @blobs = blobs
  end

  def perform
    ticket = nil

    # One transaction, because the advisory lock the reference allocator takes is transaction-scoped: the
    # number it hands out is only guaranteed unique while the lock is still held, which is until this commits.
    ActiveRecord::Base.transaction do
      ticket = PlatformSupport::Ticket.create!(
        @attributes.slice(:category, :subject, :description, :priority).merge(snapshots)
      )
      open_thread(ticket)
      PlatformSupport::EventRecorder.new(ticket: ticket, actor: @reporter).record(
        'created', metadata: { category: ticket.category, priority: ticket.priority, status: ticket.status }
      )
      apply_sla(ticket)
    end

    announce(ticket)
    ticket
  end

  private

  def snapshots
    subscription = @account.billing_subscription
    {
      account: @account,
      account_name_at_creation: @account.name,
      reporter: @reporter,
      reporter_name: @reporter.available_name,
      plan_id_at_creation: subscription&.plan_id,
      plan_name_at_creation: subscription&.plan&.name,
      subscription_status_at_creation: subscription&.status
    }
  end

  # The ONE message not written by PlatformSupport::MessageCreation, because it is not a reply: there is no
  # thread to reopen, no closed ticket to refuse, and the `created` event above already says the customer
  # spoke, so a `customer_replied` row at the same second would read as two things happening.
  def open_thread(ticket)
    message = ticket.messages.create!(
      PlatformSupport::Message.author_attributes_for(@reporter).merge(body: ticket.description)
    )
    message.platform_support_message_files.attach(@blobs) if @blobs.present?
    ticket.update!(last_customer_message_at: message.created_at)
  end

  # RESOLVED ONCE, AT CREATION, so an upgrade mid-ticket does not retroactively change a commitment Lynomia
  # already made -- which is why the ticket snapshots `plan_id_at_creation` beside `sla_policy_id`. Measured
  # from `created_at` rather than from `Time.current`: the promise starts when the customer asked, not when the
  # last callback in this transaction finished.
  #
  # The event's actor is the SYSTEM, not the reporter. The customer asked for a ticket; the target is Lynomia's
  # own commitment and no customer-visible event type covers it.
  def apply_sla(ticket)
    policy = PlatformSupport::Sla::PolicyResolver.for(account: @account)
    return if policy.nil?

    ticket.sla_policy = policy
    PlatformSupport::Sla::Clock.new(ticket).apply(from: ticket.created_at)
    ticket.save!
    PlatformSupport::EventRecorder.new(ticket: ticket).record(
      'sla_policy_applied',
      metadata: { sla_policy_id: policy.id, first_response_due_at: ticket.first_response_due_at&.iso8601,
                  resolution_due_at: ticket.resolution_due_at&.iso8601 }
    )
  end

  # AFTER THE COMMIT, deliberately: a job enqueued inside the transaction can be picked up by a worker before
  # that transaction commits, and an email about a ticket the database does not have yet is the one failure
  # mode this ordering removes. The operator message refuses itself when no support alias is configured, so
  # there is no pre-check here and no invented address anywhere.
  def announce(ticket)
    PlatformSupport::TicketMailer.ticket_created(ticket).deliver_later
    PlatformSupport::TicketMailer.new_ticket(ticket).deliver_later
  end
end
