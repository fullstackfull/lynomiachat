require 'rails_helper'

# Installation switches for order actions and abandoned carts (docs/commerce/28-commerce-actions-architecture.md §switches).
RSpec.describe Commerce::Switches do
  around do |example|
    GlobalConfig.clear_cache
    example.run
  ensure
    GlobalConfig.clear_cache
  end

  let(:configure) do
    lambda do |values|
      values.each { |name, value| InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false) }
      GlobalConfig.clear_cache
    end
  end

  it 'offers WooCommerce actions by default and keeps the other providers off' do
    expect(described_class.actions_enabled?).to be(true)
    expect(described_class.provider_actions_enabled?('woocommerce')).to be(true)
    expect(%w[salla zid shopify].map { |provider| described_class.provider_actions_enabled?(provider) }).to all(be(false))
    expect(%w[woocommerce salla zid shopify].map { |provider| described_class.provider_recovery_enabled?(provider) }).to all(be(false))
  end

  it 'stops every provider with the kill switches' do
    configure.call('COMMERCE_ACTIONS_ENABLED' => false, 'COMMERCE_RECOVERY_ENABLED' => false)

    expect(described_class.provider_actions_enabled?('woocommerce')).to be(false)
    expect(described_class.recovery_enabled?).to be(false)
  end

  it 'never turns a provider\'s actions or carts on while its read switch is off' do
    configure.call('SALLA_ACTIONS_ENABLED' => true, 'SALLA_RECOVERY_ENABLED' => true)

    with_modified_env(COMMERCE_ALLOW_PRE_UAT_PROVIDERS: 'true') do
      expect(described_class.provider_actions_enabled?('salla')).to be(false)
      expect(described_class.provider_recovery_enabled?('salla')).to be(false)

      configure.call('SALLA_ENABLED' => true)
      expect(described_class.provider_actions_enabled?('salla')).to be(true)
      expect(described_class.provider_recovery_enabled?('salla')).to be(true)
    end
  end

  it 'keeps providers that have not passed a real UAT off whatever Super Admin says, unless the ENV-only override is set' do
    configure.call('ZID_ENABLED' => true, 'ZID_ACTIONS_ENABLED' => true, 'ZID_RECOVERY_ENABLED' => true,
                   'SHOPIFY_COMMERCE_ENABLED' => true, 'SHOPIFY_COMMERCE_ACTIONS_ENABLED' => true)

    expect(described_class.provider_actions_enabled?('zid')).to be(false)
    expect(described_class.provider_recovery_enabled?('zid')).to be(false)
    expect(described_class.provider_actions_enabled?('shopify')).to be(false)

    with_modified_env(COMMERCE_ALLOW_PRE_UAT_PROVIDERS: 'true') do
      expect(described_class.provider_actions_enabled?('zid')).to be(true)
      expect(described_class.provider_actions_enabled?('shopify')).to be(true)
    end
  end

  it 'has no abandoned carts for WooCommerce, whose core has no merchant-wide cart API' do
    configure.call('COMMERCE_RECOVERY_ENABLED' => true)

    expect(described_class.provider_recovery_enabled?('woocommerce')).to be(false)
  end

  it 'reads the recovery cooldown in hours, 24 by default' do
    expect(described_class.recovery_cooldown).to eq(24.hours)

    configure.call('COMMERCE_RECOVERY_COOLDOWN_HOURS' => 6)
    expect(described_class.recovery_cooldown).to eq(6.hours)
  end
end
