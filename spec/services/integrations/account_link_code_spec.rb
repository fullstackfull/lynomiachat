require 'rails_helper'

RSpec.describe Integrations::AccountLinkCode do
  include_context 'with account link codes'

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:platform_app) { create(:platform_app) }

  def stored_code_keys
    keys = []
    Redis::Alfred.scan_each(match: 'INTEGRATIONS::ACCOUNT_LINK::CODE::*') { |key| keys << key }
    keys
  end

  describe '.create' do
    it 'stores only a digest, never the code the merchant was shown' do
      result = described_class.create(account: account, user: user, platform_app: platform_app)

      expect(stored_code_keys.sole).not_to include(result[:code].delete('-'))
      expect(Redis::Alfred.get(stored_code_keys.sole))
        .to eq({ account_id: account.id, user_id: user.id, platform_app_id: platform_app.id }.to_json)
      expect(Redis::Alfred.ttl(stored_code_keys.sole)).to be_between(3590, 3600)
    end

    it 'issues 80 bits from an alphabet with no look-alike characters' do
      code = described_class.create(account: account, user: user, platform_app: platform_app)[:code].delete('-')

      expect(code.length).to eq(described_class::LENGTH)
      expect(code).to match(/\A[#{described_class::ALPHABET}]+\z/o)
      expect(code).not_to match(/[01OI]/)
    end

    it 'revokes the account previous code so only one is ever live' do
      first = described_class.create(account: account, user: user, platform_app: platform_app)
      described_class.create(account: account, user: user, platform_app: platform_app)

      expect(stored_code_keys.length).to eq(1)
      expect(described_class.redeem(first[:code], platform_app: platform_app)).to eq(:unknown)
    end

    # Read-then-delete-then-write left TWO live codes when two mints raced, with only one of them
    # named by progress -- so the displaced one could not be deleted by any later mint and stayed
    # redeemable for its full hour, while the merchant believed regenerating had killed it.
    it 'leaves exactly one live code when two mints interleave' do
      inner = nil
      interleaved = false

      # Interleave at the point the race matters: the outer mint has written its code key but has not yet
      # swapped progress, and a second mint runs to completion inside that gap.
      allow(Redis::Alfred).to receive(:setex).and_wrap_original do |original, key, value, expiry|
        result = original.call(key, value, expiry)
        if key.start_with?('INTEGRATIONS::ACCOUNT_LINK::CODE::') && !interleaved
          interleaved = true
          inner = described_class.create(account: account, user: user, platform_app: platform_app)
        end
        result
      end

      outer = described_class.create(account: account, user: user, platform_app: platform_app)

      expect(interleaved).to be(true)
      # One key, not two. Before the GETSET swap this left both live, with progress naming only one -- so the
      # other could never be deleted by a later mint and stayed redeemable for its full hour.
      expect(stored_code_keys.length).to eq(1)

      # The survivor is the one progress names, and the displaced one is gone. The outer mint swapped progress
      # last, so it is the survivor; naming which is the point, because "one of them survived" would pass even
      # if the survivor were the one progress had forgotten.
      expect(described_class.redeem(inner[:code], platform_app: platform_app)).to eq(:unknown)
      expect(described_class.redeem(outer[:code], platform_app: platform_app))
        .to eq({ 'account_id' => account.id, 'user_id' => user.id, 'platform_app_id' => platform_app.id })
      expect(stored_code_keys).to be_empty
    end

    it 'records who issued it' do
      described_class.create(account: account, user: user, platform_app: platform_app)

      log = Custom::AuditLog.where(associated: account, comment: 'integrations.account_link.code_issued').sole
      expect(log.user_id).to eq(user.id)
    end
  end

  describe '.redeem' do
    it 'returns the account and user the code was minted by' do
      code = described_class.create(account: account, user: user, platform_app: platform_app)[:code]

      expect(described_class.redeem(code, platform_app: platform_app))
        .to eq({ 'account_id' => account.id, 'user_id' => user.id, 'platform_app_id' => platform_app.id })
    end

    it 'works exactly once' do
      code = described_class.create(account: account, user: user, platform_app: platform_app)[:code]

      expect(described_class.redeem(code, platform_app: platform_app)).to be_a(Hash)
      expect(described_class.redeem(code, platform_app: platform_app)).to eq(:unknown)
      expect(stored_code_keys).to be_empty
    end

    it 'ignores case, spaces and dashes, because a merchant types it' do
      code = described_class.create(account: account, user: user, platform_app: platform_app)[:code]

      expect(described_class.redeem("  #{code.downcase.delete('-')}  ", platform_app: platform_app)).to be_a(Hash)
    end

    it 'refuses a code that has expired' do
      code = described_class.create(account: account, user: user, platform_app: platform_app)[:code]

      travel(described_class::TTL + 1.minute) do
        expect(described_class.redeem(code, platform_app: platform_app)).to eq(:unknown)
      end
    end

    it 'refuses a blank or unknown string without raising' do
      expect(described_class.redeem(nil, platform_app: platform_app)).to eq(:unknown)
      expect(described_class.redeem('', platform_app: platform_app)).to eq(:unknown)
      expect(described_class.redeem('AAAABBBBCCCCDDDD', platform_app: platform_app)).to eq(:unknown)
    end

    # The earlier version of this minted for the other account, then minted mine, then redeemed MINE -- so
    # with any last-write-wins storage bug mine was written second and still read back correctly. Proven
    # vacuous by collapsing code_key to one shared constant: that version still passed while redeem(A)
    # returned account B. Redeeming the OTHER account's code is the only form that observes the leak.
    it 'does not leak one account code to another account' do
      other_account = create(:account)
      other_user = create(:user, account: other_account, role: :administrator)
      other_code = described_class.create(account: other_account, user: other_user, platform_app: platform_app)[:code]

      mine = described_class.create(account: account, user: user, platform_app: platform_app)[:code]

      expect(described_class.redeem(other_code, platform_app: platform_app))
        .to eq({ 'account_id' => other_account.id, 'user_id' => other_user.id, 'platform_app_id' => platform_app.id })
      expect(described_class.redeem(mine, platform_app: platform_app))
        .to eq({ 'account_id' => account.id, 'user_id' => user.id, 'platform_app_id' => platform_app.id })
    end
  end

  describe 'the audience' do
    it 'refuses a code minted for a different integration, and does not consume it' do
      other_app = create(:platform_app)
      code = described_class.create(account: account, user: user, platform_app: platform_app)[:code]

      expect(described_class.redeem(code, platform_app: other_app)).to eq(:wrong_app)

      # STILL LIVE. Burning it here would let any app on the installation destroy a merchant's code by
      # guessing at it, and the merchant would be told their own code was invalid.
      expect(described_class.redeem(code, platform_app: platform_app))
        .to eq({ 'account_id' => account.id, 'user_id' => user.id, 'platform_app_id' => platform_app.id })
    end

    it 'records the intended integration so the merchant can see who it is for' do
      described_class.create(account: account, user: user, platform_app: platform_app)

      expect(described_class.status(account)[:intended_app]).to eq(platform_app.name)
    end

    # No silent fallback: a payload with no audience matches nobody, which is what a code from before
    # audiences existed looks like.
    it 'refuses an audienceless code rather than letting anyone have it' do
      described_class.create(account: account, user: user, platform_app: platform_app)
      key = stored_code_keys.sole
      Redis::Alfred.setex(key, { account_id: account.id, user_id: user.id }.to_json, 1.hour)

      expect(described_class.redeem('IGNORED', platform_app: platform_app)).to eq(:unknown)
    end
  end

  describe '.status' do
    it 'reports none, then waiting, then claimed' do
      expect(described_class.status(account)).to eq({ status: 'none' })

      code = described_class.create(account: account, user: user, platform_app: platform_app)[:code]
      expect(described_class.status(account)[:status]).to eq('waiting')

      described_class.redeem(code, platform_app: platform_app)
      expect(described_class.status(account)[:status]).to eq('claimed')
    end

    it 'reports expired once the window has passed' do
      described_class.create(account: account, user: user, platform_app: platform_app)

      travel(described_class::TTL + 1.minute) do
        expect(described_class.status(account)[:status]).to eq('expired')
      end
    end
  end
end
