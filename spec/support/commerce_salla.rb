# The Salla app as a super admin sets it up (Super Admin → Settings → Salla), with Salla's hosts resolving to public
# addresses for the SSRF check. The global config cache and Salla's Redis keys are cleared around the example so nothing
# reaches other specs.
RSpec.shared_context 'with salla app' do
  let(:salla_client_secret) { 'salla-client-secret-for-specs' }
  let(:salla_webhook_secret) { 'salla-webhook-secret-for-specs' }

  around do |example|
    clear = lambda do
      GlobalConfig.clear_cache
      Redis::Alfred.scan_each(match: 'COMMERCE::SALLA::*') { |key| Redis::Alfred.delete(key) }
    end
    clear.call
    example.run
  ensure
    clear.call
  end

  before do
    { 'SALLA_ENABLED' => true, 'SALLA_APP_ID' => '1234567890', 'SALLA_CLIENT_ID' => 'salla-client-id-for-specs',
      'SALLA_CLIENT_SECRET' => salla_client_secret, 'SALLA_WEBHOOK_SECRET' => salla_webhook_secret }.each do |name, value|
      InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false)
    end
    GlobalConfig.clear_cache
    allow(Resolv).to receive(:getaddresses).with('accounts.salla.sa').and_return(['93.184.216.40'])
    allow(Resolv).to receive(:getaddresses).with('api.salla.dev').and_return(['93.184.216.41'])
  end
end
