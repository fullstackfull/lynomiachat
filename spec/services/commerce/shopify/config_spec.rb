require 'rails_helper'

RSpec.describe Commerce::Shopify::Config do
  around do |example|
    GlobalConfig.clear_cache
    example.run
  ensure
    GlobalConfig.clear_cache
  end

  def configure(name, value)
    InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false)
    GlobalConfig.clear_cache
  end

  it 'keeps Shopify Commerce off until a super admin turns it on' do
    expect(described_class.enabled?).to be(false)
    expect(Commerce::Providers.enabled).to eq(%w[woocommerce])

    configure('SHOPIFY_COMMERCE_ENABLED', true)

    expect(described_class.enabled?).to be(true)
    expect(Commerce::Providers.enabled).to eq(%w[woocommerce shopify])
  end

  it 'is a switch of its own: the legacy Shopify integration setting does not turn it on' do
    configure('ENABLE_SHOPIFY_INTEGRATION', true)
    configure('SHOPIFY_CLIENT_ID', 'legacy-client-id')
    configure('SHOPIFY_CLIENT_SECRET', 'legacy-client-secret')

    expect(described_class.enabled?).to be(false)
    expect { described_class.client_id }.to raise_error(KeyError, 'SHOPIFY_COMMERCE_CLIENT_ID is not configured')
    expect { described_class.client_secret }.to raise_error(KeyError, 'SHOPIFY_COMMERCE_CLIENT_SECRET is not configured')
  end

  it 'derives the allowed redirect URL from the installation URL' do
    with_modified_env(FRONTEND_URL: 'https://app.lynomia.test') do
      expect(described_class.redirect_uri).to eq('https://app.lynomia.test/commerce/shopify/callback')
    end
  end

  it 'pins the Admin API version and requests read-only scopes' do
    expect(described_class::API_VERSION).to eq('2026-07')
    expect(described_class::SCOPES).to eq(%w[read_customers read_orders])
  end
end
