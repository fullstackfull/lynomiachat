# What the customer is told happened to their ticket
# (docs/platform-support/12-refresh-against-product-refinement.md §2, §1 M6).
#
# A POSITIVE ALLOW-LIST, applied in the query and not in the view: `customer_visible` names 7 of the 18 event
# types, so an event type added in a later phase is invisible here until somebody deliberately lists it. The
# serializer carries no `metadata` key and no operator `actor_name`, so neither can leak through a partial
# somebody edits later.
class Api::V1::Accounts::PlatformSupport::EventsController < Api::V1::Accounts::PlatformSupport::BaseController
  before_action -> { fetch_ticket(params[:ticket_id]) }
  before_action -> { authorize(@ticket, :show?) }

  def index
    @events = @ticket.events.customer_visible.oldest_first
  end
end
