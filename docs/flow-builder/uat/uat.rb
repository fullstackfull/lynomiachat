# Real WhatsApp UAT of the Lynomia Flow Builder (docs/flow-builder/uat/README.md). Run on the server, as the chatwoot
# user, from /home/chatwoot/chatwoot:
#
#   RAILS_ENV=production bundle exec rails runner docs/flow-builder/uat/uat.rb <command> [arguments]
#
#   status   [INBOX_ID]                         A1/A3: release, migrations, switches, workers, WhatsApp inboxes; for
#                                               INBOX_ID also Meta's view through Chatwoot's own read-only services
#   setup    INBOX_ID PHONE TEMPLATE LANGUAGE   the UAT flow (Start keyword "uat-lynomia"), a shared audience matching
#                                               PHONE, a "UAT Care" team; publishes the flow and connects it to the inbox
#   audience match|nomatch                      A7: the UAT audience matches PHONE, or matches nobody
#   evidence PHONE                              A4–A11: the test conversation's messages, provider ids, statuses, flow
#                                               sessions, assignment (no message text)
#   duplicate PHONE                             A6: the last customer message delivered again to Chatwoot's incoming
#                                               service with the same WhatsApp id, and its flow job run again
#   teardown                                    the UAT flow disconnected and deleted, the inbox's previous bot, the
#                                               feature state restored, the UAT audience and team deleted
#
# Never printed: tokens, app secrets, provider_config values, message text. Phone numbers are masked.
require 'sidekiq/api'

UAT_NAME = 'Lynomia UAT flow'.freeze
KEYWORD = 'uat-lynomia'.freeze

def say(line) = puts(line) # rubocop:disable Rails/Output
def mask(value) = value.to_s.gsub(/\d(?=\d{4})/, '•')
def digits(phone) = phone.to_s.delete('^0-9')
def uat_bot = AgentBot.flow.find_by(name: UAT_NAME)

def inbox_line(inbox)
  channel = inbox.channel
  config = channel.provider_config || {}
  approved = Array(channel.message_templates).count { |t| t['status'].to_s.casecmp?('approved') }
  "inbox #{inbox.id} \"#{inbox.name}\" account #{inbox.account_id} provider #{channel.provider} " \
    "mode #{config['is_coexistence'] ? 'coexistence' : 'whatsapp_api'} number #{mask(channel.phone_number)} " \
    "waba #{mask(config['business_account_id'])} reauthorization_required=#{channel.reauthorization_required?} " \
    "templates #{Array(channel.message_templates).size} (approved #{approved}) synced #{channel.message_templates_last_updated&.iso8601} " \
    "bot #{inbox.agent_bot_inbox&.agent_bot_id.inspect}"
end

def status(inbox_id)
  root = Rails.root.to_s
  say "server path #{root}"
  say "git #{`git -C #{root} rev-parse --abbrev-ref HEAD`.strip} #{`git -C #{root} rev-parse --short HEAD`.strip}"
  pending = ActiveRecord::Base.connection_pool.migration_context.migrations_status.select { |state, _, _| state == 'down' }
  say "migrations pending=#{pending.size} #{pending.map { |_, version, name| "#{version} #{name}" }.join(', ')}"
  say "flow tables #{%w[flow_versions flow_sessions].all? { |t| ActiveRecord::Base.connection.table_exists?(t) }}"
  say "LYNOMIA_FLOW_BUILDER_ENABLED effective=#{Flows::Switch.enabled?}"
  say "lynomia_flow_builder accounts=#{Account.all.select { |a| a.feature_enabled?('lynomia_flow_builder') }.map(&:id).inspect}"
  say "sidekiq processes=#{Sidekiq::ProcessSet.new.size} retries=#{Sidekiq::RetrySet.new.size} dead=#{Sidekiq::DeadSet.new.size} " \
      "queues=#{Sidekiq::Queue.all.map { |q| "#{q.name}:#{q.size}" }.join(',')}"
  Inbox.where(channel_type: 'Channel::Whatsapp').order(:id).each { |inbox| say inbox_line(inbox) }
  return if inbox_id.blank?

  channel = Inbox.find(inbox_id).channel
  health = Whatsapp::HealthService.new(channel).fetch_health_status
  say "meta number status=#{health[:status]} platform=#{health[:platform_type]} on_business_app=#{health[:is_on_biz_app]} " \
      "verified_name=#{health[:verified_name].present?} quality=#{health[:quality_rating]} account_mode=#{health[:account_mode]}"
  webhook = Whatsapp::ManualWebhookStatusService.new(channel).perform
  say "meta webhook callback_configured=#{webhook[:callback_configured]} subscribed=#{webhook[:subscription_verified]}"
