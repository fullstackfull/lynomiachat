# Which status change is allowed, and to whom
# (docs/platform-support/12-refresh-against-product-refinement.md §4 "Transitions").
#
# Stated as a table rather than inferred from the enum, because the two sides of this desk have different
# authority and neither is the enum's business:
#
#   staff     may move a ticket to any status. They are the ones working it.
#   customer  may only close a ticket they have been told is resolved. Everything else they want to say, they
#             say in a message -- and a message on a resolved ticket reopens it, which is a transition the
#             reply path performs rather than one a client may ask for.
#
# A no-op is allowed and is a no-op, so an idempotent client retry does not 422. Everything else is refused
# with the attempted edge named, because coercing to some "nearest legal" state would make the history a
# fiction. Nothing auto-closes in V1.
module PlatformSupport::StatusTransition
  # The customer's whole vocabulary. Deliberately one edge: `resolved -> closed`.
  CUSTOMER_ALLOWED = { 'resolved' => %w[closed] }.freeze

  module_function

  def customer_allowed?(from, to)
    from.to_s == to.to_s || Array(CUSTOMER_ALLOWED[from.to_s]).include?(to.to_s)
  end

  def customer_allowed_from(from)
    ([from.to_s] + Array(CUSTOMER_ALLOWED[from.to_s])).uniq
  end

  # Raised at the request boundary and rendered as 422, so a refused transition never reaches a model.
  def ensure_customer_allowed!(from, to)
    return if customer_allowed?(from, to)

    raise CustomExceptions::PlatformTickets::InvalidStatusTransition.new(
      from: from.to_s, to: to.to_s, allowed: customer_allowed_from(from)
    )
  end
end
