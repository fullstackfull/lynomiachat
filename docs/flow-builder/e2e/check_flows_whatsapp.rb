# frozen_string_literal: true

# Lynomia Flow Builder WhatsApp E2E (docs/flow-builder/10-e2e.md), scenarios A–F. Runs with `rails runner` in
# production mode on the staging harness database seeded by docs/chatwoot-upgrade/staging-harness/seed_pre_upgrade.rb.
#
# Real: the flows API (created, saved, published as Tenant A's administrator), Chatwoot's WhatsApp webhook endpoint with
# Meta's signature, the incoming message service, conversations, AgentBot's bot phase and handoff, the flow runtime and
# its lock, Chatwoot's message model and SendReplyJob through the WhatsApp Cloud provider, ActionService, Commerce's
# WooCommerce provider against the disposable local test store, Chatwoot's webhook delivery and SafeFetch.
# Simulated: Meta (FakeGraph, in process: its template list, sends and rejections), the customers (signed webhook payloads),
# n8n (a local HTTP catcher), the passing of 24 hours (the customer's last message is dated back).
# Jobs run inline; scheduled jobs (reply timeouts) are only recorded.
require_relative '../../chatwoot-upgrade/staging-harness/lib'
require 'socket'

# The local WooCommerce test store and the n8n stand-in are real HTTP on localhost: the harness' catch-all 404 stub is
# dropped. Meta stays FakeGraph, and any other host still fails closed (WebMock refuses the connection).
WebMock::StubRegistry.instance.request_stubs.delete_if { |stub| stub.request_pattern.to_s.include?('/.*/') }

HARNESS = File.join(__dir__, '..', '..', 'chatwoot-upgrade', 'staging-harness')
ids = JSON.parse(File.read(File.join(HARNESS, 'out', 'seed_ids.json')))
ACCOUNT = Account.find(ids['A']['account_id'])
ADMIN = User.find_by!(email: ids['A']['admin'])
AGENT = User.find_by!(email: ids['A']['agent'])
INBOX = Inbox.find(ids['A']['inbox_id'])
ADMIN_B = User.find_by!(email: ids['B']['admin'])
PHONE = '+15550001001'
PHONE_ID = '1110001'
WABA = 'WABA-A'
DISPLAY = '+1 555-000-1001'
API = "/api/v1/accounts/#{ACCOUNT.id}".freeze

FakeGraph.reset!(wabas: { WABA => { name: 'Tenant A Biz', numbers: [{ id: PHONE_ID, display: DISPLAY, verified_name: 'Tenant A' }] } })

def graph_node(id, type, data = {}) = { id: id, type: type, position: { x: 0, y: 0 }, data: data }
def graph_edge(source, target, handle = 'next') = { id: "#{source}-#{handle}", source: source, sourceHandle: handle, target: target }

# A flow as an administrator makes it: created, saved, published, connected to the WhatsApp inbox.
def publish_flow(name, nodes, edges)
  _, created = H.api(:post, "#{API}/flows", ADMIN, { name: name })
  H.api(:put, "#{API}/flows/#{created['id']}/draft", ADMIN, { graph: { nodes: nodes, edges: edges } })
  status, body = H.api(:post, "#{API}/flows/#{created['id']}/publish", ADMIN)
  raise "#{name} not published: #{body}" unless status == 200

  H.api(:post, "#{API}/inboxes/#{INBOX.id}/set_agent_bot", ADMIN, { agent_bot: created['id'] })
  AgentBot.find(created['id'])
end

def inbound_message(from, type, content, name: 'Customer')
  H.post_webhook(PHONE, H.inbound(WABA, PHONE_ID, DISPLAY, from: from, id: "wamid.in-#{SecureRandom.hex(6)}", type: type,
                                                          content: content, name: name))
end

def customer_says(from, text, name: 'Customer') = inbound_message(from, 'text', { body: text }, name: name)
def tap_button(from, id, title) = inbound_message(from, 'interactive', { type: 'button_reply', button_reply: { id: id, title: title } })
def pick_row(from, id, title) = inbound_message(from, 'interactive', { type: 'list_reply', list_reply: { id: id, title: title } })

