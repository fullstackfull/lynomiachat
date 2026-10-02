# Rollback level A then C.2 / C.3 of docs/flow-builder/12-production-readiness.md §10, exactly as documented, on the CURRENT release.
ActiveJob::Base.queue_adapter = :inline
InstallationConfig.find_or_initialize_by(name: 'LYNOMIA_FLOW_BUILDER_ENABLED').update!(value: false, locked: false); GlobalConfig.clear_cache
puts "SWITCH enabled=#{Flows::Switch.enabled?}"
AgentBot.flow.find_each { |bot| Flows::Versions.new(bot).disable! }; Conversation.pending.where(inbox_id: AgentBotInbox.where(agent_bot_id: AgentBot.flow.select(:id)).select(:inbox_id)).find_each(&:bot_handoff!); AgentBotInbox.where(agent_bot_id: AgentBot.flow.select(:id)).destroy_all
require 'sidekiq/api'; [Sidekiq::ScheduledSet.new, Sidekiq::RetrySet.new].each { |set| set.select { |job| job.display_class == 'Flows::RunJob' }.each(&:delete) }
puts "DETACHED sessions_live=#{FlowSession.live.count} flow_inboxes=#{AgentBotInbox.where(agent_bot_id: AgentBot.flow.select(:id)).count} pending=#{Conversation.pending.count} published=#{FlowVersion.published.count}"
