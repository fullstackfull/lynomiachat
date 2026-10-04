require 'rails_helper'

describe SuperAdmin::BrandingHelper do
  let(:installation_name) { InstallationConfig.where(name: 'INSTALLATION_NAME').first_or_create(value: 'Chatwoot') }
  let(:support_url) { InstallationConfig.where(name: 'SUPPORT_URL').first_or_create(value: '') }

  describe '#application_title' do
    it 'uses the installation name instead of the Rails application module name' do
      installation_name.update!(value: 'Acme Desk')
      GlobalConfig.clear_cache

      expect(helper.application_title).to eq('Acme Desk')
    end
  end

  describe '#brand_support_url' do
    it 'keeps the upstream destination on an installation that has not been rebranded' do
      installation_name.update!(value: 'Chatwoot')
      GlobalConfig.clear_cache

      expect(helper.brand_support_url('https://upstream.example/community')).to eq('https://upstream.example/community')
    end

    it 'uses the configured support link on a branded installation' do
      installation_name.update!(value: 'Acme Desk')
      support_url.update!(value: 'https://help.acme.example')
      GlobalConfig.clear_cache

      expect(helper.brand_support_url('https://upstream.example/community')).to eq('https://help.acme.example')
    end

    it 'returns nil on a branded installation with no support link, so the caller renders nothing' do
      installation_name.update!(value: 'Acme Desk')
      support_url.update!(value: '')
      GlobalConfig.clear_cache

      expect(helper.brand_support_url('https://upstream.example/community')).to be_nil
    end
  end
end
