# frozen_string_literal: true

class BillingPlan < ApplicationRecord
  INTERVALS = %w[month year].freeze
  PRICING_TYPES = %w[flat per_agent].freeze
  # 2-decimal currencies only (price is stored in cents)
  CURRENCIES = %w[usd eur gbp sar aed try egp].freeze
  # stores: Lynomia Commerce stores an account keeps connected (Commerce::StoreConnection)
  LIMIT_KEYS = %w[agents inboxes stores].freeze
  FEATURES_FILE = Rails.root.join('config/features.yml')
  # System flags that must never be switched off by a plan
  SYSTEM_FEATURES = %w[chatwoot_v4 assignment_v2 report_rollup].freeze

  has_many :subscriptions, class_name: 'BillingSubscription', foreign_key: :plan_id,
                           inverse_of: :plan, dependent: :restrict_with_error
  has_many :scheduled_subscriptions, class_name: 'BillingSubscription', foreign_key: :scheduled_plan_id,
                                     inverse_of: :scheduled_plan, dependent: :restrict_with_error

  before_validation :normalize_attributes
  after_update_commit :sync_subscribers_features, if: :saved_change_to_features?

  validates :name, presence: true
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :interval, inclusion: { in: INTERVALS }
  validates :pricing_type, inclusion: { in: PRICING_TYPES }
  validate :validate_limits
  validate :validate_features
  validate :validate_channel_entitlements
  validate :refuse_narrowing_while_billed, on: :update

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  # Features the super admin can attach to a plan.
  # Excludes internal, deprecated, premium (enterprise-licensed) and system features.
  def self.assignable_features
    @assignable_features ||= YAML.safe_load(FEATURES_FILE.read)
                                 .reject { |f| f['chatwoot_internal'] || f['deprecated'] || f['premium'] }
                                 .reject { |f| SYSTEM_FEATURES.include?(f['name']) }
                                 .map { |f| { 'name' => f['name'], 'display_name' => f['display_name'] } }
                                 .freeze
  end

  # Price in normal units (e.g. 19.99) - used by the super admin form
  def price
    price_cents.to_i / 100.0
  end

  def price=(value)
    self.price_cents = value.blank? ? 0 : (BigDecimal(value.to_s) * 100).round
  rescue ArgumentError
    self.price_cents = nil # invalid input -> fails numericality validation
  end

  # nil => unlimited
  def limit_for(key)
    limits[key.to_s]
  end

  def feature_included?(name)
    features.include?(name.to_s)
  end

  # An empty list is "this plan has no opinion about channels", which denies nothing. See the migration header
  # and Billing::Entitlements#channel_allowed? -- it is what keeps every existing plan behaving as it does now.
  def channel_included?(channel_type)
    channel_entitlements.blank? || channel_entitlements.include?(channel_type.to_s)
  end

  def sells_channels?
    channel_entitlements.present?
  end

  private

  def normalize_attributes
    self.currency = currency.to_s.strip.downcase
    self.features = Array(features).map(&:to_s).compact_blank.uniq
    self.limits = (limits || {}).to_h
                                .transform_keys(&:to_s)
                                .slice(*LIMIT_KEYS)
                                .compact_blank
                                .transform_values(&:to_i)
    self.channel_entitlements = Array(channel_entitlements).map(&:to_s).compact_blank.uniq
  end

  # Validated against Channels::Capability, which P10 established as the one list of the channel types this
  # fork actually has. A typo here would sell a channel that does not exist, or silently withhold one.
  def validate_channel_entitlements
    unknown = channel_entitlements - Channels::Capability::BY_CHANNEL_TYPE.keys
    errors.add(:channel_entitlements, "unknown channel types: #{unknown.join(', ')}") if unknown.any?
  end

  def validate_limits
    limits.each do |key, value|
      errors.add(:limits, "#{key} must be 0 or more") if value.negative?
    end
  end

  def validate_features
    unknown = features - self.class.assignable_features.pluck('name')
    errors.add(:features, "unknown: #{unknown.join(', ')}") if unknown.any?
  end

  # P-FINAL (docs/p-final/06-clean-code-review.md §2, answering P11's first known limitation).
  #
  # There are no plan versions, so editing a live plan changes every subscriber immediately and mid-period.
  # P11 shipped that with a blast-radius warning on the form and a mandatory audit row, and recorded it as a
  # limitation. For a commercial release a warning is not enough: the harm is not "a customer's plan changed",
  # it is "a customer lost, mid-period, a capability or a ceiling they are paying for", which is a refund
  # conversation and in some jurisdictions a contractual one.
  #
  # The rule here is therefore asymmetric, because the harm is asymmetric: while a plan has billed subscribers
  # it may be WIDENED but never NARROWED. Adding a feature, raising or removing a ceiling, selling another
  # channel or clearing the channel list all give customers more than they bought and need no ceremony.
  # Taking any of those away requires a new plan and a deliberate move of each subscriber -- which is the
  # product rule P11 wrote down, now enforced by the server instead of asked for in a hint.
  #
  # Why not plan versions or a subscription snapshot. Both were considered (docs/p11/03-plans-entitlements.md
  # records the shape). Each needs a new table or column, a write on every plan edit, a resolution path through
  # the snapshot in Billing::Entitlements, and a backfill decision for existing subscriptions -- and all of that
  # to express a rule this validation expresses in one place with no schema at all. A narrowing is rare, and
  # answering it with "create the corrected plan and move people to it" is both the honest commercial answer and
  # the one an operator can already carry out with the console that exists.
  #
  # Nothing is locked for a plan nobody is billed on: an unsubscribed, inactive or fully-cancelled plan edits
  # freely, which is what makes "create a new plan" a workable instruction.
  def refuse_narrowing_while_billed
    return unless changes.keys.intersect?(Billing::PlanAudit::ENTITLEMENT_COLUMNS)

    billed = subscriptions.where(status: BillingSubscription::BILLED_STATUSES).count
    return if billed.zero?

    narrowings = narrowed_entitlements
    return if narrowings.empty?

    errors.add(:base, narrowing_error_message(narrowings, billed))
  end

  # Each entry is one thing a subscriber would lose. Computed against the stored row, not the form, so it is
  # the same answer however the edit arrives -- console, Platform API or console-less script.
  def narrowed_entitlements
    withdrawn_features + tightened_limits + withdrawn_channels
  end

  def withdrawn_features
    (Array(features_was) - features).map { |name| "the feature #{name}" }
  end

  # A missing key means unlimited, so introducing a ceiling where there was none is a narrowing, and removing
  # one is not.
  def tightened_limits
    previous = (limits_was || {}).to_h
    limits.filter_map do |key, value|
      before = previous[key]
      next "a ceiling of #{value} on #{key} where there was none" if before.nil?
      next if value >= before.to_i

      "the #{key} ceiling, from #{before} to #{value}"
    end
  end

  # An empty list sells every channel (see #channel_included?), so going from empty to a list withdraws every
  # channel the list leaves out.
  def withdrawn_channels
    previous = Array(channel_entitlements_was)
    return [] if channel_entitlements.blank?
    return ['every channel the new list leaves out, because this plan previously sold all of them'] if previous.blank?

    (previous - channel_entitlements).map { |type| "the channel #{type}" }
  end

  def narrowing_error_message(narrowings, billed)
    "cannot be narrowed while #{billed} #{'account'.pluralize(billed)} #{billed == 1 ? 'is' : 'are'} billed on " \
      "this plan: it would withdraw #{narrowings.to_sentence} mid-period. Create a new plan with the intended " \
      'entitlements and move those accounts to it, or grant a per-account override for an exception. Widening ' \
      'this plan -- adding features, raising or removing a ceiling, selling more channels -- is allowed.'
  end

  def sync_subscribers_features
    Billing::FeatureSync.sync_plan!(self)
  end
end
