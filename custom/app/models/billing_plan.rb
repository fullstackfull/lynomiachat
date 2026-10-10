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

  def sync_subscribers_features
    Billing::FeatureSync.sync_plan!(self)
  end
end