# What the provider sent Meta for this customer, oldest first.
def sent_to(to)
  FakeGraph.calls('POST', %r{/#{PHONE_ID}/messages\z}).map { |call| JSON.parse(call[:body]) }.select { |body| body['to'].to_s.delete('+') == to }
end

def texts_to(to) = sent_to(to).map { |body| body.dig('text', 'body') || body.dig('interactive', 'body', 'text') }
def conversation_of(from) = ContactInbox.find_by!(inbox: INBOX, source_id: from).conversations.order(:id).last
def flow_session_of(from) = FlowSession.where(conversation: conversation_of(from)).order(:id).last

# n8n stand-in: records the requests it receives.
CAUGHT = []
catcher = TCPServer.new('127.0.0.1', 3911)
Thread.new do
  loop do
    client = catcher.accept
    head = +''
    head << client.gets until head.end_with?("\r\n\r\n")
    headers = head.split("\r\n").drop(1).to_h { |line| line.split(': ', 2) }.transform_keys(&:downcase)
    CAUGHT << { path: head.split[1], headers: headers, body: client.read(headers['content-length'].to_i) }
    client.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}")
    client.close
  end
end

ACCOUNT.enable_features!('lynomia_flow_builder', 'lynomia_commerce')
team = ACCOUNT.teams.create!(name: 'Customer Care')
team.add_members([AGENT.id])
ACCOUNT.labels.create!(title: 'vip', color: '#1f93ff')
ACCOUNT.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'order_ref',
                                             attribute_display_name: 'Order reference', attribute_display_type: :number)

puts "\n== Scenario A: welcome menu, Track order (WooCommerce, the customer's own orders only), Customer care (team + handoff)"
store = Commerce::StoreConnection.new(account: ACCOUNT, user: ADMIN)
                                 .connect(provider: 'woocommerce', base_url: 'http://localhost:8081', name: 'Syria Cosmetics',
                                          credentials: { 'consumer_key' => ENV.fetch('WOO_CK'), 'consumer_secret' => ENV.fetch('WOO_CS') })
omar = ACCOUNT.contacts.create!(name: 'Omar', phone_number: '+966500000002')
ContactInbox.create!(contact: omar, inbox: INBOX, source_id: '966500000002')
store.customer_links.create!(account: ACCOUNT, contact: omar, external_customer_id: '2', match_source: :manual)
menu = [{ id: 'track', title: 'Track order' }, { id: 'care', title: 'Customer care' }]
flow_a = publish_flow('Welcome menu', [
                        graph_node('start', 'start'), graph_node('menu', 'buttons', text: 'Welcome to Syria Cosmetics! How can we help?', options: menu),
                        graph_node('ask', 'question', text: 'Please send your order number.', reply_type: 'number',
                                                store_as: { scope: 'context', key: 'order_no' }),
                        graph_node('look', 'commerce_lookup', mode: 'order_number', number: '{{flow.order_no}}'),
                        graph_node('found', 'send_message', text: 'Order #{{flow.order.number}} is {{flow.order.status}}.'),
                        graph_node('missing', 'send_message', text: 'We could not find that order on your account. A colleague will help you.'),
                        graph_node('team', 'assign_team', team_id: team.id),
                        graph_node('human', 'handoff', reason: 'Customer asked for customer care'),
                        graph_node('lost', 'handoff', reason: 'Order not found'), graph_node('end', 'end')
                      ], [
                        graph_edge('start', 'menu'), graph_edge('menu', 'ask', 'track'), graph_edge('menu', 'team', 'care'), graph_edge('ask', 'look', 'reply'),
                        graph_edge('look', 'found', 'found'), graph_edge('look', 'missing', 'not_found'), graph_edge('found', 'end'), graph_edge('missing', 'lost'),
                        graph_edge('team', 'human')
                      ])

