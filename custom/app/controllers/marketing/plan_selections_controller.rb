# frozen_string_literal: true

# A VISITOR CHOOSES A PLAN TO BUY, BEFORE WE KNOW WHO THEY ARE.
#
# This is the only new public surface in the purchase funnel, and it deliberately does almost nothing: it
# checks that the plan it was handed is one this installation actually sells, writes that plan's id into the
# visitor's own session, and sends them to sign in. No Stripe call, no account, no money.
#
# WHY THE SESSION AND NOT THE URL. The intention has to survive a sign-in, and on a fresh account also an
# email confirmation and the onboarding wizard. Three things in that path destroy a query string: the
# confirmation screen navigates to a fixed URL and drops whatever it was given
# (app/javascript/v3/views/auth/confirmation/Index.vue), the dashboard's route guard force-redirects a new
# administrator to onboarding, and neither existing root-relative-path validator
# (Marketing::LinkTarget::PATH, SiteRedirect::PATH) even permits a `?`. A server-side session survives all
# three, and -- the reason that matters more -- it cannot be edited by the person it is about. The browser
# holds an opaque cookie; the plan id lives on our side. There is no redirect target to forge and no price
# to tamper with, so the whole class of attack the obvious `?return_to=` design opens is simply absent.
#
# WHY IT STILL RE-READS THE PLAN LATER. Writing the id here is not a decision that it may be bought. The
# session can be minutes or days old, and a plan can be unlisted, deactivated or lose its Stripe price in
# between. Billing::PendingPlanController re-reads it, and Billing::Checkout re-reads it again. This is the
# first of three checks, not the only one.
class Marketing::PlanSelectionsController < Marketing::BaseController
  # Where a visitor goes to identify themselves. The sign-in page carries the "create an account" link when
  # the installation allows signups, and it bounces an already-signed-in visitor onward by itself
  # (app/javascript/v3/helpers/RouteHelper.js) -- so one destination serves all three kinds of visitor and we
  # do not have to guess which one this is. We cannot guess in any case: the dashboard signs in with
  # `store: false`, so no server-rendered page can tell whether the person holding this session is logged in.
  SIGN_IN_PATH = '/app/login'

  def create
    plan = Billing::PlanOffer.listed.find_by(id: params[:plan_id])
    offer = plan && Billing::PlanOffer.new(plan)

    return redirect_to_quote if offer.nil? || !offer.purchasable?

    Billing::PendingPlan.write(session, plan)
    redirect_to SIGN_IN_PATH, allow_other_host: false
  end

  private

  # A plan that is not on sale is not an error the visitor caused -- an operator may have unlisted it while
  # the page was open, or the id may be typed. Either way the answer is the page they came from, at the form
  # that can still help them, and not a 404 that reads as "this product does not exist".
  def redirect_to_quote
    redirect_to marketing_pricing_path(locale: params[:locale], anchor: 'quote')
  end
end
