# frozen_string_literal: true

# CRUD for plans is handled by Administrate (see BillingPlanDashboard).
# Billing settings live here as collection actions so they don't create
# an extra entry in the super admin sidebar.
class SuperAdmin::BillingPlansController < SuperAdmin::ApplicationController
  def settings
    @settings = Billing::Settings.all
    @plans = BillingPlan.ordered
  end

  def update_settings
    Billing::Settings.update!(settings_params)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to settings_super_admin_billing_plans_path, notice: 'Billing settings saved'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  # Administrate hooks: called only after a successful save
  def after_resource_created_path(resource)
    sync_with_stripe(resource)
    super
  end

  def after_resource_updated_path(resource)
    Billing::PlanAudit.record(resource, actor: current_super_admin)
    sync_with_stripe(resource)
    super
  end

  def sync_with_stripe(plan)
    Billing::PlanSync.new(plan).perform
  rescue Billing::PlanSync::NotConfigured => e
    flash[:error] = "Plan saved, but not synced with Stripe: #{e.message}"
  rescue Stripe::StripeError => e
    Rails.logger.error("[Billing] Stripe sync failed for plan #{plan.id}: #{e.message}")
    flash[:error] = "Plan saved, but Stripe sync failed: #{e.message}"
  end

  def settings_params
    params.require(:billing_settings).permit(*Billing::Settings::KEYS.keys)
  end
end