rescue StandardError => e
  say "meta check error #{e.class}: #{e.message.gsub(/[A-Za-z0-9_-]{30,}/, '[redacted]').first(200)}"
end

def template_params_for(inbox, name, language)
  template = Flows::Template.find(inbox, name, language)
  problem = Flows::Template.problem(inbox, name, language)
  abort("template #{name}/#{language}: #{problem}") if problem

  Flows::Template.slots(template).each_with_object({}) do |(section, key, kind), params|
    if section == 'buttons'
      (params['buttons'] ||= [])[key] = { 'type' => kind == :copy_code ? 'copy_code' : 'url', 'parameter' => 'UAT1' }
    else
      (params[section] ||= {})[key] = slot_value(kind)
    end
  end
end

def slot_value(kind)
  case kind
  when :media_url then ENV.fetch('UAT_MEDIA_URL') { abort('this template has a media header: set UAT_MEDIA_URL to an https link') }
  when :media_name then 'uat.pdf'
  else '{{contact.name}}'
  end
end

def node(id, type, data = {}, x = 0, y = 0) = { 'id' => id, 'type' => type, 'position' => { 'x' => x, 'y' => y }, 'data' => data }
def edge(source, target, handle = 'next') = { 'id' => "#{source}-#{handle}", 'source' => source, 'sourceHandle' => handle, 'target' => target }

