# The support-case list: filters, sort and page, all server side (docs/p9/02-support-tickets.md).
#
# It receives an ALREADY POLICY-SCOPED relation. Visibility is Support::TicketPolicy::Scope's job and is not
# re-decided here, so there is one definition of who can see what and this service cannot widen it.
#
# Every filter value is validated before it reaches a query: an unknown status, priority, category or sort key
# is a 422 naming the allowed values, and an id that does not belong to the account is a 422 naming the filter.
# Nothing is silently ignored, because a silently dropped filter returns a page the operator will read as an
# answer to the question they asked.
class Support::Tickets::Query
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  # The pseudo-statuses the workspace's tabs are built from, resolved here so the frontend does not have to know
  # which concrete statuses count as active.
  STATUS_GROUPS = {
    'active' => Support::Ticket::ACTIVE_STATUSES,
    'terminal' => Support::Ticket::TERMINAL_STATUSES
  }.freeze

  SORTS = {
    'last_activity_at' => { last_activity_at: :desc },
    'last_activity_at_asc' => { last_activity_at: :asc },
    'created_at' => { created_at: :desc },
    'created_at_asc' => { created_at: :asc },
    'resolution_due_at' => { resolution_due_at: :asc },
    'priority' => { priority: :desc, last_activity_at: :desc }
  }.freeze
  DEFAULT_SORT = 'last_activity_at'.freeze

  SLA_STATES = %w[overdue breached met_or_pending none].freeze

  # 9999-12-31T23:59:59Z; beyond this the column cannot represent the value. Same bound and same epoch contract
  # as the audit log reader (custom/app/controllers/api/v1/accounts/audit_logs_controller.rb:12).
  MAX_EPOCH = 253_402_300_799

  def initialize(account:, scope:, user:, params: {})
    @account = account
    @scope = scope
    @user = user
    @params = params
  end

  def call
    relation = filtered
    relation = relation.order(SORTS.fetch(sort_key))
    relation.page(@params[:page]).per(per_page)
  end

  def per_page
    requested = @params[:per_page].presence
    return DEFAULT_PER_PAGE if requested.blank?

    value = Integer(requested, exception: false)
    raise CustomExceptions::Tickets::InvalidLimit.new(limit: requested.to_s, maximum: MAX_PER_PAGE) unless value&.between?(1, MAX_PER_PAGE)

    value
  end

  def sort_key
    requested = @params[:sort].presence || DEFAULT_SORT
    return requested if SORTS.key?(requested)

    raise CustomExceptions::Tickets::UnsupportedSort.new(sort: requested.to_s, allowed: SORTS.keys)
  end

  private

  def filtered
    relation = @scope
    relation = apply_statuses(relation)
    relation = apply_enum(relation, :priority, Support::Ticket.priorities.keys,
                          CustomExceptions::Tickets::UnsupportedPriority, :priority)
    relation = apply_categories(relation)
    relation = apply_ownership(relation)
    relation = apply_links(relation)
    relation = apply_sla_state(relation)
    relation = apply_search(relation)
    apply_window(relation)
  end

  def apply_statuses(relation)
    requested = list(:status)
    return relation if requested.empty?

    expanded = requested.flat_map { |value| STATUS_GROUPS.fetch(value, [value]) }.uniq
    unknown = expanded - Support::Ticket.statuses.keys
    if unknown.any?
      raise CustomExceptions::Tickets::UnsupportedStatus.new(
        status: unknown.first, allowed: Support::Ticket.statuses.keys + STATUS_GROUPS.keys
      )
    end

    relation.where(status: expanded)
  end

  def apply_enum(relation, key, allowed, error_class, column)
    requested = list(key)
    return relation if requested.empty?

    unknown = requested - allowed
    raise error_class.new(key => unknown.first, :allowed => allowed) if unknown.any?

    relation.where(column => requested)
  end

  def apply_categories(relation)
    apply_enum(relation, :category, Support::Ticket::CATEGORIES,
               CustomExceptions::Tickets::UnsupportedCategory, :category)
  end

  # `assignee_id=me` and `assignee_id=unassigned` are the two views an agent lives in, resolved here rather than
  # making the client know its own user id or how to express a NULL.
  def apply_ownership(relation)
    assignee = @params[:assignee_id].presence
    relation = case assignee
               when nil then relation
               when 'me' then relation.where(assignee_id: @user&.id)
               when 'unassigned' then relation.where(assignee_id: nil)
               else relation.where(assignee_id: resolved_id(:assignee_id, assignee) { |id| account_member?(id) })
               end

    team = @params[:team_id].presence
    return relation if team.nil?

    relation.where(team_id: resolved_id(:team_id, team) { |id| @account.teams.exists?(id: id) })
  end

  def apply_links(relation)
    { contact_id: ->(id) { @account.contacts.exists?(id: id) },
      inbox_id: ->(id) { @account.inboxes.exists?(id: id) },
      conversation_id: ->(id) { @account.conversations.exists?(id: id) } }.each do |key, belongs|
      value = @params[key].presence
      next if value.nil?

      relation = relation.where(key => resolved_id(key, value, &belongs))
    end
    relation
  end

  def apply_sla_state(relation)
    state = @params[:sla].presence
    return relation if state.nil?

    raise CustomExceptions::Tickets::UnknownFilterValue.new(filter: 'sla', value: state) unless SLA_STATES.include?(state)

    case state
    when 'overdue' then relation.overdue
    when 'breached' then relation.breached
    when 'met_or_pending' then relation.where(first_response_breached_at: nil, resolution_breached_at: nil).where.not(sla_policy_id: nil)
    when 'none' then relation.where(sla_policy_id: nil)
    end
  end

  # Reference first: an operator pasting `TCK-000123` or `123` wants that one case, not a title match. Falling
  # through to a title search when the reference misses would hide the fact that the reference does not exist.
  def apply_search(relation)
    term = @params[:q].to_s.strip
    return relation if term.blank?

    number = Support::Ticket.reference_number_from(term)
    return relation.where(reference_number: number) if number.present? && term.match?(/\A(tck-?)?0*\d+\z/i)

    relation.where('support_tickets.title ILIKE :term', term: "%#{sanitize_like(term)}%")
  end

  def apply_window(relation)
    since = parsed_time(@params[:since])
    until_value = parsed_time(@params[:until])
    relation = relation.where(created_at: since..) if since
    relation = relation.where(created_at: ..until_value) if until_value
    relation
  end

  def list(key)
    Array.wrap(@params[key]).flat_map { |value| value.to_s.split(',') }.map(&:strip).reject(&:blank?)
  end

  # Membership, not a column comparison: a User is global in Chatwoot and joins an account through AccountUser.
  def account_member?(id)
    AccountUser.exists?(account_id: @account.id, user_id: id)
  end

  # One place where a filter id is turned into something a query may use, so "does this belong to my account?"
  # cannot be forgotten at one call site. An id from another tenant is a 422 naming the filter, never a silently
  # empty page.
  def resolved_id(filter, value)
    id = Integer(value, exception: false)
    raise CustomExceptions::Tickets::UnknownFilterValue.new(filter: filter.to_s, value: value.to_s) if id.nil?
    raise CustomExceptions::Tickets::UnknownFilterValue.new(filter: filter.to_s, value: value.to_s) unless yield(id)

    id
  end

  def sanitize_like(term)
    term.gsub(/[\\%_]/) { |char| "\\#{char}" }
  end

  def parsed_time(value)
    return if value.blank?

    epoch = Integer(value, exception: false)
    return unless epoch&.between?(0, MAX_EPOCH)

    Time.zone.at(epoch)
  end
end
