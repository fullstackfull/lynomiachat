# Which status change is allowed, stated as a table rather than inferred from the enum
# (docs/p9/03-sla-workflow.md).
#
# The product rules this encodes:
#   * any active state can become any other active state -- an agent picking work up, putting it down, or waiting
#     on someone is not a workflow to police;
#   * any active state can reach either terminal state, because an agent may resolve a case or close it outright;
#   * `resolved` can be closed, or reopened to `open`;
#   * `closed` can only be reopened to `open`;
#   * a no-op transition is allowed and is a no-op, so an idempotent client retry does not 422.
#
# Everything else is refused with the attempted edge named, because a silent coercion to some "nearest legal"
# state would make the case history a fiction.
module Support::Tickets::StatusTransition
  ACTIVE = Support::Ticket::ACTIVE_STATUSES
  TERMINAL = Support::Ticket::TERMINAL_STATUSES

  ALLOWED = (
    ACTIVE.index_with { |_state| (ACTIVE + TERMINAL) }.merge(
      'resolved' => %w[closed open],
      'closed' => %w[open]
    )
  ).freeze

  module_function

  def allowed?(from, to)
    from = from.to_s
    to = to.to_s
    return true if from == to

    Array(ALLOWED[from]).include?(to)
  end

  def allowed_from(from)
    ([from.to_s] + Array(ALLOWED[from.to_s])).uniq
  end

  # Raised by the service layer, rendered as 422 by the controller.
  def ensure!(from, to)
    return if allowed?(from, to)

    raise CustomExceptions::Tickets::InvalidStatusTransition.new(from: from.to_s, to: to.to_s, allowed: allowed_from(from))
  end
end
