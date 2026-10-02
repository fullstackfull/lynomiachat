# Runs on the PREVIOUS release (before the Flow Builder) against the database the current release migrated.
ActiveJob::Base.queue_adapter = :test
account = Account.find_by!(name: 'Rollback proof')
inbox = account.inboxes.first
bot = account.agent_bots.first
checks = {}
checks['tables ignored, app boots'] = ActiveRecord::Base.connection.table_exists?(:flow_sessions) && !defined?(FlowSession)
checks['flow bot loads (bot_type unknown to the old enum)'] = bot.bot_type.nil? && bot.outgoing_url.blank?
admin = User.find_by!(email: 'rollback-admin@proof.lynomia.local')
session = ActionDispatch::Integration::Session.new(Rails.application).tap { |s| s.host! 'proof.lynomia.local' }
get_json = lambda do |path|
  session.get("/api/v1/accounts/#{account.id}#{path}", headers: { 'api_access_token' => admin.access_token.token })
  [session.response.status, session.response.body]
end
status, body = get_json.call('/agent_bots')
checks['Settings > Bots API answers 200 and lists the flow bot'] = status == 200 && body.include?('Welcome flow')
status, body = get_json.call('/inboxes')
checks['inboxes API answers 200'] = status == 200 && body.include?('Rollback WhatsApp')
contact = account.contacts.first
conversation = account.conversations.first
message = conversation.messages.create!(account: account, inbox: inbox, message_type: :incoming, sender: contact, content: 'still there?')
enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job['job_class'] || job[:job].to_s }
checks['a customer message is stored; no webhook job for the flow bot'] = message.persisted? && enqueued.none? { |name| name.to_s.include?('AgentBots::WebhookJob') }
checks.each { |name, ok| puts "#{ok ? 'PASS' : 'FAIL'}  #{name}" }
puts "STATE conversation=#{conversation.reload.status} inbox_bot=#{inbox.reload.agent_bot_inbox&.agent_bot_id.inspect} bot_messages=#{conversation.messages.where(sender_type: 'AgentBot').count}"
puts "enqueued: #{enqueued.uniq.inspect}"
