# frozen_string_literal: true

# Injected into Account via `Account.prepend_mod_with('Account')`
# (see app/models/account.rb and config/initializers/01_inject_enterprise_edition_module.rb)
module Custom::Account
  def self.prepended(base)
    base.has_one :billing_subscription, dependent: :destroy, inverse_of: :account
    # Commercial exceptions an operator granted this account (docs/p11/03-plans-entitlements.md).
    base.has_many :billing_entitlement_overrides, dependent: :destroy, inverse_of: :account
    base.has_many :commerce_stores, class_name: 'Commerce::Store', dependent: :destroy, inverse_of: :account
    # Lynomia Support (docs/p9/01-architecture.md). No `dependent:`: support_tickets.account_id carries an
    # ON DELETE CASCADE foreign key, so the database removes them and a second mechanism would only be a
    # second thing to keep in step.
    base.has_many :support_tickets, class_name: 'Support::Ticket', inverse_of: :account, dependent: nil
    base.has_many :sla_policies, class_name: 'Support::SlaPolicy', inverse_of: :account, dependent: nil
    # Runs after the signup transaction commits, so the admin user is already linked
    base.after_create_commit :start_billing_trial

    # WHOSE WORKSPACE THIS IS (P6D). `platform_owned` marks an account the installation runs
    # for itself -- Store Syria's own workspace for talking to its merchants -- rather than
    # one it sells. The scopes are named after Portal's, which answers the same question for
    # help centres, so the two read alike.
    #
    # `tenant` is the one almost every caller wants, and it is deliberately the longer name to
    # type: a listing that forgets to scope shows the platform's workspace among the
    # customers', which is how an operator comes to believe they have one more merchant than
    # they do, and how a merchant-facing list leaks the existence of an account nobody sold.
    base.scope :platform_owned, -> { where(platform_owned: true) }
    base.scope :tenant, -> { where(platform_owned: false) }
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
    # A PLATFORM WORKSPACE IS NOT A PROSPECT. The trial starter puts an account on the
    # merchant trial plan, which would give the installation's own workspace a trialing
    # subscription on a plan meant to be sold -- counted in the installation's own numbers and
    # expiring into a lock on a workspace nobody is going to upgrade. Its subscription is an
    # operator's deliberate act (Billing::PlatformWorkspace), not a signup side effect.
    return if platform_owned?
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