customer_says('966500000002', 'hi', name: 'Omar')
buttons = sent_to('966500000002').last
button_ids = buttons && JSON.parse(buttons.dig('interactive', 'action')).fetch('buttons').map { |b| b.dig('reply', 'id') }
H.check('A1 the menu goes out as WhatsApp reply buttons whose ids are the flow options',
        buttons&.dig('interactive', 'type') == 'button' && button_ids == %w[lfb:menu:track lfb:menu:care], button_ids.inspect)
H.check('A2 the conversation is in the bot phase (pending, the flow bot as AI assignee)',
        conversation_of('966500000002').then { |c| c.pending? && c.ai_assignee == flow_a })
tap_button('966500000002', 'lfb:menu:track', 'Track order')
H.check('A3 the tap follows the option id: the order number is asked', texts_to('966500000002').last == 'Please send your order number.')
customer_says('966500000002', '18', name: 'Omar')
H.check('A4 the customer\'s own order is found in the WooCommerce store and its normalized status sent',
        texts_to('966500000002').last == 'Order #18 is refunded.', texts_to('966500000002').last.inspect)
H.check('A5 the session completed; the conversation stays with the flow', flow_session_of('966500000002').completed? && conversation_of('966500000002').pending?)

customer_says('966500000002', 'hi again', name: 'Omar')
tap_button('966500000002', 'lfb:menu:track', 'Track order')
customer_says('966500000002', '26', name: 'Omar')
H.check('A6 another customer\'s order number is not disclosed: not found, then handed to a human',
        texts_to('966500000002').last.to_s.start_with?('We could not find') && texts_to('966500000002').none? { |text| text.to_s.include?('#26') } &&
          flow_session_of('966500000002').handed_off? && conversation_of('966500000002').open?, texts_to('966500000002').last(2).inspect)
customer_says('966500000002', 'hello?', name: 'Omar')
H.check('A7 after the handoff the bot stays silent', texts_to('966500000002').last.to_s.start_with?('We could not find') &&
                                                     FlowSession.where(conversation: conversation_of('966500000002')).count == 2)

customer_says('966500000003', 'مرحبا', name: 'Sara')
tap_button('966500000003', 'lfb:menu:care', 'Customer care')
care = conversation_of('966500000003')
note = care.messages.where(private: true).last
H.check('A8 Customer care: Customer Care team assigned, conversation opened for humans, the reason left as a private note',
        care.open? && care.team_id == team.id && care.ai_assignee.nil? && note&.content == 'Customer asked for customer care' &&
          flow_session_of('966500000003').handed_off?, "status=#{care.status} team=#{care.team_id}")
H.check('A9 a private note never goes to WhatsApp', texts_to('966500000003').none? { |text| text.to_s.include?('asked for customer care') })

puts "\n== Scenario B: Arabic or English menu"
publish_flow('Language menu', [
               graph_node('start', 'start'),
               graph_node('lang', 'buttons', text: 'اختر اللغة / Choose your language',
                                       options: [{ id: 'ar', title: 'العربية' }, { id: 'en', title: 'English' }]),
               graph_node('ar_menu', 'list', text: 'كيف نساعدك؟', button_label: 'القائمة',
                                       options: [{ id: 'orders', title: 'طلباتي' }, { id: 'care', title: 'خدمة العملاء', description: 'تحدث مع فريقنا' }]),
               graph_node('en_menu', 'list', text: 'How can we help?', button_label: 'Menu',
                                       options: [{ id: 'orders', title: 'My orders' }, { id: 'care', title: 'Customer care', description: 'Talk to our team' }]),
               graph_node('ar_done', 'send_message', text: 'شكرًا لك'), graph_node('en_done', 'send_message', text: 'Thank you'), graph_node('end', 'end')
             ], [
               graph_edge('start', 'lang'), graph_edge('lang', 'ar_menu', 'ar'), graph_edge('lang', 'en_menu', 'en'),
               graph_edge('ar_menu', 'ar_done', 'orders'), graph_edge('ar_menu', 'ar_done', 'care'),
               graph_edge('en_menu', 'en_done', 'orders'), graph_edge('en_menu', 'en_done', 'care'),
               graph_edge('ar_done', 'end'), graph_edge('en_done', 'end')
             ])
