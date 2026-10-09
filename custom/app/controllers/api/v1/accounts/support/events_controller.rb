# A case's history, and the internal notes inside it (docs/p9/01-architecture.md §7).
#
# Reading history needs the same visibility as reading the case, so the ticket is fetched through the policy
# scope first and a case the caller cannot see is a 404 before any event is touched.
#
# Only `note` can be created through the API. Every other event type is written by the service that performed
# the change, so a client cannot fabricate a status change that never happened.
class Api::V1::Accounts::Support::EventsController < Api::V1::Accounts::Support::BaseController
  before_action :fetch_ticket
  before_action -> { authorize(@ticket, :show?) }, only: [:index]
  before_action -> { authorize(@ticket, :update?) }, only: [:create]

  RESULTS_PER_PAGE = 50

  def index
    @events = @ticket.events.includes(:user).page(params[:page]).per(RESULTS_PER_PAGE)
    @current_page = @events.current_page
    @total_entries = @events.total_count
    @per_page = RESULTS_PER_PAGE
  end

  def create
    @event = ::Support::Tickets::EventRecorder.new(ticket: @ticket, user: Current.user)
                                              .record(::Support::TicketEvent::NOTE, body: note_params[:body])
    @ticket.update!(last_activity_at: Time.current)
    render :show, status: :created
  end

  private

  def fetch_ticket
    @ticket = ticket_scope.find(params[:ticket_id])
  end

  def note_params
    params.require(:event).permit(:body)
  end
end
