# Lynomia Campaigns (P5D): stopping a campaign is an administrator's act, at the same bar as
# editing one.
#
# WHY THE POLICY AND NOT THE CONTROLLER. `Api::V1::Accounts::CampaignsController` declares
# `before_action :check_authorization` with no `only:`, so it runs for the prepended `cancel`
# action as well, and `check_authorization` calls `authorize(Campaign)` with no explicit
# query. Pundit then derives the query from the action name, so the question actually asked
# is `cancel?` -- and a policy that cannot answer it raises NoMethodError, which nothing
# rescues, so every cancellation came back 500. Answering the question here is the fix that
# leaves the upstream controller's authorization in place; skipping the before_action in the
# prepend would have removed a guard to work around a missing answer.
#
# `update?`, not a new rule. Cancelling changes a campaign an administrator may change: it is
# smaller than destroying one, which also destroys the recipient snapshot, and larger than
# reading one. The controller's own `authorize @campaign, :update?` then asks the same
# question against the record, so the two agree by construction rather than by coincidence.
module Custom::CampaignPolicy
  def cancel? = update?
end
