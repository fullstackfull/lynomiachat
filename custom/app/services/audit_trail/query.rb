# One page of one account's audit trail (docs/p-final/clean-room/specs/A-audit-trail-read.md §2, §4).
#
# The account comes from the authenticated session and is the first thing applied, so no combination of filter,
# sort or page can reach another account's entries. The capability is checked here rather than in the controller
# because an account without the audit capability must get an empty page and a 200, not a refusal: the page then
# renders its own empty state instead of an error.
#
# The view needs exactly one thing from the audited record: the `user_id` of a membership entry, which is how
# the browser decides whether the actor edited themselves (app/javascript/dashboard/helper/auditlogHelper.js:218).
#
# `includes(:auditable)` used to supply it, and cost far more than it was worth: Rails preloads a polymorphic
# belongs_to with one query per distinct type on the page, the trail's vocabulary is fourteen types, and a page
# of 25 can mix all of them -- loading whole Account and Inbox rows, jsonb settings and provider config
# included, to read an integer that most of those types do not even have. #member_user_ids asks only the types
# whose table HAS a `user_id` column, and asks them for two columns rather than for records.
class AuditTrail::Query
  CAPABILITY = 'audit_logs'.freeze

  def initialize(account:, params: {})
    @account = account
    @filters = AuditTrail::Filters.new(params)
  end

  attr_reader :filters

  def entries
    @entries ||= scope.page(@filters.page).per(@filters.per_page)
  end

  # nil for an entry whose audited record has no `user_id`, and nil for one whose record has since been
  # deleted -- the same two answers `entry.auditable&.user_id` gave, and the second is the signal the browser
  # already reads to render its "deleted" label.
  def member_user_id(entry)
    member_user_ids[[entry.auditable_type, entry.auditable_id]]
  end

  def total_entries
    entries.total_count
  end

  def current_page
    entries.current_page
  end

  def per_page
    @filters.per_page
  end

  private

  def scope
    return Custom::AuditLog.none unless @account.feature_enabled?(CAPABILITY)

    filtered(Custom::AuditLog.for_account(@account))
  end

  # One query per type ON THIS PAGE that could answer, which in practice is none or one: of the fourteen types
  # the trail records, only a membership, an inbox member, a team member and a saved audience have the column.
  def member_user_ids
    @member_user_ids ||= entries.group_by(&:auditable_type).each_with_object({}) do |(type, rows), lookup|
      model = member_model(type)
      next if model.nil?

      model.where(id: rows.map(&:auditable_id)).pluck(:id, :user_id).each do |id, user_id|
        lookup[[type, id]] = user_id
      end
    end
  end

  # `safe_constantize` is given a value only this product's own `audited` declarations write -- the audited
  # model's class name -- and anything that does not resolve to a model with the column is skipped rather than
  # trusted.
  def member_model(type)
    model = type.to_s.safe_constantize
    return unless model.is_a?(Class) && model < ActiveRecord::Base
    return unless model.column_names.include?('user_id')

    model
  end

  def filtered(scope)
    scope = scope.of_type(@filters.types) if @filters.types
    scope = scope.by_actor(@filters.actor_id) if @filters.actor_id
    scope = scope.by_actor_name(@filters.actor_name) if @filters.actor_name
    scope = scope.occurred_between(@filters.window.first, @filters.window.last) if @filters.window
    @filters.sort == 'asc' ? scope.oldest_first : scope.newest_first
  end
end
