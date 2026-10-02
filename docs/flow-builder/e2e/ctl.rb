# Lynomia Flow Builder E2E control (docs/flow-builder/10-e2e.md), run with `rails runner` on the E2E database:
#
#   setup      account A gets the Flow Builder, a Customer Care team and a vip label, and its WhatsApp inbox the approved
#              templates Chatwoot would have synced from Meta; earlier E2E flows are removed
#   locale     account A's language (en | ar), for the screenshots
#   state      the E2E flow's versions, sessions and inbox connection
#   teardown   E2E flows removed, the inbox's bot detached, the feature switched back off
#   perf_graph N  a draft flow of N valid nodes for the canvas performance run (docs/flow-builder/perf/canvas.js): Start,
#              segments of a question, a condition, a label, an attribute and a message, and a handoff
#
# Every result is one line: SIM <json>.
def report(result) = puts("SIM #{result.to_json}") # rubocop:disable Rails/Output

E2E_PREFIX = 'E2E '.freeze
# Meta's template list as Chatwoot stores it (the WhatsApp harness syncs the same list from its Graph stand-in).
TEMPLATES = [
  { 'name' => 'order_update', 'status' => 'APPROVED', 'category' => 'UTILITY', 'language' => 'ar', 'id' => 't1',
    'components' => [{ 'type' => 'BODY', 'text' => 'مرحبا {{1}}، طلبك {{2}} في الطريق' }] },
  { 'name' => 'hello_world', 'status' => 'APPROVED', 'category' => 'MARKETING', 'language' => 'en_US', 'id' => 't2',
    'components' => [{ 'type' => 'BODY', 'text' => 'Hello World' }] }
].freeze

def account_a = Account.find_by!(name: 'Lynomia Demo A')

def whatsapp_inbox = account_a.inboxes.find_by!(channel_type: 'Channel::Whatsapp')

def e2e_flows = account_a.agent_bots.flow.where('name LIKE ?', "#{E2E_PREFIX}%")

def clean
  whatsapp_inbox.agent_bot_inbox&.destroy!
  e2e_flows.find_each do |flow|
    flow.flow_sessions.delete_all
    flow.flow_versions.delete_all
    flow.destroy!
  end
end

case ARGV[0]
when 'setup'
  clean
  account_a.update!(locale: 'en')
  account_a.enable_features!('lynomia_flow_builder')
  team = account_a.teams.find_by('LOWER(name) = ?', 'customer care') || account_a.teams.create!(name: 'Customer Care')
  admin = User.find_by!(email: 'admin_a@commerce.lynomia.local')
  team.add_members([admin.id]) unless team.members.include?(admin)
  account_a.labels.find_or_create_by!(title: 'vip') { |label| label.color = '#1f93ff' }
  whatsapp_inbox.channel.update_columns(message_templates: TEMPLATES, message_templates_last_updated: Time.current) # rubocop:disable Rails/SkipsModelValidations
  report({ account_id: account_a.id, inbox_id: whatsapp_inbox.id, inbox_name: whatsapp_inbox.name, team_id: team.id })
when 'locale'
  account_a.update!(locale: ARGV[1])
  report({ locale: account_a.locale })
when 'state'
  flow = e2e_flows.order(:id).last
  report({ flow_id: flow&.id, inbox_bot: whatsapp_inbox.agent_bot_inbox&.agent_bot_id,
           versions: flow ? flow.flow_versions.order(:version).pluck(:version, :status) : [],
           sessions: flow ? flow.flow_sessions.order(:id).map { |s| s.slice(:id, :status, :current_node_id, :conversation_id) } : [] })
when 'perf_graph'
  size = Integer(ARGV[1])
  team = account_a.teams.find_by!('LOWER(name) = ?', 'customer care')
  account_a.custom_attribute_definitions.find_or_create_by!(attribute_model: :conversation_attribute, attribute_key: 'step') do |definition|
    definition.attribute_display_name = 'Step'
    definition.attribute_display_type = :number
  end
  segment = %w[question condition add_label set_conversation_attribute send_message]
  data = lambda do |type, index|
    { 'question' => { text: "Question #{index}?", reply_type: 'any', timeout_minutes: 60 },
      'condition' => { conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['pending'], query_operator: nil }] },
      'add_label' => { labels: ['vip'] }, 'set_conversation_attribute' => { key: 'step', value: index.to_s } }
      .fetch(type, { text: "Step #{index} for {{contact.name}}" })
  end
  nodes = [{ id: 'start', type: 'start', position: { x: 0, y: 0 }, data: {} }]
  (1..(size - 2)).each do |index|
    type = segment[(index - 1) % segment.size]
    nodes << { id: "n#{index}", type: type, position: { x: (index % 10) * 280, y: (index / 10) * 220 }, data: data.call(type, index) }
  end
  nodes << { id: 'human', type: 'handoff', position: { x: ((size - 1) % 10) * 280, y: ((size - 1) / 10) * 220 }, data: { team_id: team.id } }
  outputs = { 'question' => ['reply'], 'condition' => %w[true false] }
  edges = nodes.each_cons(2).flat_map do |from, to|
    outputs.fetch(from[:type], ['next']).map { |handle| { id: "#{from[:id]}-#{handle}", source: from[:id], sourceHandle: handle, target: to[:id] } }
  end
  bot = account_a.agent_bots.create!(name: "#{E2E_PREFIX}Perf #{size}", bot_type: :flow)
  versions = Flows::Versions.new(bot)
  versions.save!(JSON.parse({ nodes: nodes, edges: edges }.to_json))
  report({ flow_id: bot.id, nodes: nodes.size, edges: edges.size, errors: versions.validate.size })
when 'teardown'
  clean
  account_a.disable_features!('lynomia_flow_builder')
  report({ ok: true })
end
