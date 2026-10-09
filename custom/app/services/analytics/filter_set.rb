# The shared analytics filter contract (docs/p8/02-analytics.md).
#
# Two jobs, and the second is the important one.
#
# It refuses a filter a family has no meaning for, so a screen cannot quietly ignore a filter the operator set and
# show them numbers that do not match what they asked for.
#
# And it resolves every id *against the account*, so an id is only accepted if that account owns the row. The
# account comes from the authenticated context, never from the request, and no filter id reaches a query before
# this has confirmed ownership. That is what stops a crafted inbox_id or campaign_id from selecting another
# tenant's rows -- including through the two tables P8 discovery flagged as having no account_id of their own,
# `audits` (scoped by associated_type/associated_id) and `contact_inboxes` (reachable only through an inbox or a
# contact this account owns).
class Analytics::FilterSet
  attr_reader :family, :values

  def initialize(account:, family:, params: {})
    @account = account
    @family = family.to_s.to_sym
    @allowed = Analytics::MetricFamily.filters_for(@family)
    @values = resolve(params)
  end

  def [](key)
    @values[key]
  end

  def any?
    @values.any?
  end

  def to_meta
    @values.transform_values { |value| value }
  end

  private

  def resolve(params)
    given = (params || {}).to_h.symbolize_keys.slice(*Analytics::MetricFamily::ALL_FILTERS)
    reject_unsupported!(given)

    given.compact_blank.to_h { |filter, value| [filter, verify_ownership(filter, value)] }
  end

  # An unsupported filter is an error rather than something to drop. Dropping it would answer with numbers for a
  # different question than the one asked.
  def reject_unsupported!(given)
    unsupported = given.compact_blank.keys - @allowed
    return if unsupported.empty?

    raise CustomExceptions::Analytics::UnsupportedFilter.new(
      filter: unsupported.first.to_s, family: @family.to_s, allowed: @allowed.map(&:to_s)
    )
  end

  # One entry per filter, each resolving against this account. A table rather than a case so that adding a filter
  # is one line and the branching does not grow.
  #
  # channel_type has no canonical constant of channel classes in the repository, and inventing one would drift
  # from the files under app/models/channel/. The account's own inboxes are the better source: derived from real
  # data, account-scoped by construction, and an operator can only filter by a channel they actually have.
  def ownership_checks
    {
      inbox_id: -> { owned_id(@account.inboxes, @value, :inbox_id) },
      team_id: -> { owned_id(@account.teams, @value, :team_id) },
      agent_id: -> { owned_agent_id(@value) },
      campaign_id: -> { owned_id(@account.campaigns, @value, :campaign_id) },
      template_id: -> { owned_id(Whatsapp::MessageTemplate.where(account_id: @account.id), @value, :template_id) },
      automation_rule_id: -> { owned_id(@account.automation_rules, @value, :automation_rule_id) },
      channel_type: -> { allowed_value(@value, @account.inboxes.distinct.pluck(:channel_type), :channel_type) },
      provider: -> { allowed_value(@value, Commerce::Store::PROVIDERS, :provider) }
    }
  end

  def verify_ownership(filter, value)
    @value = value
    ownership_checks.fetch(filter).call
  end

  # `exists?` rather than `find`, because the answer needed is ownership and a 422 naming the filter is a better
  # answer than a 404 for a row the caller was never allowed to see.
  def owned_id(scope, value, filter)
    id = Integer(value, exception: false)
    raise CustomExceptions::Analytics::UnknownFilterValue.new(filter: filter.to_s) if id.nil?
    raise CustomExceptions::Analytics::UnknownFilterValue.new(filter: filter.to_s) unless scope.exists?(id: id)

    id
  end

  # An agent is a user reachable only through this account's account_users, so an agent id from another account
  # is rejected even though users are global.
  def owned_agent_id(value)
    id = Integer(value, exception: false)
    raise CustomExceptions::Analytics::UnknownFilterValue.new(filter: 'agent_id') if id.nil?
    raise CustomExceptions::Analytics::UnknownFilterValue.new(filter: 'agent_id') unless @account.account_users.exists?(user_id: id)

    id
  end

  def allowed_value(value, allowed, filter)
    normalized = value.to_s
    raise CustomExceptions::Analytics::UnknownFilterValue.new(filter: filter.to_s) unless allowed.map(&:to_s).include?(normalized)

    normalized
  end
end
