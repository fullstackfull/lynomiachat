# Lynomia Commerce refuses to store credentials without Active Record encryption. Commerce specs switch encryption on
# with throwaway keys for the example only (the rest of the suite keeps its own configuration).
RSpec.shared_context 'with commerce encryption' do
  around do |example|
    keys = {
      primary_key: 'commerce-spec-primary-key-0123456789',
      deterministic_key: 'commerce-spec-deterministic-key-0123',
      key_derivation_salt: 'commerce-spec-key-derivation-salt-01'
    }
    # The key readers raise when a key is not configured, which is the usual case in the test suite.
    previous = keys.keys.index_with do |key|
      ActiveRecord::Encryption.config.public_send(key)
    rescue ActiveRecord::Encryption::Errors::Configuration
      nil
    end

    ActiveRecord::Encryption.configure(**keys)
    with_modified_env(keys.transform_keys { |key| "ACTIVE_RECORD_ENCRYPTION_#{key.upcase}" }) { example.run }
  ensure
    ActiveRecord::Encryption.configure(**previous)
  end
end