customer_says('966500000004', 'السلام عليكم')
tap_button('966500000004', 'lfb:lang:ar', 'العربية')
list = sent_to('966500000004').last
action = JSON.parse(list&.dig('interactive', 'action') || '{}')
H.check('B1 Arabic: a WhatsApp list with the Arabic text, the node\'s button label and option ids',
        list&.dig('interactive', 'type') == 'list' && list.dig('interactive', 'body', 'text') == 'كيف نساعدك؟' && action['button'] == 'القائمة' &&
          action.dig('sections', 0, 'rows').pluck('id') == %w[lfb:ar_menu:orders lfb:ar_menu:care], list&.dig('interactive', 'action'))
pick_row('966500000004', 'lfb:ar_menu:care', 'خدمة العملاء')
H.check('B2 a list row reply follows its id', texts_to('966500000004').last == 'شكرًا لك' && flow_session_of('966500000004').completed?)
customer_says('966500000005', 'Hello')
tap_button('966500000005', 'lfb:lang:en', 'English')
english = JSON.parse(sent_to('966500000005').last.dig('interactive', 'action'))
H.check('B3 English: the English list with its own button label',
        english['button'] == 'Menu' && english.dig('sections', 0, 'rows').pluck('title') == ['My orders', 'Customer care'])
customer_says('966500000005', '2')
H.check('B4 a typed option number is accepted', texts_to('966500000005').last == 'Thank you')

puts "\n== Scenario C: VIP shared audience"
audience = ACCOUNT.custom_filters.create!(name: 'VIP numbers', filter_type: :contact, shared: true, user: nil,
                                          query: { payload: [{ attribute_key: 'phone_number', filter_operator: 'contains', values: ['96655'],
                                                               query_operator: nil }] })
publish_flow('VIP welcome', [
               graph_node('start', 'start'),
               graph_node('vip', 'audience_condition', conditions: [{ attribute_key: 'contact_audience', filter_operator: 'equal_to',
                                                                values: [audience.id], query_operator: nil }]),
               graph_node('tag', 'add_label', labels: ['vip']), graph_node('vip_hi', 'send_message', text: 'Welcome back, {{contact.name}}! You are a VIP.'),
               graph_node('hi', 'send_message', text: 'Welcome, {{contact.name}}!'), graph_node('end', 'end')
             ], [graph_edge('start', 'vip'), graph_edge('vip', 'tag', 'true'), graph_edge('vip', 'hi', 'false'), graph_edge('tag', 'vip_hi'), graph_edge('vip_hi', 'end'),
                 graph_edge('hi', 'end')])
customer_says('966550000006', 'hi', name: 'Lina')
customer_says('966500000007', 'hi', name: 'Karim')
H.check('C1 a contact in the shared audience gets the VIP branch and the vip label',
        texts_to('966550000006').last == 'Welcome back, Lina! You are a VIP.' && conversation_of('966550000006').label_list == ['vip'],
        texts_to('966550000006').last.inspect)
H.check('C2 a contact outside it gets the regular branch, no label',
        texts_to('966500000007').last == 'Welcome, Karim!' && conversation_of('966500000007').label_list.empty?, texts_to('966500000007').last.inspect)

puts "\n== Scenario D: a question stored in a contact custom attribute; a human reply stops the bot"
publish_flow('Order reference', [
               graph_node('start', 'start'),
               graph_node('ask', 'question', text: 'What is your order reference?', reply_type: 'number', max_attempts: 2,
                                       retry_text: 'Please send the reference in digits.',
                                       store_as: { scope: 'contact', key: 'order_ref' }, timeout_minutes: 30),
               graph_node('thanks', 'send_message', text: 'Thank you, we saved your reference.'), graph_node('human', 'handoff'), graph_node('end', 'end')
             ], [graph_edge('start', 'ask'), graph_edge('ask', 'thanks', 'reply'), graph_edge('ask', 'human', 'invalid'), graph_edge('thanks', 'end')])
