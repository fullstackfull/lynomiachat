# Opens a support case (docs/p9/02-support-tickets.md).
#
# Everything the client may set arrives already resolved against Current.account by the controller, so this
# service never looks an id up: a cross-tenant link is a 404 before it reaches here, and the model's own
# validation is the net under that.
#
# `created_by` is the acting user and is never read from the request. An operator-created case has no acting
# account user, so it is nil, and the event trail records that the case was opened by the system.
class Support::Tickets::Create
  def initialize(account:, user:, attributes:)
    @account = account
    @user = user
    @attributes = attributes
  end

  def perform
    ticket = nil

    ActiveRecord::Base.transaction do
      ticket = @account.support_tickets.new(@attributes.merge(created_by: @user))
      Support::Tickets::SlaClock.new(ticket).apply if ticket.sla_policy_id.present?
      ticket.save!
      record_creation(ticket)
    end

    ticket
  end

  private

  def record_creation(ticket)
    Support::Tickets::EventRecorder.new(ticket: ticket, user: @user).record(
      'created', data: { category: ticket.category, priority: ticket.priority, status: ticket.status }
    )
    return if ticket.sla_policy_id.blank?

    Support::Tickets::EventRecorder.new(ticket: ticket, user: @user).record(
      'sla_applied',
      data: {
        sla_policy_id: ticket.sla_policy_id,
        first_response_due_at: ticket.first_response_due_at,
        resolution_due_at: ticket.resolution_due_at,
        business_hours: Support::Tickets::SlaClock.new(ticket).business_hours_applicable?
      }
    )
  end
end
