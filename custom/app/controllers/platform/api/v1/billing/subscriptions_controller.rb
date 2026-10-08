# frozen_string_literal: true

# Subscriptions are addressed by ACCOUNT id: /platform/api/v1/billing/subscriptions/:account_id
class Platform::Api::V1::Billing::SubscriptionsController < Platform::Api::V1::Billing::BaseController
  before_action :set_account, except: [:index]
  before_action :validate_account_permissible, except: [:index]

  rescue_from ::Billing::AdminActions::Error, ::Billing::PlanChange::Error, ::Billing::Checkout::Error do |e|
    render_error('billing_error', e.message, :unprocessable_entity)
  end

  rescue_from Stripe::StripeError do |e|
    render_error('stripe_error', e.message, :unprocessable_entity)
  end

  # GET /platform/api/v1/billing/subscriptions?plan_id=1&status=active,trialing&source=manual&page=1&per_page=25
  def index
    scope = BillingSubscription.where(account_id: permissible_account_ids).order(id: :desc)
    scope = scope.where(plan_id: params[:plan_id]) if params[:plan_id].present?
    statuses = list_param(:status)
    scope = scope.where(status: statuses) if statuses.any?
    scope = scope.where(source: params[:source]) if params[:source].present?
    render_subscriptions_page(scope)
  end

  # GET /platform/api/v1/billing/subscriptions/:account_id
  def show
    render_subscription
  end

  # POST .../:account_id/change_plan_preview  { plan_id, prorate (default true) }
  def change_plan_preview
    render_data(::Billing::PlanChange.new(account: @account, plan: requested_plan, prorate: prorate?).preview)
  end

  # POST .../:account_id/change_plan  { plan_id, prorate (default true), proration_date (optional) }
  def change_plan
    actions.change_plan(requested_plan, prorate: prorate?, proration_date: params[:proration_date])
    render_subscription
  end

  # POST .../:account_id/extend_trial  { days }
  def extend_trial
    actions.extend_trial(params.require(:days))
    render_subscription
  end

  # POST .../:account_id/grant_plan  { plan_id, ends_at (optional, YYYY-MM-DD) }
  def grant_plan
    actions.grant_plan(requested_plan(active_only: false), ends_at: params[:ends_at])
    render_subscription
  end

  # POST .../:account_id/cancel
  def cancel
    actions.cancel!
    render_subscription
  end

  # POST .../:account_id/checkout_link  { plan_id, email (optional: a user of the account, default first admin) }
  def checkout_link
    user = params[:email].present? ? @account.users.from_email(params[:email]) : @account.administrators.first
    return render_error('user_not_found', 'No matching user in this account', :unprocessable_entity) if user.nil?

    url = ::Billing::Checkout.new(account: @account, plan: requested_plan, user: user).perform
    render_data({ url: url })
  end

  # POST .../:account_id/portal_link
  def portal_link
    customer_id = subscription.stripe_customer_id
    return render_error('no_billing_account', 'This account has never paid through Stripe', :unprocessable_entity) if customer_id.blank?

    session = Stripe::BillingPortal::Session.create(
      { customer: customer_id, return_url: "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}/app/accounts/#{@account.id}/settings/subscription" },
      { api_key: ::Billing::Settings.stripe_secret_key }
    )
    render_data({ url: session.url })
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end

  # Every account gets a subscription row (created on the fly if missing)
  def subscription
    @subscription ||= @account.billing_subscription || ::Billing::TrialStarter.new(@account).perform
  end

  def actions
    ::Billing::AdminActions.new(subscription)
  end

  def requested_plan(active_only: true)
    scope = active_only ? BillingPlan.active : BillingPlan
    scope.find(params.require(:plan_id))
  end

  def prorate?
    ActiveModel::Type::Boolean.new.cast(params.fetch(:prorate, true))
  end

  def render_subscription
    render_data(::Billing::ApiSerializer.subscription(@account.reload.billing_subscription, with_usage: true))
  end
end
