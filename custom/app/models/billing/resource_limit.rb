# frozen_string_literal: true

# The one implementation of "how many X does this account have, and has it used up its allowance?"
# (docs/p11/05-usage-limits.md).
#
# Lynomia (P11.6, P11.23). Two defects live here, and they are different problems:
#
# ONE COUNT PER RESOURCE. The count was written out at each site that needed it -- the validators, the access
# guard, the commerce connector, the account API, the Super Admin page -- so the number a customer was shown
# and the number the gate compared were two independent expressions of the same rule. COUNTS is now the only
# place a resource is counted.
#
# A LIMIT TWO REQUESTS CANNOT WALK PAST. The check was `current_count >= limit` read outside any lock, so two
# requests arriving at count == limit - 1 both read limit - 1, both passed, and both committed. There is no
# unique index behind these counts to catch the loser. The fix is the lock this repository already uses for
# exactly this shape -- `account.with_lock`, as in AgentBuilder#perform and DataImports::CreationService --
# taken inside the save's own transaction, which is where a `validate ... on: :create` already runs. The
# second request blocks until the first has committed and then counts the row the first inserted.
#
# The ceiling comes from Billing::Entitlements, not from the plan directly, so an operator's override applies
# wherever a limit is enforced or displayed rather than only in the console. This module replaced
# Billing::PlanLimits, which read the plan directly and therefore could not see an override.
module Billing::ResourceLimit
  module_function

  # The canonical counting query per resource. `stores` counts connected stores only: a disconnected store
  # holds no slot, which is the rule Commerce::StoreConnection has always applied.
  COUNTS = {
    agents: ->(account) { account.account_users.count },
    inboxes: ->(account) { account.inboxes.count },
    stores: ->(account) { account.commerce_stores.connected.count },
    # Every flow bot, not only the published ones. A draft nobody has published is still a flow the
    # account owns, edits and sees in its list -- counting only published flows would let an account
    # keep any number of them and hit the ceiling only at the moment it tried to turn one on.
    flows: ->(account) { account.agent_bots.flow.count }
  }.freeze

  # RESOURCES WHOSE USAGE IS METERED RATHER THAN COUNTED. The four in COUNTS above count rows
  # that EXIST, so deleting one gives it back; a send is spent and the allowance refills when
  # the billing period turns over. Billing::MeteredUsage owns the stored counter, and this
  # list is what routes a read to it -- without it `current_count` would KeyError on every
  # usage display the moment a metered key joined BillingPlan::LIMIT_KEYS.
  METERED = %i[campaign_sends].freeze

  # @param resource [Symbol, String] one of BillingPlan::LIMIT_KEYS
  def current_count(account, resource)
    key = resource.to_sym
    return Billing::MeteredUsage.usage(account, key.to_s)[:used] if METERED.include?(key)

    COUNTS.fetch(key).call(account)
  end

  # THE GATE for a COUNTED resource. Locks the account row, then counts, so concurrent creates
  # are serialized. Call it inside the caller's transaction -- the lock is released when that
  # transaction ends.
  #
  # A METERED resource has its own gate, Billing::MeteredUsage.consume, because the two do
  # different things: this one asks "is there room", which is idempotent and may be asked
  # twice; that one TAKES a unit, which may not.
  # @return [Integer, nil] the limit that was exceeded, or nil when there is room
  def exceeded(account, resource)
    limit = Billing::Entitlements.limit(account, resource)
    return nil if limit.nil?

    account.lock!
    current_count(account, resource) >= limit ? limit : nil
  end

  # A read-only pre-flight, for refusing early with a clear message and for showing the state in the UI.
  # NOT a gate: it takes no lock, so two concurrent requests can both pass it. `exceeded` is what refuses.
  def reached?(account, resource)
    limit = Billing::Entitlements.limit(account, resource)
    !limit.nil? && current_count(account, resource) >= limit
  end

  # THE SENTENCE FOLLOWS THE SOURCE OF THE CEILING. "Upgrade your plan" is the right advice when
  # the limit came from a plan bought here, and the wrong advice when it came from a platform that
  # bundles this product -- that merchant has no Lynomia plan to upgrade, and the number they need
  # changed lives in their package on the other side. Sending them to a billing page that cannot
  # help them is how a clear refusal becomes a support ticket.
  def message(resource, limit, source = nil)
    scope = source == :integration ? 'limit_reached_included' : 'limit_reached'

    I18n.t("errors.billing.#{scope}.#{resource}", limit: limit,
                                                  default: I18n.t("errors.billing.#{scope}.generic", limit: limit))
  end
end
