# Lynomia Commerce refuses to store credentials without Active Record encryption. Commerce specs switch it on with
# throwaway keys for the example (ENV, so `Chatwoot.encryption_configured?` is true only inside it).
#
# The Active Record keys stay configured afterwards on purpose: models that declare
# `encrypts … if Chatwoot.encryption_configured?` and happen to be loaded inside such an example keep encrypting, and
# later examples must still find keys for them. Other specs keep seeing encryption as off, because that check reads ENV.
RSpec.shared_context 'with commerce encryption' do
  around do |example|
    keys = {
      primary_key: 'commerce-spec-primary-key-0123456789',
      deterministic_key: 'commerce-spec-deterministic-key-0123',
      key_derivation_salt: 'commerce-spec-key-derivation-salt-01'
    }
    ActiveRecord::Encryption.configure(**keys)
    with_modified_env(keys.transform_keys { |key| "ACTIVE_RECORD_ENCRYPTION_#{key.upcase}" }) { example.run }
  end
end
