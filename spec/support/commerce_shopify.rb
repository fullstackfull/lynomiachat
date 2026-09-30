# The Lynomia Commerce Shopify app as a super admin sets it up (Super Admin → Settings → Shopify Commerce), with every
# myshopify.com host resolving to a public address for the SSRF check. The global config cache and the Commerce Shopify
# Redis keys are cleared around the example so nothing reaches other specs.
RSpec.shared_context 'with shopify commerce app' do
  let(:shopify_client_secret) { 'shopify-commerce-secret-for-specs' }

  around do |example|
    clear = lambda do
      GlobalConfig.clear_cache
      Redis::Alfred.scan_each(match: 'COMMERCE::SHOPIFY::*') { |key| Redis::Alfred.delete(key) }
    end
    clear.call
    with_modified_env(FRONTEND_URL: 'https://app.lynomia.test') { example.run }
  ensure
    clear.call
  end

  before do
    { 'SHOPIFY_COMMERCE_ENABLED' => true, 'SHOPIFY_COMMERCE_CLIENT_ID' => 'commerce-client-id',
      'SHOPIFY_COMMERCE_CLIENT_SECRET' => shopify_client_secret }.each do |name, value|
      InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false)
    end
    GlobalConfig.clear_cache
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with(/\.myshopify\.com\z/).and_return(['93.184.216.60'])
  end
end
