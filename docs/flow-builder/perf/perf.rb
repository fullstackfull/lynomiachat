# Lynomia Flow Builder performance (docs/flow-builder/09-performance.md). Run with `rails runner` in production mode on
# the E2E database; it creates a throwaway account and deletes it at the end. Jobs are recorded, never sent.
#
#   graphs of 50, 100 and 200 nodes: GET the flow (load + validation), PUT the draft (save), validate, POST publish, and
#   a Test Mode replay, each through the real API (median of RUNS)
#   runtime on the 200-node flow: start, resume after a reply (one segment), the longest chain the runner allows between
#   two waits (MAX_AUTO_STEPS), and a handoff
require 'benchmark'

RUNS = 5
ActiveJob::Base.queue_adapter = :test
Rails.logger.level = :warn

def median(values) = values.sort[values.size / 2]
def ms(seconds) = (seconds * 1000).round(1)
def timed = ms(Benchmark.realtime { yield })

account = Account.create!(name: "Flow perf #{SecureRandom.hex(3)}", locale: 'en')
account.enable_features!('lynomia_flow_builder')
admin = User.create!(email: "flow-perf-#{SecureRandom.hex(4)}@perf.lynomia.local", name: 'Perf admin', password: 'Password1!x',
                     confirmed_at: Time.current)
AccountUser.create!(account: account, user: admin, role: :administrator)
channel = Channel::Whatsapp.new(account: account, phone_number: "+1555#{rand(1_000_000..9_999_999)}", provider: 'whatsapp_cloud',
                                provider_config: { 'api_key' => 'perf', 'phone_number_id' => 'perf', 'business_account_id' => 'perf' })
# No Meta here: the provider check and the template sync are skipped, as the test factory does.
channel.define_singleton_method(:validate_provider_config) { nil }
channel.define_singleton_method(:sync_templates) { nil }
channel.save!
inbox = Inbox.create!(account: account, channel: channel, name: 'Perf WhatsApp')
team = account.teams.create!(name: 'Perf team')
account.labels.create!(title: 'perf')
account.custom_attribute_definitions.create!(attribute_model: :conversation_attribute, attribute_key: 'step', attribute_display_name: 'Step',
                                             attribute_display_type: :number)
session = ActionDispatch::Integration::Session.new(Rails.application).tap { |s| s.host! 'perf.lynomia.local' }
api = lambda do |method, path, params = nil|
  session.public_send(method, "/api/v1/accounts/#{account.id}#{path}", params: params&.to_json,
                                                                        headers: { 'CONTENT_TYPE' => 'application/json', 'api_access_token' => admin.access_token.token })
  raise "#{method} #{path}: #{session.response.status} #{session.response.body.first(300)}" unless session.response.successful?

  session.response.body.present? ? JSON.parse(session.response.body) : {}
end

def graph_node(id, type, data, index) = { id: id, type: type, position: { x: (index % 10) * 280, y: (index / 10) * 200 }, data: data }

SEGMENT = %w[question condition add_label set_conversation_attribute send_message].freeze

def main_outputs(type) = { 'question' => ['reply'], 'condition' => %w[true false] }.fetch(type, ['next'])

def data_for(type, index)
  case type
  when 'question' then { text: "Question #{index}?", reply_type: 'any', timeout_minutes: 60 }
  when 'condition' then { conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['pending'], query_operator: nil }] }
  when 'add_label' then { labels: ['perf'] }
  when 'set_conversation_attribute' then { key: 'step', value: index.to_s }
  else { text: "Step #{index} for {{contact.name}}" }
  end
end

# A valid flow of `size` nodes: Start, then repeated segments (a question, and after the reply a condition, a label, an
# attribute and a message), and a handoff at the end. Each node leads to the next through its main outputs.
def graph_of(size, team)
  nodes = [graph_node('start', 'start', {}, 0)]
  (1..(size - 2)).each { |index| nodes << graph_node("n#{index}", SEGMENT[(index - 1) % SEGMENT.size], data_for(SEGMENT[(index - 1) % SEGMENT.size], index), index) }
  nodes << graph_node('human', 'handoff', { team_id: team.id, reason: 'Perf handoff' }, size - 1)
  edges = nodes.each_cons(2).flat_map do |from, to|
    main_outputs(from[:type]).map { |handle| { id: "#{from[:id]}-#{handle}", source: from[:id], sourceHandle: handle, target: to[:id] } }
  end
  { nodes: nodes, edges: edges }
end

results = { runs: RUNS, api: {}, runtime: {} }
[50, 100, 200].each do |size|
  flow = api.call(:post, '/flows', { name: "Perf #{size}" })
  graph = graph_of(size, team)
  bytes = graph.to_json.bytesize
  saves = Array.new(RUNS) { timed { api.call(:put, "/flows/#{flow['id']}/draft", { graph: graph }) } }
  errors = Flows::Versions.new(AgentBot.find(flow['id'])).validate
  raise "graph #{size} invalid: #{errors.first(3)}" if errors.any?

  loads = Array.new(RUNS) { timed { api.call(:get, "/flows/#{flow['id']}") } }
  validates = Array.new(RUNS) { timed { Flows::Versions.new(AgentBot.find(flow['id'])).validate } }
  publishes = Array.new(RUNS) do
    api.call(:put, "/flows/#{flow['id']}/draft", { graph: graph })
    timed { api.call(:post, "/flows/#{flow['id']}/publish") }
  end
  api.call(:post, "/inboxes/#{inbox.id}/set_agent_bot", { agent_bot: flow['id'] })
  inputs = [{ text: 'hi' }] + Array.new(5) { |i| { text: "answer #{i}" } }
  simulations = Array.new(RUNS) { timed { api.call(:post, "/flows/#{flow['id']}/simulate", { inputs: inputs }) } }
  results[:api][size] = { nodes: graph[:nodes].size, edges: graph[:edges].size, bytes: bytes, load_ms: median(loads), save_ms: median(saves),
                          validate_ms: median(validates), publish_ms: median(publishes), test_mode_6_inputs_ms: median(simulations) }
  puts "PERF #{size} nodes: #{results[:api][size].to_json}"
