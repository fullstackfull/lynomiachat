# The Salla app as a super admin sets it up (Super Admin → Settings → Salla). The global config cache is cleared around
# the example so these values never reach other specs.
RSpec.shared_context 'with salla app' do
  let(:salla_client_secret) { 'salla-client-secret-for-specs' }
  let(:salla_webhook_secret) { 'salla-webhook-secret-for-specs' }

  around do |example|
    GlobalConfig.clear_cache
    example.run
  ensure
    GlobalConfig.clear_cache
  end

  before do
    { 'SALLA_ENABLED' => true, 'SALLA_APP_ID' => '1234567890', 'SALLA_CLIENT_ID' => 'salla-client-id-for-specs',
      'SALLA_CLIENT_SECRET' => salla_client_secret, 'SALLA_WEBHOOK_SECRET' => salla_webhook_secret }.each do |name, value|
      InstallationConfig.where(name: name).first_or_initialize.update!(value: value, locked: false)
    end
    GlobalConfig.clear_cache
  end
end
