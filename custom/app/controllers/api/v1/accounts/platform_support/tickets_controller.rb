# The customer's own Platform Support tickets
# (docs/platform-support/12-refresh-against-product-refinement.md §2).
#
# WHAT A REQUEST MAY SET IS DEFINED BY WHAT IT MAY NOT. `reference_number`, `account_id`, every snapshot,
# `assignee_id`, `sla_policy_id`, every SLA timestamp and `status` are owned by the services that set them and
# are never read from a request. A new ticket always opens: letting a client create one already `resolved`
# would skip the lifecycle and leave a ticket with a resolution it never had.
#
# PATCH ACCEPTS `priority`, AND `status` ONLY TO CLOSE A RESOLVED TICKET. It does not accept `category`
# (recategorising is triage, which is Lynomia's), `subject`, or `description` -- an edited description makes the
# thread above it incoherent, so the customer adds a message instead.
class Api::V1::Accounts::PlatformSupport::TicketsController < Api::V1::Accounts::PlatformSupport::BaseController
  before_action :fetch_ticket, only: [:show, :update, :mark_viewed]
  before_action -> { authorize(::PlatformSupport::Ticket) }, only: [:index, :create]
  before_action -> { authorize(@ticket, :show?) }, only: [:show, :mark_viewed]
  before_action -> { authorize(@ticket, :update?) }, only: [:update]

  def index
    @tickets = ::PlatformSupport::TicketQuery.new(scope: ticket_scope, params: filter_params).call
    @counts = ::PlatformSupport::TicketCounts.new(scope: ticket_scope).call
    @totals = ::PlatformSupport::ThreadTotals.for_tickets(@tickets.map(&:id))
  end

  def show
    @totals = ::PlatformSupport::ThreadTotals.for_tickets([@ticket.id])
  end

  def create
    @ticket = ::PlatformSupport::TicketCreation.new(
      account: Current.account, reporter: Current.user,
      attributes: create_attributes, blobs: attachment_blobs(create_params[:attachment_ids])
    ).perform
    @totals = ::PlatformSupport::ThreadTotals.for_tickets([@ticket.id])
    render :show, status: :created
  end

  def update
    @ticket = ::PlatformSupport::TicketTransition.new(
      ticket: @ticket, actor: Current.user, attributes: update_attributes
    ).perform
    @totals = ::PlatformSupport::ThreadTotals.for_tickets([@ticket.id])
    render :show
  end

  # Stamps what clears the unread dot. A POST rather than a GET because it writes, so no link or prefetch can
  # mark a customer's unread replies as read on their behalf.
  def mark_viewed
    @ticket.update!(customer_last_viewed_at: Time.current)
    head :ok
  end

  private

  def filter_params
    params.permit(:q, :page, :per_page, status: [], category: [], priority: []).to_h.symbolize_keys
  end

  def create_params
    params.require(:ticket).permit(:category, :subject, :description, :priority, attachment_ids: [])
  end

  # A ticket with no description is refused before anything is written. It is the one piece of spam control a
  # rate limit cannot provide, and an empty complaint is a thread an operator cannot answer.
  def create_attributes
    params.require(:ticket).require(:description)
    attributes = create_params.to_h.symbolize_keys.except(:attachment_ids)
    validate_category(attributes[:category]) if attributes.key?(:category)
    validate_priority(attributes[:priority]) if attributes.key?(:priority)
    attributes
  end

  def update_attributes
    permitted = params.require(:ticket).permit(:priority, :status)
    attributes = {}
    attributes[:priority] = validate_priority(permitted[:priority]) if permitted.key?(:priority)
    attributes[:status] = requested_status(permitted[:status]) if permitted.key?(:status)
    attributes
  end

  # Two checks, both 422, because they are two different mistakes: a status that is not a status at all, and a
  # status the customer is not the one who decides. The customer's whole vocabulary is `resolved -> closed`.
  def requested_status(value)
    validate_status(value)
    ::PlatformSupport::StatusTransition.ensure_customer_allowed!(@ticket.status, value)
    value
  end

  def validate_category(value)
    return value if ::PlatformSupport::Ticket::CATEGORIES.include?(value)

    raise CustomExceptions::PlatformTickets::UnsupportedCategory.new(
      category: value.to_s, allowed: ::PlatformSupport::Ticket::CATEGORIES
    )
  end

  def validate_priority(value)
    return value if ::PlatformSupport::Ticket.priorities.key?(value)

    raise CustomExceptions::PlatformTickets::UnsupportedPriority.new(
      priority: value.to_s, allowed: ::PlatformSupport::Ticket.priorities.keys
    )
  end

  def validate_status(value)
    return value if ::PlatformSupport::Ticket.statuses.key?(value)

    raise CustomExceptions::PlatformTickets::UnsupportedStatus.new(
      status: value.to_s, allowed: ::PlatformSupport::Ticket.statuses.keys
    )
  end
end
