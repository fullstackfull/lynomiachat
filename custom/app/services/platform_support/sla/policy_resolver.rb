# Which SLA policy governs a new Platform Support ticket (docs/platform-support/06-sla-notifications.md §2).
#
# DATA-DRIVEN, BY `billing_plan_id`, AND NEVER BY A PLAN NAME. `billing_plans` has no `tier` and no `code`
# column; `name` is free text an operator edits in Super Admin. A string match on a plan name would stop
# matching the first time somebody renames a plan, silently, and the ticket would fall back to the default
# target without anybody being told. The id is the only stable key the table offers.
#
# TWO LOOKUPS, IN THIS ORDER, AND NO THIRD. The plan's own row, then the single installation default
# (`billing_plan_id IS NULL`). No match at all resolves to nil, which is not an error: a desk with no policy
# rows promises nothing, and `PlatformSupport::Sla::State#governed?` is what the surfaces read to say so. No
# row is invented and no threshold value appears anywhere in this module -- the numbers are owner data
# (D-7, docs/platform-support/12-refresh-against-product-refinement.md §11.1).
#
# RESOLVED ONCE, AT CREATION. The ticket snapshots `plan_id_at_creation` beside `sla_policy_id`, so an upgrade
# mid-ticket does not retroactively change a commitment Lynomia already made.
#
# `where(active: true)` rather than an `active` scope: the column is what the schema contract guarantees
# (§1 M2), so this resolves correctly whatever scopes the model happens to declare.
class PlatformSupport::Sla::PolicyResolver
  def self.for(account:)
    new(account: account).resolve
  end

  def initialize(account:)
    @account = account
  end

  def resolve
    return nil if @account.nil?

    plan_id = @account.billing_plan&.id
    (plan_id && active_policies.find_by(billing_plan_id: plan_id)) || active_policies.find_by(billing_plan_id: nil)
  end

  private

  def active_policies
    ::PlatformSupport::SlaPolicy.where(active: true)
  end
end
