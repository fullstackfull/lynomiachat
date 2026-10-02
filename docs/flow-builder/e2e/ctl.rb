# Lynomia Flow Builder E2E control (docs/flow-builder/10-e2e.md), run with `rails runner` on the E2E database:
#
#   setup      account A gets the Flow Builder, a Customer Care team and a vip label, and its WhatsApp inbox the approved
#              templates Chatwoot would have synced from Meta; earlier E2E flows are removed
#   locale     account A's language (en | ar), for the screenshots
#   state      the E2E flow's versions, sessions and inbox connection
#   teardown   E2E flows removed, the inbox's bot detached, the feature switched back off
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
when 'teardown'
  clean
  account_a.disable_features!('lynomia_flow_builder')
  report({ ok: true })
end
