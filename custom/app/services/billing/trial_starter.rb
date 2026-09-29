# frozen_string_literal: true

# Gives a new account its first BillingSubscription:
#   - "trialing" on the trial plan, if the trial is enabled and allowed
#   - "inactive" otherwise (the account must subscribe)
class Billing::TrialStarter
  class NotConfigured < StandardError; end

  # One-off: start a trial for every existing account that has no subscription yet.
  # Existing accounts always get the trial (the once-per-user rule is not applied).
  def self.backfill!
    raise NotConfigured, 'Enable the trial and choose a trial plan in Billing Settings first' unless configured?

    Account.where.missing(:billing_subscription).find_each.count do |account|
      new(account, check_usage: false).perform
    end
  end

  def self.configured?
    Billing::Settings.trial_enabled? && Billing::Settings.trial_plan.present? && Billing::Settings.trial_days.positive?
  end

  def initialize(account, check_usage: true)
    @account = account
    @check_usage = check_usage
  end

  def perform
    return @account.billing_subscription if @account.billing_subscription.present?
    return start_trial if trial_allowed?

    @account.create_billing_subscription!(status: 'inactive')
  end

  private

  def trial_allowed?
    return false unless self.class.configured?
    return true unless @check_usage && Billing::Settings.trial_once_per_user?

    !BillingTrialUsage.exists?(email: admin_emails)
  end

  def start_trial
    ends_at = Billing::Settings.trial_days.days.from_now
    subscription = @account.create_billing_subscription!(
      status: 'trialing',
      plan: Billing::Settings.trial_plan,
      trial_ends_at: ends_at
    )
    admin_emails.each do |email|
      BillingTrialUsage.find_or_create_by!(email: email) do |usage|
        usage.account_id = @account.id
        usage.trial_ends_at = ends_at
      end
    end
    subscription
  end

  def admin_emails
    @admin_emails ||= @account.administrators.pluck(:email).map(&:downcase)
  end
end
