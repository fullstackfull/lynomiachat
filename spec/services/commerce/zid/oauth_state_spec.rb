require 'rails_helper'

RSpec.describe Commerce::Zid::OauthState do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:issued) { described_class.issue(account: account, user: admin) }

  it 'names the account and administrator it was issued for, once, to the browser that started it' do
    expect(described_class.consume(issued.state, issued.nonce)).to eq('account_id' => account.id, 'user_id' => admin.id)
    expect(described_class.consume(issued.state, issued.nonce)).to be_nil
  end

  it 'is refused from another browser or without the browser cookie' do
    expect(described_class.consume(issued.state, SecureRandom.urlsafe_base64(32))).to be_nil
    expect(described_class.consume(issued.state, nil)).to be_nil
    expect(described_class.consume(issued.state, issued.nonce)).to be_present
  end

  it 'expires after ten minutes' do
    state = issued
    travel 11.minutes do
      expect(described_class.consume(state.state, state.nonce)).to be_nil
    end
  end

  it 'refuses a forged or tampered state' do
    data = { 'nonce' => issued.nonce, 'account_id' => create(:account).id, 'user_id' => admin.id }
    forged = ActiveSupport::MessageVerifier.new('not-the-app-secret').generate(data, purpose: 'commerce_zid_oauth', expires_in: 10.minutes)
    tampered = issued.state.sub(/.\z/) { |char| char == 'a' ? 'b' : 'a' }

    [forged, tampered, 'garbage', nil].each { |state| expect(described_class.consume(state, issued.nonce)).to be_nil }
  end
end
