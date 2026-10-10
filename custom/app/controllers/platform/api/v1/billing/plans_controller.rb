# frozen_string_literal: true

class Platform::Api::V1::Billing::PlansController < Platform::Api::V1::Billing::BaseController
  before_action :set_plan, only: [:show, :update, :destroy, :sync, :subscribers]

  # GET /platform/api/v1/billing/plans?active=true
  def index
    plans = BillingPlan.ordered
    plans = plans.where(active: ActiveModel::Type::Boolean.new.cast(params[:active])) if params.key?(:active)
    render_data(plans.map { |plan| ::Billing::ApiSerializer.plan(plan) })
  end

  # GET /platform/api/v1/billing/plans/features
  def features
    render_data(BillingPlan.assignable_features)
  end

  # GET /platform/api/v1/billing/plans/:id
  def show
    render_data(::Billing::ApiSerializer.plan(@plan))
  end

  # GET /platform/api/v1/billing/plans/:id/subscribers?status=active,trialing&page=1&per_page=25
  def subscribers
    scope = @plan.subscriptions.where(account_id: permissible_account_ids).order(id: :desc)
    statuses = list_param(:status)
    scope = scope.where(status: statuses) if statuses.any?
    render_subscriptions_page(scope)
  end

  # POST /platform/api/v1/billing/plans
  def create
    plan = BillingPlan.create!(plan_params)
    render_data(::Billing::ApiSerializer.plan(plan), status: :created, meta: { stripe_sync: stripe_sync(plan) })
  end

  # PATCH /platform/api/v1/billing/plans/:id
  def update
    @plan.update!(plan_params)
    # Before the reload below, which clears `previous_changes`.
    ::Billing::PlanAudit.record(@plan, actor: @platform_app)
    render_data(::Billing::ApiSerializer.plan(@plan.reload), meta: { stripe_sync: stripe_sync(@plan) })
  end

  # DELETE /platform/api/v1/billing/plans/:id
  # Refused when accounts are on the plan (set active=false instead).
  def destroy
    product_id = @plan.stripe_product_id
    return render_error('plan_in_use', @plan.errors.full_messages.to_sentence, :unprocessable_entity) unless @plan.destroy

    archive_stripe_product(product_id)
    head :no_content
  end

  # POST /platform/api/v1/billing/plans/:id/sync
  def sync
    result = stripe_sync(@plan)
    render_data(::Billing::ApiSerializer.plan(@plan.reload), meta: { stripe_sync: result })
  end

  private

  def set_plan
    @plan = BillingPlan.find(params[:id])
  end

  def plan_params
    params.require(:plan).permit(
      :name, :description, :price, :currency, :interval, :pricing_type, :active, :position,
      limits: BillingPlan::LIMIT_KEYS, features: []
    )
  end

  def archive_stripe_product(product_id)
    return if product_id.blank? || ::Billing::Settings.stripe_secret_key.blank?

    Stripe::Product.update(product_id, { active: false }, { api_key: ::Billing::Settings.stripe_secret_key })
  rescue Stripe::StripeError => e
    Rails.logger.warn("[Billing] Could not archive Stripe product #{product_id}: #{e.message}")
  end
end
