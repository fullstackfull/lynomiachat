# Installation switches for order actions and sales recovery (docs/commerce/28-commerce-actions-architecture.md §switches).
# Each is read from Super Admin → Settings → Lynomia Commerce, else from ENV, else its default.
#
#   COMMERCE_ACTIONS_ENABLED    kill switch for every order action (default on)
#   <PROVIDER>_ACTIONS_ENABLED  one provider's actions (default on for WooCommerce only)
#   COMMERCE_RECOVERY_ENABLED   kill switch for abandoned carts and recovery messages (default on)
#   <PROVIDER>_RECOVERY_ENABLED one provider's abandoned carts (default off; WooCommerce has none)
#
# A provider's actions or carts are never on while its read switch (SALLA_ENABLED, …) is off. Providers that have not
# passed a real UAT (PRE_UAT) stay off whatever the switches say, unless the ENV-only COMMERCE_ALLOW_PRE_UAT_PROVIDERS is
# set: staging and simulated E2E runs only, never production. A provider leaves PRE_UAT through a reviewed code change.
module Commerce::Switches
  ACTION_KEYS = { 'woocommerce' => 'WOOCOMMERCE_ACTIONS_ENABLED', 'salla' => 'SALLA_ACTIONS_ENABLED', 'zid' => 'ZID_ACTIONS_ENABLED',
                  'shopify' => 'SHOPIFY_COMMERCE_ACTIONS_ENABLED' }.freeze
  RECOVERY_KEYS = { 'salla' => 'SALLA_RECOVERY_ENABLED', 'zid' => 'ZID_RECOVERY_ENABLED', 'shopify' => 'SHOPIFY_COMMERCE_RECOVERY_ENABLED' }.freeze
  PRE_UAT = { actions: %w[salla zid shopify], recovery: %w[salla zid shopify] }.freeze
  DEFAULT_RECOVERY_COOLDOWN_HOURS = 24

  def self.actions_enabled? = flag('COMMERCE_ACTIONS_ENABLED', default: true)

  def self.provider_actions_enabled?(provider)
    actions_enabled? && Commerce::Providers.enabled?(provider) && uat_cleared?(:actions, provider) &&
      flag(ACTION_KEYS.fetch(provider), default: provider == 'woocommerce')
  end

  def self.recovery_enabled? = flag('COMMERCE_RECOVERY_ENABLED', default: true)

  def self.provider_recovery_enabled?(provider)
    key = RECOVERY_KEYS[provider]
    key.present? && recovery_enabled? && Commerce::Providers.enabled?(provider) && uat_cleared?(:recovery, provider) && flag(key, default: false)
  end

  # Hours before the same cart can be sent another recovery message (an administrator can override it once).
  def self.recovery_cooldown
    hours = Integer(GlobalConfig.get_value('COMMERCE_RECOVERY_COOLDOWN_HOURS').to_s, 10, exception: false)
    (hours&.positive? ? hours : DEFAULT_RECOVERY_COOLDOWN_HOURS).hours
  end

  def self.uat_cleared?(feature, provider)
    PRE_UAT.fetch(feature).exclude?(provider) || ActiveModel::Type::Boolean.new.cast(ENV.fetch('COMMERCE_ALLOW_PRE_UAT_PROVIDERS', false)) == true
  end

  def self.flag(name, default:)
    value = GlobalConfig.get_value(name)
    value = ENV.fetch(name, default) if value.nil?
    ActiveModel::Type::Boolean.new.cast(value) == true
  end

  private_class_method :uat_cleared?, :flag
end