def setup(inbox_id, phone, template, language)
  abort('a UAT flow exists: run teardown first') if uat_bot
  abort('LYNOMIA_FLOW_BUILDER_ENABLED is off on this installation') unless Flows::Switch.enabled?
  inbox = Inbox.find(inbox_id)
  account = inbox.account
  abort('not a WhatsApp Cloud inbox') unless Flows::ChannelCapabilities.for(inbox)
  template_params = template_params_for(inbox, template, language) # checked before anything is created
  feature_was = account.feature_enabled?('lynomia_flow_builder')
  account.enable_features!('lynomia_flow_builder') unless feature_was
  audience = account.custom_filters.create!(name: 'UAT test phone', filter_type: :contact, shared: true, user: nil,
                                            query: { payload: [{ attribute_key: 'phone_number', filter_operator: 'equal_to',
                                                                 values: ["+#{digits(phone)}"], query_operator: nil }] })
  team = account.teams.create!(name: 'UAT Care', description: 'Lynomia Flow Builder UAT (deleted by teardown)')
  previous = inbox.agent_bot_inbox&.slice('agent_bot_id', 'status')
  bot = account.agent_bots.create!(name: UAT_NAME, bot_type: :flow,
                                   bot_config: { 'uat' => { 'inbox_id' => inbox.id, 'phone' => "+#{digits(phone)}", 'previous' => previous,
                                                            'feature_was' => feature_was,
                                                            'audience_id' => audience.id, 'team_id' => team.id } })
  menu = [{ 'id' => 'ask', 'title' => 'Question' }, { 'id' => 'care', 'title' => 'Customer care' }, { 'id' => 'tpl', 'title' => 'Template' }]
  graph = {
    'nodes' => [
      node('start', 'start', { 'keywords' => [KEYWORD] }), node('hello', 'send_message', { 'text' => 'Lynomia UAT: hello {{contact.name}}' }, 0, 150),
      node('aud', 'audience_condition', { 'conditions' => [{ 'attribute_key' => 'contact_audience', 'filter_operator' => 'equal_to',
                                                              'values' => [audience.id], 'query_operator' => nil }] }, 0, 300),
      node('vip', 'send_message', { 'text' => 'Lynomia UAT: audience matched' }, -200, 450),
      node('reg', 'send_message', { 'text' => 'Lynomia UAT: audience not matched' }, 200, 450),
      node('menu', 'buttons', { 'text' => 'Lynomia UAT: choose', 'options' => menu }, 0, 600),
      node('ask', 'question', { 'text' => 'Lynomia UAT: send a number', 'reply_type' => 'number', 'max_attempts' => 2,
                                'store_as' => { 'scope' => 'context', 'key' => 'uat_no' }, 'timeout_minutes' => 1440 }, -300, 800),
      node('got', 'send_message', { 'text' => 'Lynomia UAT: received {{flow.uat_no}}' }, -300, 950),
      node('care', 'handoff', { 'team_id' => team.id, 'reason' => 'Lynomia UAT handoff' }, 0, 800),
      node('tpl', 'send_template', { 'name' => template, 'language' => language, 'params' => template_params }, 300, 800),
      node('end', 'end', {}, 0, 1100)
    ],
    'edges' => [edge('start', 'hello'), edge('hello', 'aud'), edge('aud', 'vip', 'true'), edge('aud', 'reg', 'false'), edge('vip', 'menu'),
                edge('reg', 'menu'), edge('menu', 'ask', 'ask'), edge('menu', 'care', 'care'), edge('menu', 'tpl', 'tpl'),
                edge('ask', 'got', 'reply'), edge('ask', 'tpl', 'timeout'), edge('got', 'end'), edge('tpl', 'end'), edge('tpl', 'care', 'failed')]
  }
  versions = Flows::Versions.new(bot)
  versions.save!(graph)
  link = inbox.agent_bot_inbox || inbox.build_agent_bot_inbox
  link.update!(agent_bot: bot, status: :active)
  version = versions.publish!
  say "UAT flow #{bot.id} published v#{version.version} on inbox #{inbox.id}; audience #{audience.id}; team #{team.id}; previous bot #{previous.inspect}"
  say "send \"#{KEYWORD}\" from #{mask(phone)} to start it"
rescue Flows::Versions::Invalid => e
  say "not published: #{e.errors.inspect}"
end

def audience(mode)
  config = uat_bot&.bot_config&.dig('uat') || abort('no UAT flow')
  filter = CustomFilter.find(config['audience_id'])
  payload = filter.query.deep_dup
  payload['payload'].first['values'] = [mode == 'nomatch' ? '+0000000000' : config['phone']]
  filter.update!(query: payload)
  say "UAT audience now #{mode == 'nomatch' ? 'matches nobody' : "matches #{mask(config['phone'])}"}"
end

def conversation_for(phone)
  config = uat_bot&.bot_config&.dig('uat')
  scope = ContactInbox.where(source_id: digits(phone))
  scope = scope.where(inbox_id: config['inbox_id']) if config
  scope.order(:id).last&.conversations&.order(:id)&.last
end

