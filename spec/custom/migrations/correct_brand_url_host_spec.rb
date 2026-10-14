require 'rails_helper'
require Rails.root.join('custom/db/migrate/20261014120000_correct_brand_url_host.rb')

# The "Powered by" host was unreachable in production: BRAND_URL and WIDGET_BRAND_URL both pointed at
# www.chat.lynomia.com, which has no DNS record. Correcting config/installation_config.yml fixes only a fresh
# install, because ConfigLoader runs with `reconcile_only_new: true` and never overwrites an existing row
# (lib/config_loader.rb:3, :50-52) -- so this migration is the half that repairs a live installation, and these
# examples pin the two properties that make it safe to run there: it is conditional, and it is reversible.
describe CorrectBrandUrlHost do
  subject(:migration) { described_class.new }

  let(:wrong) { 'https://www.chat.lynomia.com' }
  let(:right) { 'https://chat.lynomia.com' }

  before { migration.verbose = false }

  def config_for(name)
    InstallationConfig.find_by(name: name)
  end

  describe 'up' do
    it 'corrects both brand hosts when they still hold the unreachable value' do
      InstallationConfig.find_or_initialize_by(name: 'BRAND_URL').update!(value: wrong)
      InstallationConfig.find_or_initialize_by(name: 'WIDGET_BRAND_URL').update!(value: wrong)

      migration.up

      expect([config_for('BRAND_URL').value, config_for('WIDGET_BRAND_URL').value]).to eq([right, right])
    end

    # The one property that makes this safe to run on a live installation: an operator who deliberately set
    # their own brand host keeps it.
    it 'leaves an operator-chosen value alone' do
      InstallationConfig.find_or_initialize_by(name: 'BRAND_URL').update!(value: 'https://brand.example.com')

      migration.up

      expect(config_for('BRAND_URL').value).to eq('https://brand.example.com')
    end

    it 'is idempotent' do
      InstallationConfig.find_or_initialize_by(name: 'BRAND_URL').update!(value: wrong)

      migration.up
      migration.up

      expect(config_for('BRAND_URL').value).to eq(right)
    end
  end

  describe 'down' do
    it 'restores the previous value, so the migration is reversible' do
      InstallationConfig.find_or_initialize_by(name: 'BRAND_URL').update!(value: wrong)
      migration.up

      migration.down

      expect(config_for('BRAND_URL').value).to eq(wrong)
    end
  end
end
