require 'rails_helper'

RSpec.describe Operations::ComputedSignals do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  def component(key)
    described_class.new.call.find { |item| item.key == key }
  end

  # The rule the console exists to keep: an area with no source at all is `unknown` with a reason, never green.
  describe 'areas with no source' do
    it 'reports unknown and says why' do
      %i[whatsapp_delivery whatsapp_templates campaigns commerce].each do |key|
        found = component(key)
        expect(found.status).to eq(Operations::Health::UNKNOWN), "#{key} should be unknown"
        expect(found.source_class).to eq('absent')
        expect(found.reason).to be_present
      end
    end
  end

  describe 'whatsapp delivery' do
    let(:whatsapp) do
      create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
    end
    let(:inbox) { create(:inbox, account: account, channel: whatsapp) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    it 'counts failed outgoing sends in the window and stays healthy below the warning line' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       status: :failed)

      found = component(:whatsapp_delivery)
      expect(found.status).to eq(Operations::Health::HEALTHY)
      expect(found.detail[:size]).to eq(1)
      expect(found.detail[:warning_at]).to eq(described_class::WHATSAPP_FAILURES_WARNING)
    end

    it 'ignores a failure outside the window, an inbound message and a private note' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       status: :failed, created_at: 8.days.ago)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                       status: :failed)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       status: :failed, private: true)

      expect(component(:whatsapp_delivery).detail[:size]).to eq(0)
    end

    it 'crosses to warning at the stated threshold' do
      stub_const("#{described_class}::WHATSAPP_FAILURES_WARNING", 2)
      2.times do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                         status: :failed)
      end

      expect(component(:whatsapp_delivery).status).to eq(Operations::Health::WARNING)
    end
  end

  describe 'campaigns' do
    let(:inbox) { create(:inbox, account: account) }
    let(:campaign) { create(:campaign, account: account, inbox: inbox) }

    def recipient(failed:, created_at: 1.hour.ago)
      CampaignRecipient.create!(account: account, campaign: campaign, contact: create(:contact, account: account),
                                inbox: inbox, status: failed ? :failed : :sent,
                                failed_at: failed ? created_at : nil, created_at: created_at)
    end

    # "One failed recipient" is not a critical campaign, and labelling it so would train an operator to ignore
    # the badge.
    it 'ignores a campaign below the minimum recipient count' do
      recipient(failed: true)

      expect(component(:campaigns).status).to eq(Operations::Health::HEALTHY)
      expect(component(:campaigns).detail[:size]).to eq(0)
    end

    it 'uses a failure RATE, not a count, and states the thresholds it used' do
      3.times { recipient(failed: true) }
      3.times { recipient(failed: false) }

      found = component(:campaigns)
      expect(found.status).to eq(Operations::Health::CRITICAL)
      expect(found.detail[:size]).to eq(1)
      expect(found.detail[:warning_at]).to eq(described_class::CAMPAIGN_FAILURE_RATE_WARNING)
      expect(found.detail[:critical_at]).to eq(described_class::CAMPAIGN_FAILURE_RATE_CRITICAL)
    end

    it 'stays healthy when a large campaign has a few failures' do
      recipient(failed: true)
      30.times { recipient(failed: false) }

      expect(component(:campaigns).status).to eq(Operations::Health::HEALTHY)
    end
  end

  describe 'commerce' do
    it 'treats a store that needs reconnecting as critical, because it has stopped working' do
      Commerce::Store.create!(account: account, provider: 'zid', external_store_id: '1', name: 'S',
                              base_url: 'https://s.test', status: :needs_reauth)

      found = component(:commerce)
      expect(found.status).to eq(Operations::Health::CRITICAL)
      expect(found.detail[:size]).to eq(1)
    end

    it 'is healthy when every connected store is active' do
      Commerce::Store.create!(account: account, provider: 'zid', external_store_id: '2', name: 'S',
                              base_url: 'https://s.test', status: :active)

      expect(component(:commerce).status).to eq(Operations::Health::HEALTHY)
    end
  end

  describe 'flows' do
    it 'counts terminal failures inside the window, across accounts' do
      [account, other_account].each do |owner|
        bot = create(:agent_bot, account: owner, bot_type: :flow, outgoing_url: nil)
        version = FlowVersion.create!(account: owner, agent_bot: bot, version: 1, graph: { 'nodes' => [] },
                                      status: :published)
        inbox = create(:inbox, account: owner)
        conversation = create(:conversation, account: owner, inbox: inbox)
        FlowSession.create!(account: owner, agent_bot: bot, flow_version: version, conversation: conversation,
                            status: :failed, finished_at: 1.hour.ago)
      end

      found = component(:flows)
      expect(found.detail[:size]).to eq(2)
      expect(found.detail[:accounts]).to eq(2)
    end
  end

  describe 'automations' do
    it 'counts the episodes whose worker died mid-action' do
      rule = create(:automation_rule, account: account, event_name: 'conversation_resolved', execution_delay: 30)
      inbox = create(:inbox, account: account)
      conversation = create(:conversation, account: account, inbox: inbox)
      AutomationRulePendingExecution.create!(automation_rule: rule, conversation: conversation,
                                             account_id: account.id, episode_key: 'k1', due_at: 1.hour.ago,
                                             status: :executing, updated_at: 2.days.ago)

      expect(component(:automations).status).to eq(Operations::Health::WARNING)
      expect(component(:automations).detail[:size]).to eq(1)
    end
  end

  it 'sorts the worst area first, so the thing to look at is at the top' do
    Commerce::Store.create!(account: account, provider: 'zid', external_store_id: '9', name: 'S',
                            base_url: 'https://s.test', status: :disconnected)

    expect(described_class.new.call.first.key).to eq(:commerce)
  end
end
