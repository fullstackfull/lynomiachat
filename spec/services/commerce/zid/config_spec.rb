require 'rails_helper'

RSpec.describe Commerce::Zid::Config do
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

  it 'keeps Zid off until a super admin turns it on' do
    expect(described_class.enabled?).to be(false)
    expect(Commerce::Providers.enabled).to eq(%w[woocommerce])

    configure('ZID_ENABLED', true)

    expect(described_class.enabled?).to be(true)
    expect(Commerce::Providers.enabled).to eq(%w[woocommerce zid])
  end

  it 'fails loudly when a required value is missing' do
    expect { described_class.client_id }.to raise_error(KeyError, 'ZID_CLIENT_ID is not configured')
    expect { described_class.client_secret }.to raise_error(KeyError, 'ZID_CLIENT_SECRET is not configured')
  end

  it 'derives the registered callback URL from the installation URL' do
    with_modified_env(FRONTEND_URL: 'https://app.lynomia.test') do
      expect(described_class.redirect_uri).to eq('https://app.lynomia.test/commerce/zid/callback')
    end
  end
end
