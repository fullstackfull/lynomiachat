# frozen_string_literal: true

# The one implementation of "has this account used up its allowance of X?" (docs/p11/05-usage-limits.md).
#
# Lynomia (P11.23). The previous check was `current_count >= limit` read outside any lock, so two requests
# arriving at count == limit - 1 both read limit - 1, both passed, and both committed. A hard limit that two
# concurrent requests can walk past is not a limit, and there is no unique index behind these counts to catch
# the loser.
#
# The fix is the lock this repository already uses for exactly this shape -- `account.with_lock`, as in
# AgentBuilder#perform and DataImports::CreationService -- taken inside the save's own transaction, which is
# where a `validate ... on: :create` already runs. The second request blocks until the first has committed and
# then counts the row the first inserted.
#
# The ceiling comes from Billing::Entitlements, not from the plan directly, so an operator's override applies
# here too rather than only in the console.
module Billing::ResourceLimit
  module_function

  # @param account [Account]
  # @param resource [Symbol] one of BillingPlan::LIMIT_KEYS
  # @param current_count [Proc] counts the resource NOW; called after the lock is held, never before
  # @return [Integer, nil] the limit that was exceeded, or nil when there is room
  def exceeded(account, resource)
    limit = Billing::Entitlements.limit(account, resource)
    return nil if limit.nil?

    # Serialize every concurrent create for this account on the account row, then count. Already inside the
    # caller's transaction, so the lock is released when that transaction ends -- committed or rolled back.
    account.lock!
    yield >= limit ? limit : nil
  end

  def message(resource, limit)
    I18n.t("errors.billing.limit_reached.#{resource}", limit: limit,
                                                       default: I18n.t('errors.billing.limit_reached.generic', limit: limit))
  end
end