HarnessAdapter::DELAYED.clear
customer_says('966500000008', 'hi', name: 'Huda')
H.check('D1 the question is asked and its reply timeout is a scheduled job',
        texts_to('966500000008').last == 'What is your order reference?' && HarnessAdapter::DELAYED.include?('Flows::RunJob'))
customer_says('966500000008', 'abc', name: 'Huda')
H.check('D2 an answer that does not fit is asked again with the retry text', texts_to('966500000008').last == 'Please send the reference in digits.')
customer_says('966500000008', '٤٥٦', name: 'Huda')
huda = Contact.find_by!(phone_number: '+966500000008')
H.check('D3 the Arabic-digit answer is stored in the contact attribute as a number',
        huda.custom_attributes['order_ref'] == 456 && texts_to('966500000008').last == 'Thank you, we saved your reference.',
        huda.custom_attributes.inspect)

customer_says('966500000009', 'hi', name: 'Yousef')
waiting = conversation_of('966500000009')
status, = H.api(:post, "#{API}/conversations/#{waiting.display_id}/messages", AGENT, { content: 'Hi Yousef, I will help you.' })
H.check('D4 an agent\'s reply hands the waiting session to humans (no automatic resume)',
        status == 200 && flow_session_of('966500000009').handed_off? && flow_session_of('966500000009').context['end_reason'] == 'human_reply',
        "http=#{status} #{flow_session_of('966500000009').attributes.slice('status', 'context')}")
customer_says('966500000009', '123', name: 'Yousef')
H.check('D5 the bot does not answer after the agent took over',
        texts_to('966500000009').last == 'Hi Yousef, I will help you.' && Contact.find_by!(phone_number: '+966500000009').custom_attributes['order_ref'].nil?)

puts "\n== Scenario E: webhook to an n8n endpoint"
flow_e = publish_flow('Notify n8n', [
                        graph_node('start', 'start'), graph_node('hook', 'webhook', url: 'http://127.0.0.1:3911/webhook/lynomia'),
                        graph_node('ok', 'send_message', text: 'Thanks, our team has your request.'), graph_node('end', 'end')
                      ], [graph_edge('start', 'hook'), graph_edge('hook', 'ok'), graph_edge('ok', 'end')])
ENV.delete('SAFE_FETCH_ALLOW_PRIVATE_NETWORK')
customer_says('966500000010', 'I need help', name: 'Nour')
H.check('E1 as shipped, SafeFetch refuses the private address; the flow goes on without waiting',
        CAUGHT.empty? && texts_to('966500000010').last == 'Thanks, our team has your request.' && flow_session_of('966500000010').completed?)
ENV['SAFE_FETCH_ALLOW_PRIVATE_NETWORK'] = 'true'
customer_says('966500000011', 'I need help', name: 'Rami')
call = CAUGHT.last
payload = call ? JSON.parse(call[:body]) : {}
signature = call && "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', flow_e.secret, "#{call[:headers]['x-chatwoot-timestamp']}.#{call[:body]}")}"
H.check('E2 self-hosted n8n receives one POST, signed with the flow bot\'s secret',
        CAUGHT.size == 1 && call[:path] == '/webhook/lynomia' && call[:headers]['x-chatwoot-signature'] == signature, "#{CAUGHT.size} request(s)")
H.check('E3 the payload carries the flow, the conversation and the reply; the flow does not wait for the answer',
        payload['event'] == 'flow_webhook' && payload.dig('flow', 'id') == flow_e.id && payload['reply'] == 'I need help' &&
          payload.dig('conversation', 'meta', 'sender', 'phone_number') == '+966500000011' && flow_session_of('966500000011').completed?)
ENV.delete('SAFE_FETCH_ALLOW_PRIVATE_NETWORK')

