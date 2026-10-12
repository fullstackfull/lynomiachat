# frozen_string_literal: true

# Billing settings managed from the super admin, stored in installation_configs.
# Stored as locked configs so they never show up in the generic
# "Installation Configs" page (the Stripe keys are secrets).
class Billing::Settings
  KEYS = {
    stripe_secret_key: { name: 'BILLING_STRIPE_SECRET_KEY', type: :secret, default: nil },
    stripe_webhook_secret: { name: 'BILLING_STRIPE_WEBHOOK_SECRET', type: :secret, default: nil },
    stripe_tax_enabled: { name: 'BILLING_STRIPE_TAX_ENABLED', type: :boolean, default: false },
    trial_enabled: { name: 'BILLING_TRIAL_ENABLED', type: :boolean, default: true },
    trial_days: { name: 'BILLING_TRIAL_DAYS', type: :integer, default: 14 },
    trial_plan_id: { name: 'BILLING_TRIAL_PLAN_ID', type: :integer, default: nil },
    trial_once_per_user: { name: 'BILLING_TRIAL_ONCE_PER_USER', type: :boolean, default: true },
    grace_period_days: { name: 'BILLING_GRACE_PERIOD_DAYS', type: :integer, default: 3 },
    # Mobile app: kill switch for the pay button + deep link to come back to the app
    mobile_checkout_enabled: { name: 'BILLING_MOBILE_CHECKOUT_ENABLED', type: :boolean, default: false },
    mobile_return_url: { name: 'BILLING_MOBILE_RETURN_URL', type: :string, default: nil }
  }.freeze

  # See .masked: what a hint shows, and the floor under which it shows nothing.
  SHORT_VALUE_MASK = '••••••••'
  REVEALED_CHARACTERS = 11

  class << self
    # A direct read, deliberately not through GlobalConfig's Redis cache. These are commercial settings whose
    # staleness would mean charging or locking the wrong account, the read is a single indexed row, and the
    # repeated cost `enforced?` used to carry on the authorization path is removed where it actually repeated
    # -- BillingSubscription#billing_enforced? memoizes it per instance (docs/p11/07-security-performance.md §6).
    def get(key)
      definition = KEYS.fetch(key.to_sym)
      value = InstallationConfig.find_by(name: definition[:name])&.value
      value.nil? ? definition[:default] : cast(value, definition[:type])
    end

    def all
      KEYS.keys.index_with { |key| get(key) }
    end

    def update!(attrs)
      InstallationConfig.transaction do
        attrs.to_h.each do |key, raw|
          definition = KEYS[key.to_sym]
          next if definition.nil?
          # empty secret field in the form = keep the stored value
          next if definition[:type] == :secret && raw.blank?

          record = InstallationConfig.find_or_initialize_by(name: definition[:name])
          record.value = cast(raw, definition[:type])
          record.locked = true if record.respond_to?(:locked=)
          record.save!
        end
      end
    end

    def trial_enabled? = get(:trial_enabled)
    def trial_days = get(:trial_days).to_i
    def trial_once_per_user? = get(:trial_once_per_user)
    def grace_period_days = get(:grace_period_days).to_i
    def stripe_tax_enabled? = get(:stripe_tax_enabled)
    def stripe_secret_key = get(:stripe_secret_key)
    def stripe_webhook_secret = get(:stripe_webhook_secret)
    def mobile_checkout_enabled? = get(:mobile_checkout_enabled)
    def mobile_return_url = get(:mobile_return_url)

    def trial_plan
      id = get(:trial_plan_id)
      id && BillingPlan.find_by(id: id)
    end

    def stripe_configured?
      stripe_secret_key.present? && stripe_webhook_secret.present?
    end

    # Accounts are only locked once billing is set up (Stripe keys or a trial plan)
    def enforced?
      stripe_configured? || Billing::TrialStarter.configured?
    end

    # "sk_test...1234" for display, never the full secret.
    #
    # P-FINAL (docs/p-final/06-clean-code-review.md §5, answering P11's sixth known limitation): the hint shows
    # 11 characters, so for a value of 11 or fewer it showed the whole thing -- "abcdefgh" came back as
    # "abcdefg...efgh". A real Stripe key is far longer (`sk_live_` or `whsec_` plus 24 or more), which is why
    # P11 left it; but the value here is whatever an operator pasted, including a truncated one, and this hint
    # is rendered into the settings page and returned by Billing::ApiSerializer.settings. The floor is generic
    # rather than Stripe-shaped: reveal the prefix and suffix only when doing so still hides at least half the
    # value, and otherwise say nothing about it beyond that it is set. The bullet count is fixed, so a short
    # value does not disclose its length either.
    def masked(key)
      value = get(key)
      return nil if value.blank?
      return SHORT_VALUE_MASK if value.length < REVEALED_CHARACTERS * 2

      "#{value.first(7)}...#{value.last(4)}"
    end

    private

    def cast(value, type)
      case type
      when :boolean then ActiveModel::Type::Boolean.new.cast(value) || false
      when :integer then value.presence && value.to_i
      else value.to_s.strip.presence
      end
    end
  end
end
