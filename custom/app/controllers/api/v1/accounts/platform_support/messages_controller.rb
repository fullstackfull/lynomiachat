# The public thread on one Platform Support ticket
# (docs/platform-support/12-refresh-against-product-refinement.md §2).
#
# PUBLIC MESSAGES ONLY, and that is a property of the model this controller names rather than of a predicate it
# applies: `PlatformSupport::InternalNote` is a different table, and there is no route, no scope and no
# serializer here that could reach it.
#
# The parent ticket is resolved through the policy scope before anything else happens, so a ticket id from
# another account is a 404 and the thread it names is never read.
class Api::V1::Accounts::PlatformSupport::MessagesController < Api::V1::Accounts::PlatformSupport::BaseController
  PER_PAGE = 50

  before_action -> { fetch_ticket(params[:ticket_id]) }
  before_action -> { authorize(@ticket, :show?) }, only: [:index]
  before_action -> { authorize(@ticket, :update?) }, only: [:create]

  def index
    @messages = @ticket.messages.oldest_first.page(params[:page]).per(PER_PAGE)
  end

  # A reply to a closed ticket is refused with 422 by the service, which is the earliest point both this
  # endpoint and the staff reply form pass through. A reply to a RESOLVED ticket succeeds and reopens it.
  def create
    @message = ::PlatformSupport::MessageCreation.new(
      ticket: @ticket, author: Current.user, body: message_params[:body],
      blobs: attachment_blobs(message_params[:attachment_ids])
    ).perform
    render :show, status: :created
  end

  private

  def message_params
    params.require(:message).require(:body)
    params.require(:message).permit(:body, attachment_ids: [])
  end
end
