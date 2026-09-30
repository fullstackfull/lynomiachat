# frozen_string_literal: true

# Injected into Account via `Account.prepend_mod_with('Account')`
# (see app/models/account.rb and config/initializers/01_inject_enterprise_edition_module.rb)
module Custom::Account
  def self.prepended(base)
    base.has_one :billing_subscription, dependent: :destroy, inverse_of: :account
    base.has_many :commerce_stores, class_name: 'Commerce::Store', dependent: :destroy, inverse_of: :account
    # Runs after the signup transaction commits, so the admin user is already linked
    base.after_create_commit :start_billing_trial
    # prepend: true -> runs before the billing_subscription row is destroyed
    base.before_destroy :cancel_stripe_subscription, prepend: true
  end

  def billing_plan
    billing_subscription&.plan
  end

  def billing_usable?
    billing_subscription&.usable? || false
  end

  private

  # Never let a billing problem break account creation.
  # Before billing is set up (no Stripe keys, no trial plan) no subscription is created:
  # the account stays open and gets the trial on first access once a trial plan is
  # configured (see Billing::TrialStarter.subscription_for).
  def start_billing_trial
    return unless Billing::Settings.enforced?

    Billing::TrialStarter.new(self).perform
  rescue StandardError => e
    Rails.logger.error("[Billing] Could not start trial for account #{id}: #{e.message}")
  end

  # Stop charging the customer before the account disappears.
  # A Stripe outage raises here, which aborts the deletion (the job retries).
  def cancel_stripe_subscription
    Billing::SubscriptionCanceller.new(billing_subscription).perform
  end
end
