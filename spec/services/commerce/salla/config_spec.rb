require 'rails_helper'

RSpec.describe Commerce::Salla::Config do
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

  it 'keeps Salla off until a super admin turns it on' do
    expect(described_class.enabled?).to be(false)
    expect(Commerce::Providers.enabled).to eq(%w[woocommerce])

    configure('SALLA_ENABLED', true)

    expect(described_class.enabled?).to be(true)
    expect(Commerce::Providers.enabled).to eq(%w[woocommerce salla])
  end

  it 'builds the official install link from the app id' do
    configure('SALLA_APP_ID', '1234567890')

    expect(described_class.install_url).to eq('https://s.salla.sa/apps/install/1234567890')
  end

  it 'fails loudly when a required value is missing' do
    expect { described_class.client_secret }.to raise_error(KeyError, 'SALLA_CLIENT_SECRET is not configured')
    expect { described_class.install_url }.to raise_error(KeyError, 'SALLA_APP_ID is not configured')
  end

  it 'has no webhook secret until one is set, so nothing can be verified against an empty key' do
    expect(described_class.webhook_secret).to be_nil

    configure('SALLA_WEBHOOK_SECRET', 'webhook-secret')

    expect(described_class.webhook_secret).to eq('webhook-secret')
  end
end
