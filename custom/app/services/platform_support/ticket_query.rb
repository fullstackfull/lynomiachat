# The tenant's ticket list: filters and one page of results
# (docs/platform-support/12-refresh-against-product-refinement.md §2 "GET /tickets").
#
# IT RECEIVES AN ALREADY POLICY-SCOPED RELATION. Who may see what is PlatformSupport::TicketPolicy::Scope's
# single answer and is not re-decided here, so this service cannot widen it.
#
# NO `assignee_id` FILTER AND NO SLA FILTER. The tenant has no knowledge of either -- the serializer does not
# emit them and the policy says why -- so a filter for them would be a question the API cannot answer.
#
# Every filter value is validated before it reaches a query: an unknown status, category or priority is a 422
# naming the allowed values. Nothing is silently ignored, because a silently dropped filter returns a page the
# customer will read as an answer to the question they asked.
class PlatformSupport::TicketQuery
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  def initialize(scope:, params: {})
    @scope = scope
    @params = params
  end

  def call
    filtered.newest_activity_first.page(@params[:page]).per(per_page)
  end

  def per_page
    requested = @params[:per_page].presence
    return DEFAULT_PER_PAGE if requested.blank?

    value = Integer(requested, exception: false)
    return value if value&.between?(1, MAX_PER_PAGE)

    raise CustomExceptions::PlatformTickets::InvalidLimit.new(limit: requested.to_s, maximum: MAX_PER_PAGE)
  end

  private

  def filtered
    relation = apply_allow_list(@scope, :status, PlatformSupport::Ticket.statuses.keys)
    relation = apply_allow_list(relation, :priority, PlatformSupport::Ticket.priorities.keys)
    relation = apply_allow_list(relation, :category, PlatformSupport::Ticket::CATEGORIES)
    apply_search(relation)
  end

  # One refusal for all three, naming the filter and the value that was not accepted, because from the
  # client's side they are the same mistake made in three places.
  def apply_allow_list(relation, key, allowed)
    requested = list(key)
    return relation if requested.empty?

    unknown = requested - allowed
    raise CustomExceptions::PlatformTickets::UnknownFilterValue.new(filter: key.to_s, value: unknown.first) if unknown.any?

    relation.where(key => requested)
  end

  # Reference first: a customer pasting `LYN-000123` or `123` wants that one ticket, not a subject match.
  # Falling through to a subject search when the reference misses would hide the fact that it does not exist.
  def apply_search(relation)
    term = @params[:q].to_s.strip
    return relation if term.blank?

    number = PlatformSupport::Ticket.reference_number_from(term)
    return relation.where(reference_number: number) if number.present? && term.match?(/\A(lyn-?)?0*\d+\z/i)

    relation.where('platform_support_tickets.subject ILIKE :term', term: "%#{sanitize_like(term)}%")
  end

  def list(key)
    Array.wrap(@params[key]).flat_map { |value| value.to_s.split(',') }.map(&:strip).reject(&:blank?)
  end

  def sanitize_like(term)
    term.gsub(/[\\%_]/) { |char| "\\#{char}" }
  end
end