end

# Runtime on the 200-node flow (connected to the inbox last).
bot = inbox.reload.agent_bot
# A new conversation in the inbox as it is now (the flow connected last owns its bot phase).
contact_for = lambda do |index|
  current = Inbox.find(inbox.id)
  contact = account.contacts.create!(name: "Perf #{index}", phone_number: "+9665#{format('%08d', index)}")
  contact_inbox = ContactInbox.create!(contact: contact, inbox: current, source_id: "9665#{format('%08d', index)}")
  Conversation.create!(account: account, inbox: current, contact: contact, contact_inbox: contact_inbox)
end
incoming = lambda do |conversation, text|
  conversation.messages.create!(message_type: :incoming, account_id: account.id, inbox_id: inbox.id, sender: conversation.contact, content: text)
end
starts = []
resumes = []
RUNS.times do |run|
  conversation = contact_for.call(run)
  first = incoming.call(conversation, 'hi')
  starts << timed { Flows::RunJob.perform_now(conversation.id, 'messages', first.id) }
  reply = incoming.call(conversation, 'answer')
  resumes << timed { Flows::RunJob.perform_now(conversation.id, 'messages', reply.id) }
  waiting = FlowSession.find_by(conversation: conversation)
  raise "resume: #{waiting&.status} at #{waiting&.current_node_id}" unless waiting&.waiting? && waiting.current_node_id == 'n6'
end
results[:runtime][:start_ms] = median(starts)
results[:runtime][:resume_one_segment_ms] = median(resumes)

# The longest chain the runner runs without waiting: MAX_AUTO_STEPS nodes in one go (Start, labels and attributes, End).
chain_nodes = [{ id: 'start', type: 'start', position: { x: 0, y: 0 }, data: {} }]
(1..(Flows::Runner::MAX_AUTO_STEPS - 2)).each do |i|
  chain_nodes << { id: "c#{i}", type: i.even? ? 'add_label' : 'set_conversation_attribute', position: { x: i * 10, y: 0 },
                   data: i.even? ? { labels: ['perf'] } : { key: 'step', value: i.to_s } }
end
chain_nodes << { id: 'end', type: 'end', position: { x: 0, y: 400 }, data: {} }
chain_edges = chain_nodes.each_cons(2).map { |from, to| { id: "#{from[:id]}-next", source: from[:id], sourceHandle: 'next', target: to[:id] } }
chain = api.call(:post, '/flows', { name: 'Perf chain' })
api.call(:put, "/flows/#{chain['id']}/draft", { graph: { nodes: chain_nodes, edges: chain_edges } })
api.call(:post, "/flows/#{chain['id']}/publish")
api.call(:post, "/inboxes/#{inbox.id}/set_agent_bot", { agent_bot: chain['id'] })
chains = Array.new(RUNS) do |run|
  conversation = contact_for.call(100 + run)
  message = incoming.call(conversation, 'go')
  elapsed = timed { Flows::RunJob.perform_now(conversation.id, 'messages', message.id) }
  ran = FlowSession.find_by(conversation: conversation)
  raise "chain: #{ran&.status} after #{ran&.steps_count} steps" unless ran&.completed? && ran.steps_count == Flows::Runner::MAX_AUTO_STEPS

  elapsed
end
results[:runtime][:chain_max_auto_steps_ms] = median(chains)

handoff = api.call(:post, '/flows', { name: 'Perf handoff' })
api.call(:put, "/flows/#{handoff['id']}/draft",
         { graph: { nodes: [{ id: 'start', type: 'start', position: { x: 0, y: 0 }, data: {} },
                            { id: 'human', type: 'handoff', position: { x: 0, y: 200 },
                              data: { team_id: team.id, priority: 'high', labels: ['perf'], reason: 'Perf handoff' } }],
                    edges: [{ id: 'e', source: 'start', sourceHandle: 'next', target: 'human' }] } })
api.call(:post, "/flows/#{handoff['id']}/publish")
api.call(:post, "/inboxes/#{inbox.id}/set_agent_bot", { agent_bot: handoff['id'] })
handoffs = Array.new(RUNS) do |run|
  conversation = contact_for.call(200 + run)
  message = incoming.call(conversation, 'help')
  elapsed = timed { Flows::RunJob.perform_now(conversation.id, 'messages', message.id) }
  raise 'not handed off' unless conversation.reload.open? && conversation.team_id == team.id

  elapsed
end
results[:runtime][:handoff_ms] = median(handoffs)
results[:runtime][:bot] = bot&.name
puts "PERF runtime: #{results[:runtime].to_json}"
puts "RESULT #{results.to_json}"

account.agent_bots.find_each do |flow_bot|
  flow_bot.flow_sessions.delete_all
  flow_bot.flow_versions.delete_all
end
inbox.agent_bot_inbox&.destroy!
account.destroy!
admin.destroy!
