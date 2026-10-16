# frozen_string_literal: true

# CAN A VISITOR ACTUALLY BUY THIS PLAN, AND IF NOT, WHY NOT.
#
# The public pricing page used to link every card at `#quote`, which was honest when there was no checkout to
# send anyone to. There is one -- `Billing::Checkout`, reachable by an administrator inside an account -- so
# the card can offer to sell the plan. What it must never do is offer a button that fails: a plan with no
# Stripe price, or an installation with no Stripe keys, cannot produce a Checkout Session, and a "Subscribe
# Now" that dead-ends is worse than the quote form it replaced.
#
# So the decision is made once, here, and both the page and the controller read it. The page uses it to
# choose between Subscribe Now and Contact Sales. The controller uses it to REFUSE a selection that is not
# purchasable, because a visitor can type a plan id into the URL and the page's rendering is not a check.
#
# WHY THE REASONS ARE NAMED RATHER THAN BOOLEAN. An operator who ticks "list on website", sets a price and
# sees Contact Sales anyway needs to know which of the four things is missing. `bundle exec rails
# pricing:diagnose` prints these, and `Billing::PlanOffer.diagnosis` is what it prints.
#
# WHAT IT DELIBERATELY DOES NOT DECIDE. Whether THIS visitor may buy it: that needs an account and a role,
# which a public page does not have. `Billing::Checkout` and the account API's `ensure_administrator` remain
# the only authority on that, and this class never widens them.
class Billing::PlanOffer
  # Ordered: the first unmet condition is the one an operator should fix first. `inactive` and `unlisted`
  # come first because they are the operator's own two deliberate switches; the Stripe pair are setup.
  REASONS = %i[inactive unlisted stripe_not_configured no_stripe_price].freeze

  def initialize(plan)
    @plan = plan
  end

  # The one question the page and the controller ask.
  def purchasable? = blocker.nil?

  # nil when purchasable, otherwise the first unmet condition as a symbol from REASONS.
  def blocker
    return :inactive unless @plan.active?
    return :unlisted unless @plan.listed_on_website?
    return :stripe_not_configured unless Billing::Settings.stripe_configured?
    return :no_stripe_price if @plan.stripe_price_id.blank?

    nil
  end

  class << self
    # The plans the public page shows. Listing is NOT the same question as purchasability: an operator may
    # publish a plan they only sell by conversation, and that plan belongs on the page with Contact Sales
    # under it. Keep this the one query so the page and the diagnosis agree.
    def listed = BillingPlan.active.ordered.where(listed_on_website: true)

    # Read-only, for the operator. One line per plan, saying whether a visitor can buy it and what to change.
    def diagnosis
      BillingPlan.ordered.map do |plan|
        offer = new(plan)
        { id: plan.id, name: plan.name, purchasable: offer.purchasable?, blocker: offer.blocker }
      end
    end
  end
end
