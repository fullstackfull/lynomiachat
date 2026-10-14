# The pricing page, and the quote request it collects.
#
# WHAT THIS PAGE PUBLISHES. Whatever the operator has marked for the website, and nothing else.
# docs/official-website/02-verified-feature-inventory.md section 4 establishes that no plan row, price,
# currency amount or tier exists anywhere in this repository -- no seed creates one, `price_cents` ships
# `default: 0`, and a no-exclusion search for commercial tier names found no plan name. So today `@plans` is
# empty and the page asks for a quote. When real plans exist and are ticked for the website, the same page
# renders them from the same query. That is the whole architecture: nothing is hard-coded, so nothing has to
# be rebuilt, and no number is invented in the meantime.
#
# THE COMPARISON DIMENSIONS ARE PUBLISHABLE EVEN WITH NO PLANS, because they are in the schema rather than in
# a marketing claim: plans carry ceilings on agents, inboxes and connected stores
# (custom/app/models/billing_plan.rb:9), bill monthly or annually, flat or per agent (:4-5), and can sell
# channels per plan (:87-93). The page says what a quote will be based on without saying what it will cost.
class Marketing::PricingController < Marketing::BaseController
  before_action :set_marketing_page

  def show
    @quote ||= SiteQuoteRequest.new
    render :show
  end

  # A public, unauthenticated write. Three things guard it, in this order: a Rack::Attack throttle per IP
  # (config/initializers/rack_attack.rb), strong parameters, and the model's own caps and allowlists.
  #
  # POST then REDIRECT, so a refresh after sending does not submit the request a second time. On failure the
  # page is re-rendered with the errors beside their fields and a 422, which is the status this repository's
  # rule asks for on invalid input.
  def create
    @quote = SiteQuoteRequest.new(quote_params.merge(locale: marketing_locale))

    if @quote.save
      notify_operator(@quote)
      redirect_to marketing_pricing_path(locale: params[:locale], sent: 1)
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  # THE ROW IS THE RECORD; THE EMAIL IS A CONVENIENCE ON TOP OF IT, and this method is what makes that
  # ordering true rather than merely intended.
  #
  # `deliver_later` is already asynchronous -- the SMTP conversation never happens inside the request, and
  # ApplicationMailer's `rescue_from(*ExceptionList::SMTP_EXCEPTIONS)` handles a relay failure in the job. But
  # ENQUEUEING can itself fail: the queue adapter talks to Redis, and a Redis that is down raises here, after
  # the row is committed. Without this rescue the visitor would be shown a 500 for a request that actually
  # succeeded, and would send it again.
  #
  # The rescue is deliberately broad and deliberately tiny: it wraps one call whose only job is to enqueue,
  # the queue adapter's failure modes are not enumerable from here (Redis, Sidekiq and ActiveJob each have
  # their own), and the correct response to every one of them is the same. It is logged at error level with
  # the id, so an operator can find the lead in Super Admin and answer it by hand.
  def notify_operator(quote)
    Marketing::QuoteMailer.new_request(quote).deliver_later
  rescue StandardError => e
    Rails.logger.error("[Marketing] quote request ##{quote.id} saved but notification could not be queued: #{e.class}: #{e.message}")
  end

  # `fetch` with empty parameters rather than `require`: a POST with no root key is a malformed client, and
  # answering it with the form and its validation errors is both more useful and the documented behaviour for
  # invalid input here. `require` would raise and answer 400 with a JSON body on an HTML page.
  def quote_params
    params.fetch(:site_quote_request, ActionController::Parameters.new)
          .permit(:name, :email, :company, :phone, :team_size, :message, channels: [])
  end

  def set_marketing_page
    @plans = BillingPlan.active.ordered.where(listed_on_website: true)
    @site_page = find_site_page(:standing, :pricing)
    return render_marketing_404 if @site_page.nil?

    @marketing_page = Marketing::Page.new(
      route: :pricing, title: @site_page.title, description: @site_page.description
    )
  end
end
