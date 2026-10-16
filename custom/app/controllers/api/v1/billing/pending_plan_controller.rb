# frozen_string_literal: true

# THE BRIDGE BETWEEN THE PUBLIC PAGE AND THE SIGNED-IN DASHBOARD.
#
# These two halves of the funnel authenticate in different ways and cannot see each other. The marketing
# site is server-rendered and knows only a Rails session; the dashboard signs in with `store: false`
# (app/controllers/devise_overrides/sessions_controller.rb) and carries a devise-token-auth token in
# headers, so no server-rendered page can tell who is looking at it, and the dashboard cannot read a session
# it never consults. The one thing they share is the ORIGIN -- the marketing site is served from
# FRONTEND_URL's host (Marketing::OfficialHost) -- so the dashboard's own XHR carries the Rails session
# cookie, and this endpoint can read with one identity what was written under the other.
#
# NOT ACCOUNT-SCOPED, DELIBERATELY. It is asked BEFORE an account is chosen -- answering "which account
# should pay for this?" is half its job -- so it hangs off Api::BaseController, which authenticates the user
# and nothing more.
#
# WHAT IT WILL NOT DO: create anything, charge anything, or widen anybody's access. It reports a plan the
# visitor already chose and the accounts they ALREADY administer. The purchase itself still goes through
# POST /api/v1/accounts/:account_id/billing/checkout, which re-checks the account, re-checks the role and
# re-checks the plan. A caller who lies to this endpoint gains nothing, because it is told nothing it does
# not already have.
class Api::V1::Billing::PendingPlanController < Api::BaseController
  # GET: the chosen plan, if there is still one, and the accounts this user could buy it for.
  def show
    plan = Billing::PendingPlan.read(session)
    return render json: { plan: nil, accounts: [] } if plan.nil?

    render json: { plan: plan_json(plan), accounts: administered_accounts.map { |a| account_json(a) } }
  end

  # DELETE: the dashboard has taken responsibility for this intention (or the person abandoned it).
  #
  # Clearing is its own call rather than a side effect of the read, because a read that forgets cannot
  # survive a page refresh -- and a refresh is exactly what happens when a new administrator is bounced
  # through onboarding on the way here.
  def destroy
    Billing::PendingPlan.clear(session)
    head :no_content
  end

  private

  # ONLY ACCOUNTS THIS USER ADMINISTERS, because only an administrator can buy
  # (Api::V1::Accounts::BillingController#ensure_administrator). Offering an account the next step would
  # refuse is a dead end dressed as a choice.
  def administered_accounts
    current_user.account_users
                .where(role: AccountUser.roles[:administrator])
                .includes(:account)
                .filter_map(&:account)
  end

  def plan_json(plan)
    {
      id: plan.id,
      name: plan.name,
      price: plan.price,
      currency: plan.currency,
      interval: plan.interval,
      pricing_type: plan.pricing_type
    }
  end

  # `subscribed` tells the dashboard which of the two legitimate paths this account needs -- a first
  # purchase through Billing::Checkout, or a change through Billing::PlanChange. Both are existing,
  # authorized flows; this only says which one applies, and the endpoint that runs it decides for itself.
  def account_json(account)
    subscription = account.billing_subscription
    {
      id: account.id,
      name: account.name,
      subscribed: subscription&.stripe_subscription_id.present? && subscription.status.in?(%w[active past_due])
    }
  end
end
