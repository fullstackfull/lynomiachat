# frozen_string_literal: true

# Runs on the PRE-upgrade code (Chatwoot 4.14.1 + Lynomia). Creates the "existing production-like" data:
#   Tenant A: WhatsApp inbox connected the existing manual API way (whatsapp_cloud, own api_key)
#   Tenant B: WhatsApp inbox connected through the existing Embedded Signup (source: embedded_signup)
require_relative 'lib'

FakeGraph.reset!(wabas: {
                   'WABA-A' => { name: 'Tenant A Biz', numbers: [{ id: '1110001', display: '+1 555-000-1001', verified_name: 'Tenant A' }] },
                   'WABA-B' => { name: 'Tenant B Biz', business_id: 'BIZ-B', numbers: [{ id: '2220001', display: '+1 555-000-2001', verified_name: 'Tenant B' }] }
                 })

{ 'WHATSAPP_APP_ID' => FakeGraph::APP_ID, 'WHATSAPP_APP_SECRET' => H::APP_SECRET, 'WHATSAPP_CONFIGURATION_ID' => 'cfg-1',
  'WHATSAPP_API_VERSION' => 'v22.0' }.each do |name, value|
  InstallationConfig.find_or_initialize_by(name: name).update!(value: value, locked: false)
end
GlobalConfig.clear_cache

def make_user(email, name)
  User.find_by(email: email) || User.create!(email: email, name: name, password: 'Password1!x', confirmed_at: Time.current)
end

accounts = {}
{ 'A' => 'Tenant A', 'B' => 'Tenant B' }.each do |k, name|
  account = Account.find_by(name: name) || Account.create!(name: name, locale: 'ar')
  admin = make_user("admin_#{k.downcase}@staging.lynomia.local", "Admin #{k}")
  agent = make_user("agent_#{k.downcase}@staging.lynomia.local", "Agent #{k}")
  AccountUser.find_or_create_by!(account: account, user: admin) { |au| au.role = :administrator }
  AccountUser.find_or_create_by!(account: account, user: agent) { |au| au.role = :agent }
  accounts[k] = { account: account, admin: admin, agent: agent }
end

a = accounts['A']
status, body = H.api(:post, "/api/v1/accounts/#{a[:account].id}/inboxes", a[:admin],
                     { name: 'WhatsApp API A', channel: { type: 'whatsapp', phone_number: '+15550001001', provider: 'whatsapp_cloud',
                                                          provider_config: { api_key: 'EAAG-manual-A', phone_number_id: '1110001',
                                                                             business_account_id: 'WABA-A' } } })
H.check('seed: Tenant A manual WhatsApp Cloud API inbox created', status == 200, "status=#{status} #{body.is_a?(Hash) ? body['id'] : body}")
inbox_a = Inbox.find(body['id'])
inbox_a.inbox_members.find_or_create_by!(user: a[:agent])

b = accounts['B']
status, body = H.api(:post, "/api/v1/accounts/#{b[:account].id}/whatsapp/authorization", b[:admin],
                     { code: 'code-B', business_id: 'BIZ-B', waba_id: 'WABA-B', phone_number_id: '2220001' })
H.check('seed: Tenant B embedded-signup WhatsApp inbox created', status == 200, "status=#{status} #{body}")
inbox_b = Inbox.find(body['id'])
inbox_b.inbox_members.find_or_create_by!(user: b[:agent])

File.write(File.join(__dir__, 'out', 'seed_ids.json'), JSON.pretty_generate(
                                                        A: { account_id: a[:account].id, admin: a[:admin].email, agent: a[:agent].email, inbox_id: inbox_a.id },
                                                        B: { account_id: b[:account].id, admin: b[:admin].email, agent: b[:agent].email, inbox_id: inbox_b.id }
                                                      ))
puts "INFO  /register calls during seed: #{FakeGraph.calls('POST', %r{/register\z}).size} (number reported VERIFIED+CONNECTED)"
H.write_results(File.join(__dir__, 'out', 'seed_results.json'))
