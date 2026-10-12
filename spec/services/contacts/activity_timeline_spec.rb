require 'rails_helper'

# One example per source the timeline reads, so a source that stops producing entries fails here rather than
# silently disappearing from the UI.
RSpec.describe Contacts::ActivityTimeline do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:whatsapp) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { whatsapp.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:store) { create(:commerce_store, :zid, account: account, name: 'Zid Shop') }

  def entries(categories: nil)
    Contacts::ActivityTimelineQuery.new(account: account, contact: contact, user: administrator,
                                        categories: categories, page: { limit: 100 }).call[:payload]
  end

  def entry_of(kind, categories: nil)
    entries(categories: categories).find { |row| row[:kind] == kind }
  end

  describe 'reporting events' do
    it 'reports a first response with its duration' do
      ReportingEvent.create!(name: 'first_response', value: 120, account_id: account.id, inbox_id: inbox.id,
                             conversation_id: conversation.id, event_start_time: 2.hours.ago,
                             event_end_time: 1.hour.ago, created_at: 1.hour.ago)

      entry = entry_of('first_response')

      expect(entry[:category]).to eq('conversations')
      expect(entry[:meta][:duration_seconds]).to eq(120)
    end

    it 'reports a reopen but not a first open, which the conversation entry already covers' do
      ReportingEvent.create!(name: 'conversation_opened', value: 0, account_id: account.id, inbox_id: inbox.id,
                             conversation_id: conversation.id, event_start_time: conversation.created_at,
                             event_end_time: conversation.created_at, created_at: 2.hours.ago)
      ReportingEvent.create!(name: 'conversation_opened', value: 600, account_id: account.id, inbox_id: inbox.id,
                             conversation_id: conversation.id, event_start_time: 90.minutes.ago,
                             event_end_time: 1.hour.ago, created_at: 1.hour.ago)

      reopens = entries.select { |row| row[:kind] == 'conversation_reopened' }

      expect(reopens.length).to eq(1)
    end

    it 'does not report reply_time, which would bury everything else' do
      ReportingEvent.create!(name: 'reply_time', value: 30, account_id: account.id, inbox_id: inbox.id,
                             conversation_id: conversation.id, event_start_time: 2.hours.ago,
                             event_end_time: 1.hour.ago, created_at: 1.hour.ago)

      expect(entries.pluck(:kind)).not_to include('reply_time')
    end
  end

  describe 'csat' do
    it 'reports a rating with its feedback' do
      csat_message = create(:message, account: account, inbox: inbox, conversation: conversation,
                                      message_type: :template, created_at: 2.hours.ago)
      CsatSurveyResponse.create!(account_id: account.id, conversation_id: conversation.id,
                                 message_id: csat_message.id, contact_id: contact.id, rating: 4,
                                 feedback_message: 'Quick and clear', created_at: 1.hour.ago)

      entry = entry_of('csat_response')

      expect(entry[:meta][:rating]).to eq(4)
      expect(entry[:summary]).to eq('Quick and clear')
    end
  end

  describe 'campaigns' do
    it 'reports the recipient row with its delivery timestamps' do
      campaign = create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago,
                                   title: 'Eid offer')
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: contact,
                                status: :read, source_id: 'wamid.x', sent_at: 3.hours.ago,
                                delivered_at: 2.hours.ago, read_at: 1.hour.ago, created_at: 3.hours.ago)

      entry = entry_of('campaign_read', categories: ['campaigns'])

      expect(entry[:category]).to eq('campaigns')
      expect(entry[:meta][:campaign_title]).to eq('Eid offer')
      expect(entry[:meta][:read_at]).to be_present
    end
  end

  describe 'automations' do
    it 'reports a delayed rule that acted, and not one still waiting' do
      rule = create(:automation_rule, account: account, name: 'Chase', event_name: 'conversation_resolved',
                                      execution_delay: 30)
      AutomationRulePendingExecution.create!(automation_rule: rule, conversation: conversation,
                                             account_id: account.id, episode_key: 'status:1',
                                             due_at: 1.hour.from_now, status: :executed,
                                             created_at: 3.hours.ago, updated_at: 1.hour.ago)
      AutomationRulePendingExecution.create!(automation_rule: rule, conversation: conversation,
                                             account_id: account.id, episode_key: 'status:2',
                                             due_at: 1.hour.from_now, status: :pending,
                                             created_at: 1.hour.ago, updated_at: 1.hour.ago)

      automations = entries(categories: ['automations'])

      expect(automations.pluck(:kind)).to eq(['automation_executed'])
      expect(automations.first[:meta][:rule_name]).to eq('Chase')
    end
  end

  describe 'flows' do
    it 'reports a run that ended, and not one still waiting' do
      bot = create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil, name: 'Welcome')
      version = FlowVersion.create!(account: account, agent_bot: bot, version: 1, status: :published,
                                    graph: { 'nodes' => [], 'edges' => [] })
      FlowSession.create!(account: account, agent_bot: bot, flow_version: version, conversation: conversation,
                          status: :handed_off, steps_count: 3, finished_at: 1.hour.ago,
                          context: { 'end_reason' => 'Care asked' })

      entry = entry_of('flow_handed_off')

      expect(entry[:meta][:flow_name]).to eq('Welcome')
      expect(entry[:meta][:end_reason]).to eq('Care asked')
    end
  end

  describe 'commerce' do
    it 'reports a cart without any money figure' do
      Commerce::Cart.create!(account: account, commerce_store: store, provider: 'zid', provider_cart_id: 'zc-1',
                             contact: contact, state: :abandoned, first_seen_at: 2.hours.ago,
                             last_provider_event_at: 1.hour.ago, abandoned_at: 2.hours.ago,
                             currency: 'SAR', visible_total: 250.0, item_count: 3)

      entry = entry_of('cart_abandoned', categories: ['commerce'])

      expect(entry[:meta]).to include(provider: 'zid', currency: 'SAR', item_count: 3)
      expect(entry[:meta].keys).not_to include(:visible_total, :total, :amount)
    end

    it 'reports an order action with its outcome' do
      Commerce::ActionRun.create!(account: account, store: store, contact_id: contact.id,
                                  conversation_id: conversation.id, provider: 'zid',
                                  action_type: 'refund_partial', external_resource_id: '15',
                                  idempotency_key: "commerce-action:#{SecureRandom.uuid}",
                                  request_digest: 'd' * 64, status: :failed, error_code: 'PROVIDER_REFUSED',
                                  created_at: 1.hour.ago)

      entry = entry_of('commerce_action_failed', categories: ['commerce'])

      expect(entry[:meta]).to include(action_type: 'refund_partial', error_code: 'PROVIDER_REFUSED')
      expect(entry[:conversation_id]).to eq(conversation.id)
    end

    it 'reports the customer link without the encrypted provider customer id' do
      Commerce::CustomerLink.create!(account: account, store: store, contact: contact,
                                     external_customer_id: '9001', match_source: :verified_phone,
                                     created_at: 1.hour.ago)

      entry = entry_of('commerce_customer_linked', categories: ['commerce'])

      expect(entry[:meta]).to include(provider: 'zid', match_source: 'verified_phone')
      expect(entry[:meta].keys).not_to include(:external_customer_id)
    end

    it 'never reads the contact metric cache, which holds no history' do
      expect(Contacts::ActivityTimeline::CommerceAdapter.instance_methods(false).map(&:to_s))
        .not_to include('contact_metric_entries')
      expect(File.read(Rails.root.join('custom/app/services/contacts/activity_timeline/commerce_adapter.rb')))
        .not_to match(/Commerce::ContactMetric\s*\./)
    end
  end
end
