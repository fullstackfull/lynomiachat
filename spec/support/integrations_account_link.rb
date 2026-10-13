RSpec.shared_context 'with account link codes' do
  # Redis is a MockRedis in test and is NEVER flushed between examples (spec/rails_helper.rb resets only
  # Current), while use_transactional_fixtures rolls the Postgres rows back underneath it. A key prefix that
  # nothing clears therefore leaks into later examples and makes the suite order-dependent -- a code minted for
  # account 1 in one example is still readable when the next example creates a different account 1. The
  # commerce contexts each clear their own prefix for exactly this reason; this clears ours.
  around do |example|
    clear = lambda do
      Redis::Alfred.scan_each(match: 'INTEGRATIONS::ACCOUNT_LINK::*') { |key| Redis::Alfred.delete(key) }
    end

    clear.call
    example.run
  ensure
    clear.call
  end
end
