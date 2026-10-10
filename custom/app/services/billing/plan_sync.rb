# frozen_string_literal: true

# Creates / updates the Stripe Product and Price for a BillingPlan.
#
# - Product: created once, then its name / description / active are kept in sync.
# - Price:   Stripe prices can't be edited. When amount, currency or interval
#            change, a new Price is created and the old one is archived.
#            Existing subscribers are then moved to the new price from their
#            next billing period (Billing::PriceMigrationJob).
#
# The API key is passed per request, so we never touch the global Stripe.api_key
# that Chatwoot's enterprise code may use.
class Billing::PlanSync
  class NotConfigured < StandardError; end

  # Archives the Stripe Product of a plan that has been deleted here. A class method because by the time it
  # runs the BillingPlan row is gone, and the Product lifecycle belongs with the rest of it rather than in the
  # controller that happened to delete the plan. Best effort: the plan is already gone either way.
  def self.archive_product!(product_id)
    api_key = Billing::Settings.stripe_secret_key
    return if product_id.blank? || api_key.blank?

    Stripe::Product.update(product_id, { active: false }, { api_key: api_key })
  rescue Stripe::StripeError => e
    Rails.logger.warn("[Billing] Could not archive Stripe product #{product_id}: #{e.message}")
  end

  def initialize(plan)
    @plan = plan
  end

  def perform
    raise NotConfigured, 'Stripe secret key is not set in Billing Settings' if api_key.blank?

    sync_product
    sync_price
    @plan
  end

  private

  def api_key
    @api_key ||= Billing::Settings.stripe_secret_key
  end

  def opts
    { api_key: api_key }
  end

  def sync_product
    params = { name: @plan.name, active: @plan.active, metadata: { billing_plan_id: @plan.id } }
    params[:description] = @plan.description if @plan.description.present?

    if @plan.stripe_product_id.present?
      Stripe::Product.update(@plan.stripe_product_id, params, opts)
    else
      product = Stripe::Product.create(params, opts)
      @plan.update_columns(stripe_product_id: product.id) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def sync_price
    return if current_price_matches?

    old_price_id = @plan.stripe_price_id
    price = Stripe::Price.create(
      {
        product: @plan.stripe_product_id,
        unit_amount: @plan.price_cents,
        currency: @plan.currency,
        recurring: { interval: @plan.interval },
        metadata: { billing_plan_id: @plan.id }
      },
      opts
    )
    @plan.update_columns(stripe_price_id: price.id) # rubocop:disable Rails/SkipsModelValidations
    return if old_price_id.blank?

    Stripe::Price.update(old_price_id, { active: false }, opts)
    # Existing subscribers pay the new price from their next period
    Billing::PriceMigrationJob.perform_later(@plan.id)
  end

  def current_price_matches?
    return false if @plan.stripe_price_id.blank?

    price = Stripe::Price.retrieve(@plan.stripe_price_id, opts)
    price.active &&
      price.unit_amount == @plan.price_cents &&
      price.currency == @plan.currency &&
      price.recurring&.interval == @plan.interval
  end
end
