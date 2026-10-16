# frozen_string_literal: true

# THE PLAN A VISITOR PICKED BEFORE THEY SIGNED IN, AND HOW LONG IT STAYS PICKED.
#
# Written by the public pricing page (Marketing::PlanSelectionsController), read by the dashboard once the
# person has an identity (Api::V1::Billing::PendingPlanController). Those two live on opposite sides of an
# authentication boundary and share nothing else, which is exactly why the key, the expiry and the
# re-validation belong in one object rather than being spelled out at each end.
#
# WHAT IS STORED: an integer id and a timestamp. Not the price, not the name, not an eligibility verdict.
# Everything else is re-read from the row when it is used, because the session outlives the plan: an
# operator can unlist a plan, deactivate it or remove its Stripe price between the click and the sign-in,
# and a cached "yes" would sell something that is no longer for sale.
#
# WHY IT EXPIRES. A session cookie can live for weeks. An intention to buy does not: a visitor who picked a
# plan, wandered off and signed in a fortnight later for an unrelated reason should land in their inbox, not
# in a checkout they have forgotten choosing. An hour is long enough to read a confirmation email, create an
# account and finish onboarding, and short enough that the resume is never a surprise.
class Billing::PendingPlan
  KEY = 'pending_billing_plan'
  EXPIRES_IN = 1.hour

  class << self
    def write(session, plan)
      session[KEY] = { 'plan_id' => plan.id, 'chosen_at' => Time.current.to_i }
    end

    # The plan, or nil. Returns nil -- and clears the session -- for an intention that has expired, names a
    # row that is gone, or names one this installation no longer sells. A caller never has to ask a second
    # question about what it gets back.
    def read(session)
      stored = session[KEY]
      return nil if stored.blank?

      return clear(session) if expired?(stored)

      plan = Billing::PlanOffer.listed.find_by(id: stored['plan_id'])
      return clear(session) if plan.nil? || !Billing::PlanOffer.new(plan).purchasable?

      plan
    end

    # Always returns nil, so a guard clause can both forget the intention and answer in one line.
    def clear(session)
      session.delete(KEY)
      nil
    end

    private

    def expired?(stored)
      chosen_at = stored['chosen_at']
      chosen_at.blank? || Time.zone.at(chosen_at.to_i) < EXPIRES_IN.ago
    end
  end
end
