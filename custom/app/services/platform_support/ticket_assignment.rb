# Assigns a Platform Support ticket to a Lynomia agent, or takes the assignment off
# (docs/platform-support/12-refresh-against-product-refinement.md §3 "Staff side").
#
# ONLY A `PlatformSupport::Agent` MAY BE AN ASSIGNEE, and that is structural rather than checked here: the
# column's foreign key points at `platform_support_agents`, so a tenant `User` id cannot be written to it at
# all. Which means no AccountUser membership is ever created for Lynomia staff -- the single thing that made
# the tenant helpdesk unusable for this product.
#
# WHO MAY REASSIGN is the staff authorizer's question (PlatformSupport::StaffAuthorizer#may_assign?), asked at
# the staff boundary before this service is reached: a `lead` may take a ticket off another agent, an `agent`
# may take unassigned work or hand back its own.
#
# `assigned` and `unassigned` are both excluded from the customer-visible event types: which operator holds a
# ticket is internal, and a customer watching names change learns nothing except how many people have touched
# their problem.
class PlatformSupport::TicketAssignment
  def initialize(ticket:, actor:, assignee:)
    @ticket = ticket
    @actor = actor
    @assignee = assignee
  end

  def perform
    return @ticket if @ticket.assignee_id == @assignee&.id

    event = @assignee.nil? ? 'unassigned' : 'assigned'
    previous_id = nil

    ActiveRecord::Base.transaction do
      # Locked first: an assignment is one operator taking responsibility, so two of them pressing Assign at
      # the same instant must not both be told they won it.
      @ticket.lock!
      previous_id = @ticket.assignee_id
      @ticket.update!(assignee: @assignee, last_activity_at: Time.current)
      PlatformSupport::EventRecorder.new(ticket: @ticket, actor: @actor).record(
        event, metadata: { from: previous_id, to: @assignee&.id }
      )
      PlatformSupport::AuditWriter.new(actor: @actor.user).write(
        @ticket, event, { 'from_agent_id' => previous_id, 'to_agent_id' => @assignee&.id, 'agent_id' => @actor.id }
      )
    end

    @ticket
  end
end
