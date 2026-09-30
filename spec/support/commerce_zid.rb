# The Zid app as a super admin sets it up (Super Admin → Settings → Zid), with Zid's hosts resolving to public addresses
# for the SSRF check. The global config cache and Zid's Redis keys are cleared around the example so nothing reaches
# other specs.
RSpec.shared_context 'with zid app' do
  let(:zid_client_secret) { 'zid-client-secret-for-specs' }

  around do |example|
    clear = lambda do
      GlobalConfig.clear_cache
      Redis::Alfred.scan_each(match: 'COMMERCE::ZID::*') { |key| Redis::Alfred.delete(key) }
    end
    clear.call
    with_modified_env(FRONTEND_URL: 'https://app.lynomia.test') { example.run }
  ensure
    clear.call
  end

  before do
    { 'ZID_ENABLED' => true, 'ZID_CLIENT_ID' => '4821', 'ZID_CLIENT_SECRET' => zid_client_secret }.each do |name, value|
      InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false)
    end
    GlobalConfig.clear_cache
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('oauth.zid.sa').and_return(['93.184.216.50'])
    allow(Resolv).to receive(:getaddresses).with('api.zid.sa').and_return(['93.184.216.51'])
  end
end
