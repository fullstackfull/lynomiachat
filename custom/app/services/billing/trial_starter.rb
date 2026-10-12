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

  # The account's subscription. An account without one starts the trial on first
  # access once a trial is configured; until then it has none and is not locked.
  def self.subscription_for(account)
    account.billing_subscription || (new(account).perform if configured?)
  end

  def initialize(account, check_usage: true)
    @account = account
    @check_usage = check_usage
  end

  def perform
    return @account.billing_subscription if @account.billing_subscription.present?
    return start_trial if trial_allowed?

    @account.create_billing_subscription!(status: 'inactive')
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # A parallel request created it first. Both classes, because `validates :account_id, uniqueness: true`
    # fires before the index does: once the winner has committed, the loser is rejected by the validation and
    # raises RecordInvalid, not RecordNotUnique. Rescuing only the latter turned the dashboard's first batch of
    # parallel GETs into 422 "Account has already been taken" during rollout -- a read failing on a write it
    # never asked for.
    @account.reload.billing_subscription
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