puts "\n== Tenancy and the message path"
status, = H.api(:get, "#{API}/flows/#{flow_e.id}", ADMIN_B)
H.check('T1 another account\'s administrator cannot read the flow', [401, 404].include?(status), "http=#{status}")
foreign_team = Account.find(ids['B']['account_id']).teams.create!(name: 'Other tenant team')
_, created = H.api(:post, "#{API}/flows", ADMIN, { name: 'Foreign references' })
H.api(:put, "#{API}/flows/#{created['id']}/draft", ADMIN,
      { graph: { nodes: [graph_node('start', 'start'), graph_node('team', 'assign_team', team_id: foreign_team.id), graph_node('end', 'end')],
                 edges: [graph_edge('start', 'team'), graph_edge('team', 'end')] } })
status, body = H.api(:post, "#{API}/flows/#{created['id']}/publish", ADMIN)
H.check('T2 a flow naming another account\'s team cannot be published',
        status == 422 && body['errors'].pluck('code').include?('unknown_team'), "http=#{status}")
H.check('T3 every message the flow sent went through Chatwoot: one Message for each Graph call',
        FakeGraph.calls('POST', %r{/#{PHONE_ID}/messages\z}).size == INBOX.messages.outgoing.where(private: false).count)

puts "\n== Scenario F: WhatsApp templates on Chatwoot's template path (WhatsApp API and coexistence numbers)"
graph_template_calls = lambda do |phone_id|
  FakeGraph.calls('POST', %r{/#{phone_id}/messages\z}).map { |call| JSON.parse(call[:body]) }.select { |body| body['type'] == 'template' }
end
template_to = ->(phone_id, to) { graph_template_calls.call(phone_id).select { |body| body['to'].to_s.delete('+') == to } }
draft_and_publish = lambda do |name, nodes, edges|
  _, created = H.api(:post, "#{API}/flows", ADMIN, { name: name })
  H.api(:put, "#{API}/flows/#{created['id']}/draft", ADMIN, { graph: { nodes: nodes, edges: edges } })
  H.api(:post, "#{API}/flows/#{created['id']}/publish", ADMIN)
end
one_template = ->(data) { [[graph_node('start', 'start'), graph_node('tpl', 'send_template', data), graph_node('end', 'end')],
                           [graph_edge('start', 'tpl'), graph_edge('tpl', 'end')]] }
order_update = ->(second) { { name: 'order_update', language: 'ar', params: { body: { '1' => '{{contact.name}}', '2' => second } } } }

INBOX.channel.sync_templates # Chatwoot's own template sync, from Meta (FakeGraph)
synced = INBOX.channel.reload.message_templates.map { |t| [t['name'], t['language'], t['status']] }
H.check('F1 the WhatsApp inbox has its templates from Chatwoot\'s sync (no flow-side template store)',
        synced.include?(%w[order_update ar APPROVED]) && synced.include?(%w[hello_world en_US APPROVED]), synced.inspect)

status, body = draft_and_publish.call('Wrong language', *one_template.call(order_update.call('{{flow.reply}}').merge(language: 'en')))
H.check('F2 an invalid language is refused at publish', status == 422 && body['errors'].pluck('code') == ['template_language_unavailable'], body.inspect)
status, body = draft_and_publish.call('Missing value', *one_template.call(order_update.call('').merge(params: { body: { '1' => '{{contact.name}}' } })))
H.check('F3 a missing template value is refused at publish',
        status == 422 && body['errors'].map { |e| [e['code'], e['detail']] } == [%w[template_param_missing body.2]], body.inspect)
tenant_b_inbox = Inbox.find(ids['B']['inbox_id'])
tenant_b_inbox.channel.update_columns(message_templates: [{ 'name' => 'tenant_b_offer', 'language' => 'ar', 'status' => 'APPROVED', 'category' => 'MARKETING',
                                                            'components' => [{ 'type' => 'BODY', 'text' => 'عرض خاص' }] }])
status, body = draft_and_publish.call('Foreign template', *one_template.call(name: 'tenant_b_offer', language: 'ar'))
H.check('F4 another account\'s template is not found: the flow cannot be published',
        status == 422 && body['errors'].pluck('code').uniq == ['template_not_found'], body.inspect)

flow_f = publish_flow('Order update template', [
                        graph_node('start', 'start'),
                        graph_node('ask', 'question', text: 'What is your order number?', store_as: { scope: 'context', key: 'order_no' }, timeout_minutes: 1440),
                        graph_node('thanks', 'send_message', text: 'Thanks {{contact.name}}.'),
                        graph_node('tpl_now', 'send_template', order_update.call('{{flow.order_no}}')),
                        graph_node('tpl_late', 'send_template', name: 'hello_world', language: 'en_US', params: {}), graph_node('end', 'end')
                      ], [graph_edge('start', 'ask'), graph_edge('ask', 'thanks', 'reply'), graph_edge('thanks', 'tpl_now'), graph_edge('tpl_now', 'end'),
                          graph_edge('ask', 'tpl_late', 'timeout'), graph_edge('tpl_late', 'end')])
customer_says('966500000020', 'hi', name: 'Mona')
customer_says('966500000020', '77', name: 'Mona')
sent = template_to.call(PHONE_ID, '966500000020').last
mona_template = conversation_of('966500000020').messages.outgoing.where(sender: flow_f).order(:id).last
H.check('F5 inside the window: the message and then the template, with the contact\'s name and the stored reply',
        texts_to('966500000020').include?('Thanks Mona.') && sent&.dig('template', 'name') == 'order_update' &&
          sent.dig('template', 'language', 'code') == 'ar' && sent.dig('template', 'components', 0, 'parameters').pluck('text') == %w[Mona 77],
        sent.inspect)
H.check('F6 it is a Chatwoot message carrying the composer\'s template_params, shown rendered in the conversation',
        mona_template&.content == 'مرحبا Mona، طلبك 77 في الطريق' && mona_template.additional_attributes.dig('template_params', 'processed_params') ==
          { 'body' => { '1' => 'Mona', '2' => '77' } } && mona_template.source_id.to_s.start_with?('wamid.') && flow_session_of('966500000020').completed?,
        mona_template&.attributes&.slice('content', 'source_id', 'status').inspect)

customer_says('966500000021', 'hi', name: 'Salem')
late = conversation_of('966500000021')
late.messages.incoming.update_all(created_at: 25.hours.ago) # the customer last wrote 25 hours ago
waiting = flow_session_of('966500000021')
Flows::RunJob.perform_now(late.id, 'wake', nil, waiting.id, waiting.step_token) # the recorded reply-timeout job, as the scheduler runs it
H.check('F7 after the 24-hour window the approved template goes out (Chatwoot sends templates outside the window)',
        !late.reload.can_reply? && template_to.call(PHONE_ID, '966500000021').last&.dig('template', 'name') == 'hello_world' && waiting.reload.completed?,
        waiting.attributes.slice('status', 'failure_code').inspect)
graph_before = FakeGraph.calls('POST', %r{/#{PHONE_ID}/messages\z}).size
status, reply = H.api(:post, "#{API}/conversations/#{late.display_id}/messages", AGENT, { content: 'A free-form reply' })
free_form = Message.find_by(id: reply['id'])
H.check('F8 outside the window a free-form message is refused by Chatwoot\'s existing protection (nothing reaches Meta)',
        status == 200 && free_form&.reload&.failed? && free_form.external_error == I18n.t('errors.whatsapp.message_outside_messaging_window') &&
          FakeGraph.calls('POST', %r{/#{PHONE_ID}/messages\z}).size == graph_before, free_form&.attributes&.slice('status', 'external_error').inspect)

publish_flow('Late plain message', [graph_node('start', 'start'), graph_node('ask', 'question', text: 'Your order number?', timeout_minutes: 1440),
                                    graph_node('late', 'send_message', text: 'Are you still there?'), graph_node('end', 'end')],
             [graph_edge('start', 'ask'), graph_edge('ask', 'end', 'reply'), graph_edge('ask', 'late', 'timeout'), graph_edge('late', 'end')])
customer_says('966500000022', 'hi', name: 'Dana')
plain = conversation_of('966500000022')
plain.messages.incoming.update_all(created_at: 25.hours.ago)
waiting = flow_session_of('966500000022')
Flows::RunJob.perform_now(plain.id, 'wake', nil, waiting.id, waiting.step_token)
H.check('F9 a Send Message after the window is not sent and never replaced by text: handed to humans (window_closed)',
        waiting.reload.handed_off? && waiting.context['end_reason'] == 'window_closed' && texts_to('966500000022') == ['Your order number?'] &&
          plain.reload.open?, waiting.attributes.slice('status', 'context').inspect)

publish_flow('Template without a value', *one_template.call(order_update.call('{{flow.order.number}}')))
customer_says('966500000023', 'hi', name: 'Basel')
H.check('F10 a variable without a value at run time: nothing sent, the session fails to humans (template_param_missing)',
        flow_session_of('966500000023').then { |s| s.failed? && s.failure_code == 'template_param_missing' } &&
          sent_to('966500000023').empty? && conversation_of('966500000023').open?)

publish_flow('Template, Meta refuses', *one_template.call(order_update.call('{{flow.reply}}')))
FakeGraph.failures[:send] = true
HarnessAdapter::DELAYED.clear
customer_says('966500000024', 'A-9', name: 'Rana')
FakeGraph.failures.delete(:send)
rejected = conversation_of('966500000024').messages.outgoing.where(private: false).order(:id).first
retried = HarnessAdapter::DELAYED.include?('Flows::RunJob') # the rejection job met the running job's lock: Sidekiq retries it after it
Flows::RunJob.perform_now(rejected.conversation_id, 'rejected', rejected.id)
H.check('F11 Meta rejects the template after the session completed: the message is failed, humans get the conversation, no text instead',
        rejected.reload.failed? && retried && flow_session_of('966500000024').completed? && conversation_of('966500000024').open? &&
          conversation_of('966500000024').messages.outgoing.where(private: false).count == 1,
        "#{rejected.attributes.slice('status', 'external_error')} conversation=#{conversation_of('966500000024').status}")

FakeGraph.wabas['WABA-COEX-A'] = { name: 'Tenant A Shop', numbers: [{ id: '3330001', display: '+1 555-000-3001', verified_name: 'Tenant A Shop',
                                                                       is_on_biz_app: true }] }
status, coex_body = H.api(:post, "#{API}/whatsapp/authorization", ADMIN,
                          { code: "coex-flow-#{SecureRandom.hex(3)}", waba_id: 'WABA-COEX-A', is_coexistence: true })
coex_inbox = Inbox.find_by(id: coex_body['id'])
both = publish_flow('Template on both numbers', *one_template.call(order_update.call('{{flow.reply}}')))
H.api(:post, "#{API}/inboxes/#{coex_inbox.id}/set_agent_bot", ADMIN, { agent_bot: both.id })
customer_says('966500000025', 'B-1', name: 'Hadi')
H.post_webhook('+15550003001', H.inbound('WABA-COEX-A', '3330001', '+1 555-000-3001', from: '966500000026', id: "wamid.in-#{SecureRandom.hex(6)}",
                                                                                      type: 'text', content: { body: 'B-1' }, name: 'Hadi'))
api_template = template_to.call(PHONE_ID, '966500000025').last&.dig('template')
coex_template = template_to.call('3330001', '966500000026').last&.dig('template')
H.check('F12 the same flow and node on a coexistence number: Chatwoot\'s same provider sends the same template, no provider branch',
        status == 200 && coex_inbox&.channel&.provider_config&.dig('is_coexistence') == true && both.inboxes.include?(coex_inbox) &&
          api_template.present? && api_template == coex_template && coex_template.dig('components', 0, 'parameters').pluck('text') == %w[Hadi B-1],
        "coex=#{status} #{coex_template.inspect}")
flow_templates = Message.where(sender_type: 'AgentBot').where("additional_attributes ? 'template_params'").count
H.check('F13 every template went through Chatwoot: one bot template Message per Graph template call',
        flow_templates == graph_template_calls.call(PHONE_ID).size + graph_template_calls.call('3330001').size, "messages=#{flow_templates}")

H.write_results(File.join(HARNESS, 'out', 'flow_whatsapp_results.json'))
