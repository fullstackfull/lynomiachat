require 'rails_helper'

RSpec.describe Analytics::FilterSet do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: other_account) }

  def build(family: :conversations, params: {})
    described_class.new(account: account, family: family, params: params)
  end

  def expect_rejected(params, as:, family: :conversations)
    expect { build(family: family, params: params) }
      .to(raise_error { |error| expect(error.class.name).to eq("CustomExceptions::Analytics::#{as}") })
  end

  describe 'tenant isolation' do
    it 'accepts an inbox this account owns' do
      expect(build(params: { inbox_id: inbox.id })[:inbox_id]).to eq(inbox.id)
    end

    it "refuses another account's inbox" do
      expect_rejected({ inbox_id: other_inbox.id }, as: 'UnknownFilterValue')
    end

    it "refuses another account's team" do
      team = create(:team, account: other_account)
      expect_rejected({ team_id: team.id }, as: 'UnknownFilterValue')
    end

    it "refuses another account's campaign" do
      campaign = create(:campaign, account: other_account, inbox: other_inbox)
      expect_rejected({ campaign_id: campaign.id }, family: :campaigns, as: 'UnknownFilterValue')
    end

    it "refuses another account's automation rule" do
      rule = create(:automation_rule, account: other_account)
      expect_rejected({ automation_rule_id: rule.id }, family: :automations, as: 'UnknownFilterValue')
    end

    it 'refuses an agent who is not a member of this account, even though users are global' do
      outsider = create(:user)
      create(:account_user, account: other_account, user: outsider)

      expect_rejected({ agent_id: outsider.id }, as: 'UnknownFilterValue')
    end

    it 'accepts an agent who is a member of this account' do
      member = create(:user)
      create(:account_user, account: account, user: member)

      expect(build(params: { agent_id: member.id })[:agent_id]).to eq(member.id)
    end

    it 'refuses a channel type this account has no inbox for' do
      inbox
      expect_rejected({ channel_type: 'Channel::Telegram' }, as: 'UnknownFilterValue')
    end

    it 'accepts a channel type this account does have' do
      expect(build(params: { channel_type: inbox.channel_type })[:channel_type]).to eq(inbox.channel_type)
    end

    it 'refuses a non-numeric id rather than coercing it to 0' do
      expect_rejected({ inbox_id: 'not-a-number' }, as: 'UnknownFilterValue')
    end

    it 'refuses a SQL fragment passed as an id' do
      expect_rejected({ inbox_id: '1 OR 1=1' }, as: 'UnknownFilterValue')
    end
  end

  describe 'filter support per family' do
    it 'refuses a filter the family has no meaning for, rather than ignoring it' do
      expect_rejected({ provider: 'woocommerce' }, family: :conversations, as: 'UnsupportedFilter')
    end

    it 'accepts provider for the commerce family' do
      expect(build(family: :commerce, params: { provider: 'woocommerce' })[:provider]).to eq('woocommerce')
    end

    it 'refuses an unknown provider' do
      expect_rejected({ provider: 'etsy' }, family: :commerce, as: 'UnknownFilterValue')
    end

    it 'refuses an unknown family' do
      expect { build(family: :nonsense) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::UnknownMetricFamily') })
    end

    it 'ignores a key that is not an analytics filter at all' do
      expect(build(params: { order_by: 'name', inbox_id: inbox.id }).values.keys).to eq([:inbox_id])
    end

    it 'treats a blank filter as absent rather than as an unsupported one' do
      expect(build(family: :conversations, params: { provider: '' }).values).to be_empty
    end
  end

  describe '#to_meta' do
    it 'reports only the resolved filters' do
      expect(build(params: { inbox_id: inbox.id }).to_meta).to eq(inbox_id: inbox.id)
    end
  end
end
