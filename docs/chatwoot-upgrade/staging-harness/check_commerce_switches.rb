# frozen_string_literal: true

# Lynomia Commerce switches on a deployed build (docs/commerce/23-real-uat-and-production-gate.md §8):
# - Commerce is off after the deploy (no account has it, only WooCommerce is offered);
# - one provider's switch changes only that provider;
# - Commerce switched off for every account stops Commerce and nothing else, and switching it back on restores it.
# WhatsApp inbound and agent replies are checked at every step. Needs a reachable WooCommerce store in
# COMMERCE_WOO_URL / COMMERCE_WOO_KEY / COMMERCE_WOO_SECRET (allowed through COMMERCE_TRUSTED_STORE_HOSTS).
# It leaves Commerce on for tenant A with the store connected, so a rollback can be run over Commerce data.
# usage: rails runner check_commerce_switches.rb <label>
require_relative 'lib'

WebMock.reset!
stub_request(:any, /graph\.facebook\.com|lookaside\.fbsbx\.com/).to_rack(FakeGraph)
WebMock.disable_net_connect!(allow_localhost: true)

label = ARGV[0] || 'run'
ids = JSON.parse(File.read(File.join(__dir__, 'out', 'seed_ids.json')))
FakeGraph.reset!(wabas: { 'WABA-A' => { name: 'Tenant A Biz', numbers: [{ id: '1110001', display: '+1 555-000-1001', verified_name: 'Tenant A' }] } })
run = "#{label}-#{Time.now.to_i}"
tenant = ids['A']
account = Account.find(tenant['account_id'])
admin = User.find_by!(email: tenant['admin'])
agent = User.find_by!(email: tenant['agent'])
base = "/api/v1/accounts/#{account.id}"
switch = lambda do |name, value|
  InstallationConfig.find_or_initialize_by(name: name).update!(value: value)
end
whatsapp = lambda do |step|
  wamid = "wamid.COMMERCE-#{run}-#{step}"
  code = H.post_webhook('+15550001001', H.inbound('WABA-A', '1110001', '15550001001', from: '15557770001', id: wamid, type: 'text',
                                                                                  content: { body: "commerce #{step}" }))
  message = Message.find_by(source_id: wamid)
  reply, = H.api(:post, "#{base}/conversations/#{message&.conversation&.display_id}/messages", agent, { content: "reply #{step}" })
  H.check("WhatsApp inbound and agent reply work (#{step})", code == 200 && message&.incoming? && reply == 200, "webhook=#{code} reply=#{reply}")
  message&.conversation
end

H.check('deploy: no account has Commerce', Account.all.none? { |a| a.feature_enabled?('lynomia_commerce') })
H.check('deploy: only WooCommerce is offered', Commerce::Providers.enabled == ['woocommerce'], Commerce::Providers.enabled.inspect)
conversation = whatsapp.call('commerce-off')
stores = "#{base}/conversations/#{conversation.display_id}/commerce/stores"
code, = H.api(:get, "#{base}/commerce/stores", admin)
H.check('Commerce settings refused while Commerce is off', code == 401, "http=#{code}")
code, = H.api(:get, stores, agent)
H.check('conversation Commerce refused while Commerce is off', code == 401, "http=#{code}")

account.enable_features!('lynomia_commerce')
code, body = H.api(:post, "#{base}/commerce/stores", admin, { provider: 'woocommerce', name: 'Rehearsal Woo', base_url: ENV.fetch('COMMERCE_WOO_URL'),
                                                              consumer_key: ENV.fetch('COMMERCE_WOO_KEY'), consumer_secret: ENV.fetch('COMMERCE_WOO_SECRET') })
store = Commerce::Store.find_by(id: body.is_a?(Hash) && body['id'])
H.check('Commerce on: a real WooCommerce store connects', code == 201 && store&.active?, "http=#{code}")
H.check('store response carries no credentials', !body.to_json.include?(ENV.fetch('COMMERCE_WOO_SECRET')) && !body.to_json.include?('credentials'))
code, body = H.api(:get, "#{stores}/#{store&.id}", agent)
H.check('Commerce on: the conversation reads the store', code == 200 && body['error'].nil?, "http=#{code} state=#{body['state'] rescue nil}")
whatsapp.call('commerce-on')

switch.call('ZID_ENABLED', true)
code, body = H.api(:get, "#{base}/commerce/stores", admin)
H.check('provider switch on: Zid offered', code == 200 && body['providers'].include?('zid'), body['providers'].inspect)
switch.call('ZID_ENABLED', false)
code, body = H.api(:get, "#{base}/commerce/stores", admin)
H.check('provider switch off: Zid no longer offered, WooCommerce unchanged', code == 200 && body['providers'] == ['woocommerce'] &&
                                                                              body['payload'].pluck('id') == [store.id], body['providers'].inspect)
code, = H.api(:get, "#{stores}/#{store.id}", agent)
H.check('provider switch off: the WooCommerce store still reads', code == 200, "http=#{code}")
whatsapp.call('zid-switched-off')

Account.find_each { |a| a.disable_features!('lynomia_commerce') }
code, = H.api(:get, "#{base}/commerce/stores", admin)
H.check('emergency off: Commerce settings refused', code == 401, "http=#{code}")
code, = H.api(:get, "#{stores}/#{store.id}", agent)
H.check('emergency off: conversation Commerce refused', code == 401, "http=#{code}")
whatsapp.call('emergency-off')
H.check('emergency off: store and encrypted credentials kept', store.reload.active? && store.credentials['consumer_secret'] == ENV.fetch('COMMERCE_WOO_SECRET') &&
                                                               !Commerce::Store.where(id: store.id).pluck(Arel.sql('credentials::text')).first.include?(ENV.fetch('COMMERCE_WOO_SECRET')))

account.reload.enable_features!('lynomia_commerce')
code, body = H.api(:get, "#{stores}/#{store.id}", agent)
H.check('switched back on: the conversation reads the store again', code == 200 && body['error'].nil?, "http=#{code}")
whatsapp.call('commerce-on-again')

H.write_results(File.join(__dir__, 'out', "commerce_switches_#{label}.json"))
