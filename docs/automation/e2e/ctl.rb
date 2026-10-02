# Control runner for the Automation E2E (docs/automation/08-e2e.md). Run with `rails runner`.
#
#   setup <ck> <cs>   Lynomia Demo A: Commerce, CRM and Automations on, English, no stores, no contact audiences, no
#                     automation rules; the disposable local WooCommerce test store A1 connected with its Read key; the
#                     label `paid-vip`. Lynomia Demo B: a shared audience, a store and a team that A's rules must never
#                     reach. Reports ids
#   state             Omar's latest conversation (the one Commerce rules act on): labels, team, assignee; the rules
#   audiences         the contact audiences of Demo A: names, shared, conditions
#   extensions <on|off>  the kill switch, as an operator sets it (installation config LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED)
#   teardown          Demo A's stores (their links and summaries go with them), audiences, rules and the run's label;
#                     Demo B's audience, store and team
require 'json'

def report(result) = puts("SIM #{result.to_json}")

def account_a = Account.find_by!(name: 'Lynomia Demo A')

def account_b = Account.find_by!(name: 'Lynomia Demo B')

def admin_a = User.find_by!(email: 'admin_a@commerce.lynomia.local')

def omar = account_a.contacts.find_by!(name: 'Omar Khalil')

def omar_latest = Automation::CommerceEvents.conversation_for(omar)

E2E_LABEL = 'paid-vip'.freeze
B_NAMES = { audience: 'E2E B audience', store: 'E2E B store', team: 'e2e b team' }.freeze

def clean
  account_a.automation_rules.destroy_all
  account_a.commerce_stores.find_each(&:destroy!)
  Commerce::Store.where(base_url: 'http://localhost:8081').find_each(&:destroy!)
  account_a.custom_filters.contact.delete_all
  conversation = omar_latest
  conversation.update!(label_list: conversation.label_list - [E2E_LABEL]) if conversation&.label_list&.include?(E2E_LABEL)
  account_a.labels.where(title: E2E_LABEL).destroy_all
  account_b.custom_filters.where(name: B_NAMES[:audience]).delete_all
  account_b.commerce_stores.where(name: B_NAMES[:store]).find_each(&:destroy!)
  account_b.teams.where(name: B_NAMES[:team]).destroy_all
end

case ARGV[0]
when 'setup'
  clean
  account_a.update!(locale: 'en')
  account_a.enable_features!('lynomia_commerce', 'crm', 'automations')
  store = Commerce::StoreConnection.new(account: account_a, user: admin_a)
                                   .connect(provider: 'woocommerce', base_url: 'http://localhost:8081', name: 'Syria Cosmetics',
                                            credentials: { 'consumer_key' => ARGV[1], 'consumer_secret' => ARGV[2] })
  account_a.labels.create!(title: E2E_LABEL, color: '#1f93ff', show_on_sidebar: true)
  audience_b = account_b.custom_filters.create!(name: B_NAMES[:audience], filter_type: :contact, shared: true,
                                                query: { payload: [{ attribute_key: 'email', filter_operator: 'contains',
                                                                     values: ['example'], query_operator: nil }] })
  store_b = account_b.commerce_stores.create!(provider: 'woocommerce', name: B_NAMES[:store], base_url: 'http://localhost:8082',
                                              external_store_id: 'e2e-automation-b',
                                              credentials: { 'consumer_key' => 'ck_unused', 'consumer_secret' => 'cs_unused' })
  team_b = account_b.teams.create!(name: B_NAMES[:team])
  conversation = omar_latest
  report({ account_id: account_a.id, store_id: store.id, conversation: conversation.display_id,
           account_b_id: account_b.id, audience_b: audience_b.id, store_b: store_b.id, team_b: team_b.id,
           agent_b: User.find_by!(email: 'admin_b@commerce.lynomia.local').id,
           team_id: conversation.team_id, assignee_id: conversation.assignee_id })
when 'state'
  conversation = omar_latest
  report({ conversation: conversation.display_id, labels: conversation.label_list, team_id: conversation.team_id,
           assignee_id: conversation.assignee_id,
           rules: account_a.automation_rules.order(:id).map do |rule|
             { id: rule.id, name: rule.name, event_name: rule.event_name, active: rule.active, conditions: rule.conditions,
               actions: rule.actions }
           end })
when 'audiences'
  report({ audiences: account_a.custom_filters.contact.order(:id).map do |filter|
    { id: filter.id, name: filter.name, shared: filter.shared, user_id: filter.user_id, query: filter.query }
  end })
when 'extensions'
  config = InstallationConfig.find_or_initialize_by(name: 'LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED')
  if ARGV[1] == 'off'
    config.update!(value: false, locked: false)
  elsif config.persisted?
    config.destroy!
  end
  report({ enabled: Automation::Extensions.enabled? })
when 'teardown'
  InstallationConfig.where(name: 'LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED').destroy_all
  clean
  report({ stores: account_a.commerce_stores.count, audiences: account_a.custom_filters.contact.count,
           rules: account_a.automation_rules.count, labels: omar_latest.label_list.include?(E2E_LABEL) ? 1 : 0 })
end
