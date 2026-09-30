require 'rails_helper'

RSpec.describe Commerce::Salla::ConnectionCode do
  include_context 'with salla app'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  def stored_code_keys
    keys = []
    Redis::Alfred.scan_each(match: 'COMMERCE::SALLA::CONNECTION_CODE::*') { |key| keys << key }
    keys
  end

  it 'issues an 80-bit code shown once, keeping only its HMAC for one hour' do
    result = described_class.create(account: account, user: admin)

    expect(result).to include(install_url: 'https://s.salla.sa/apps/install/1234567890')
    expect(result[:code]).to match(/\A[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){3}\z/)
    expect(stored_code_keys.sole).not_to include(result[:code].delete('-'))
    expect(Redis::Alfred.get(stored_code_keys.sole)).to eq({ account_id: account.id, user_id: admin.id }.to_json)
    expect(Redis::Alfred.ttl(stored_code_keys.sole)).to be_between(3590, 3600)
    expect(described_class.status(account)).to eq(status: 'waiting', expires_at: result[:expires_at])
  end

  it 'redeems a code once, whatever the case, spaces or dashes the merchant typed' do
    code = described_class.create(account: account, user: admin)[:code]

    expect(described_class.redeem(" #{code.downcase.delete('-')} ")).to eq('account_id' => account.id, 'user_id' => admin.id)
    expect(described_class.status(account)).to include(status: 'claimed')
    expect(described_class.redeem(code)).to be_nil
  end

  it 'replaces the previous code of the account' do
    first = described_class.create(account: account, user: admin)[:code]
    second = described_class.create(account: account, user: admin)[:code]

    expect(described_class.redeem(first)).to be_nil
    expect(described_class.redeem(second)).to include('account_id' => account.id)
  end

  it 'shows an unused code as expired after an hour' do
    described_class.create(account: account, user: admin)

    travel(described_class::TTL + 1.minute) { expect(described_class.status(account)).to include(status: 'expired') }
  end

  it 'keeps accounts apart' do
    other = create(:account)
    code = described_class.create(account: account, user: admin)[:code]

    described_class.redeem(code)

    expect(described_class.status(other)).to eq(status: 'none')
  end
end
