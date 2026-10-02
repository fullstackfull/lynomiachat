require 'rails_helper'

# Flow bots in Chatwoot's AgentBotListener (docs/flow-builder/05-runtime-and-session.md), which the SyncDispatcher calls
# when a message is created: runner jobs instead of webhooks; webhook bots unchanged.
RSpec.describe AgentBotListener do
  let(:account) { create(:account).tap { |record| record.enable_features!('lynomia_flow_builder') } }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:incoming) { create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming) }

  it 'runs the flow for a flow bot\'s customer messages, without any webhook' do
    AgentBotInbox.create!(inbox: inbox, agent_bot: create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil))

    expect(Flows::RunJob).to have_been_enqueued.with(conversation.id, 'messages', incoming.id)
    expect(AgentBots::WebhookJob).not_to have_been_enqueued
  end

  it 'leaves webhook bots exactly as they were' do
    AgentBotInbox.create!(inbox: inbox, agent_bot: create(:agent_bot, account: account, outgoing_url: 'https://bot.example.com/hook'))

    incoming
    expect(AgentBots::WebhookJob).to have_been_enqueued
    expect(Flows::RunJob).not_to have_been_enqueued
  end

  it 'does nothing for accounts without Lynomia Flow Builder' do
    account.disable_features!('lynomia_flow_builder')
    AgentBotInbox.create!(inbox: inbox, agent_bot: create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil))

    incoming
    expect(Flows::RunJob).not_to have_been_enqueued
  end
end