def evidence(phone)
  conversation = conversation_for(phone) || abort('no conversation for that number')
  say "conversation #{conversation.display_id} (id #{conversation.id}) inbox #{conversation.inbox_id} status #{conversation.status} " \
      "assignee #{conversation.assignee_id.inspect} team #{conversation.team_id.inspect} bot #{conversation.ai_assignee&.id.inspect} " \
      "can_reply=#{conversation.can_reply?}"
  conversation.messages.where(message_type: %i[incoming outgoing]).order(:id).last(40).each do |m|
    reply = m.content_attributes.dig('interactive_reply', 'id')
    template = m.additional_attributes&.dig('template_params')&.slice('name', 'language')
    say "msg #{m.id} #{m.created_at.utc.iso8601} #{m.message_type} #{m.sender_type}#{"(#{m.sender_id})" if m.sender_type == 'AgentBot'} " \
        "#{m.content_type} chars=#{m.content.to_s.length} wamid=#{m.source_id || '-'} status=#{m.status}" \
        "#{" error=#{m.external_error.to_s.first(80)}" if m.failed?}#{" reply_id=#{reply}" if reply}#{" template=#{template.values.join('/')}" if template}" \
        "#{' private' if m.private?}"
  end
  FlowSession.where(conversation: conversation).order(:id).each do |s|
    say "session #{s.id} flow #{s.agent_bot_id} v#{s.flow_version.version} #{s.status} node=#{s.current_node_id} steps=#{s.steps_count} " \
        "last_message=#{s.last_message_id} end=#{s.context['end_reason'] || s.failure_code || '-'} visits=#{s.context['visits'].to_h.to_json}"
  end
end

def duplicate(phone)
  conversation = conversation_for(phone) || abort('no conversation for that number')
  inbox = conversation.inbox
  last = conversation.messages.incoming.where.not(source_id: nil).order(:id).last || abort('no customer message')
  before = [conversation.messages.count, conversation.messages.outgoing.where(sender_type: 'AgentBot').count]
  config = inbox.channel.provider_config
  params = { object: 'whatsapp_business_account',
             entry: [{ id: config['business_account_id'], changes: [{ field: 'messages', value: {
               messaging_product: 'whatsapp', metadata: { display_phone_number: inbox.channel.phone_number.delete('+'), phone_number_id: config['phone_number_id'] },
               contacts: [{ profile: { name: conversation.contact.name }, wa_id: digits(phone) }],
               messages: [{ from: digits(phone), id: last.source_id, timestamp: last.created_at.to_i.to_s, type: 'text', text: { body: last.content.to_s } }]
             } }] }] }.with_indifferent_access
  Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform
  Flows::RunJob.perform_now(conversation.id, 'messages', last.id)
  after = [conversation.messages.count, conversation.messages.outgoing.where(sender_type: 'AgentBot').count]
  say "duplicate of #{last.source_id}: messages #{before[0]} -> #{after[0]}, flow messages #{before[1]} -> #{after[1]} " \
      "#{before == after ? 'PASS (nothing advanced twice)' : 'FAIL'}"
end

def teardown
  bot = uat_bot || abort('no UAT flow')
  config = bot.bot_config['uat']
  inbox = Inbox.find(config['inbox_id'])
  Flows::Versions.new(bot).disable!
  link = inbox.agent_bot_inbox
  if config['previous']
    link.update!(agent_bot_id: config['previous']['agent_bot_id'], status: config['previous']['status'])
  elsif link&.agent_bot_id == bot.id
    link.destroy!
  end
  bot.flow_sessions.live.each { |s| Flows::SessionEnd.new(s.conversation).hand_off(s, 'flow_disabled') }
  bot.flow_sessions.delete_all
  bot.flow_versions.delete_all
  bot.destroy!
  CustomFilter.where(id: config['audience_id']).destroy_all
  Team.where(id: config['team_id']).destroy_all
  inbox.account.disable_features!('lynomia_flow_builder') unless config['feature_was']
  say "UAT flow removed; inbox #{inbox.id} bot #{inbox.reload.agent_bot_inbox&.agent_bot_id.inspect}; feature restored=#{!config['feature_was']}"
end

command, *args = ARGV
case command
when 'status' then status(args[0])
when 'setup' then setup(*args.first(4))
when 'audience' then audience(args[0])
when 'evidence' then evidence(args[0])
when 'duplicate' then duplicate(args[0])
when 'teardown' then teardown
else say 'usage: status [INBOX_ID] | setup INBOX_ID PHONE TEMPLATE LANGUAGE | audience match|nomatch | evidence PHONE | duplicate PHONE | teardown'
end
