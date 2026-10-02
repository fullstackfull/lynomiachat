# Runs on the CURRENT release (HEAD): a flow bot published, connected to a WhatsApp inbox, with a waiting session.
ActiveJob::Base.queue_adapter = :test
account = Account.create!(name: 'Rollback proof')
account.enable_features!('lynomia_flow_builder')
channel = Channel::Whatsapp.new(account: account, phone_number: '+15550009001', provider: 'whatsapp_cloud',
                                provider_config: { 'api_key' => 'x', 'phone_number_id' => 'x', 'business_account_id' => 'x' })
channel.define_singleton_method(:validate_provider_config) { nil }
channel.define_singleton_method(:sync_templates) { nil }
channel.save!
inbox = Inbox.create!(account: account, channel: channel, name: 'Rollback WhatsApp')
admin = User.create!(email: 'rollback-admin@proof.lynomia.local', name: 'Rollback admin', password: 'Password1!x', confirmed_at: Time.current)
AccountUser.create!(account: account, user: admin, role: :administrator)
bot = account.agent_bots.create!(name: 'Welcome flow', bot_type: :flow)
graph = { 'nodes' => [{ 'id' => 's', 'type' => 'start', 'position' => { 'x' => 0, 'y' => 0 }, 'data' => {} },
                      { 'id' => 'q', 'type' => 'question', 'position' => { 'x' => 0, 'y' => 100 }, 'data' => { 'text' => 'Order?' } },
                      { 'id' => 'e', 'type' => 'end', 'position' => { 'x' => 0, 'y' => 200 }, 'data' => {} }],
          'edges' => [{ 'id' => 's-next', 'source' => 's', 'sourceHandle' => 'next', 'target' => 'q' },
                      { 'id' => 'q-reply', 'source' => 'q', 'sourceHandle' => 'reply', 'target' => 'e' }] }
Flows::Versions.new(bot).tap { |versions| versions.save!(graph) }.publish!
AgentBotInbox.create!(inbox: inbox, agent_bot: bot)
contact = account.contacts.create!(name: 'Rollback customer', phone_number: '+966500000099')
contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: '966500000099')
conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
message = conversation.messages.create!(account: account, inbox: inbox, message_type: :incoming, sender: contact, content: 'hi')
Flows::RunJob.perform_now(conversation.id, 'messages', message.id)
puts "SEED account=#{account.id} inbox=#{inbox.id} bot=#{bot.id} session=#{FlowSession.last.status} conversation=#{conversation.reload.status}"
