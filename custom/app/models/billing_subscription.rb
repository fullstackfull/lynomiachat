# frozen_string_literal: true

class BillingSubscription < ApplicationRecord
  STATUSES = %w[inactive trialing active past_due canceled].freeze
  SOURCES = %w[stripe manual].freeze

  belongs_to :account
  belongs_to :plan, class_name: 'BillingPlan', optional: true, inverse_of: :subscriptions
  belongs_to :scheduled_plan, class_name: 'BillingPlan', optional: true, inverse_of: :scheduled_subscriptions

  validates :account_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :stripe_subscription_id, uniqueness: true, allow_nil: true

  # Keep the account's Chatwoot features in line with its plan
  after_commit :sync_account_features, on: [:create, :update], if: -> { saved_change_to_plan_id? && plan.present? }

  scope :trialing, -> { where(status: 'trialing') }
  scope :past_due, -> { where(status: 'past_due') }

  def manual?
    source == 'manual'
  end

  def trial_active?
    status == 'trialing' && trial_ends_at.present? && trial_ends_at.future?
  end

  def in_grace_period?
    status == 'past_due' && grace_period_ends_at.present? && grace_period_ends_at.future?
  end

  # Can the account use the dashboard right now?
  def usable?
    case status
    when 'active'   then active_period_valid?
    when 'trialing' then trial_active?
    when 'past_due' then in_grace_period?
    else false
    end
  end

  # Is the dashboard open for the account? Same as usable?, except that an account
  # that never subscribed is not locked while billing is not set up (it can't pay yet).
  def accessible?
    usable? || (status == 'inactive' && !Billing::Settings.enforced?)
  end

  private

  # Stripe subscriptions are kept in sync by webhooks.
  # Manual grants may have an optional end date set by the super admin.
  def active_period_valid?
    return true unless manual?

    current_period_end.nil? || current_period_end.future?
  end

  def sync_account_features
    Billing::FeatureSync.new(account, plan).perform
  end
end
