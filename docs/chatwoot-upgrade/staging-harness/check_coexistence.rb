# frozen_string_literal: true

# WhatsApp Business (Coexistence) staging checks on the upgraded code, against the migrated staging DB that
# already holds Tenant A (manual API number) and Tenant B (Embedded Signup number) from before the upgrade.
# Meta is simulated in-process by FakeGraph; everything else is the real Rails stack.
require_relative 'lib'

ids = JSON.parse(File.read(File.join(__dir__, 'out', 'seed_ids.json')))
A = ids['A']
B = ids['B']
admin_a = User.find_by(email: A['admin'])
agent_a = User.find_by(email: A['agent'])
admin_b = User.find_by(email: B['admin'])
run = Time.now.to_i.to_s

FakeGraph.reset!(wabas: {
                   'WABA-A' => { name: 'Tenant A Biz', numbers: [{ id: '1110001', display: '+1 555-000-1001' }] },
                   'WABA-B' => { name: 'Tenant B Biz', numbers: [{ id: '2220001', display: '+1 555-000-2001' }] },
                   'WABA-COEX-A' => { name: 'Tenant A Shop', numbers: [{ id: '3330001', display: '+1 555-000-3001', verified_name: 'Tenant A Shop',
                                                                          is_on_biz_app: true }] },
                   'WABA-COEX-B' => { name: 'Tenant B Shop', numbers: [{ id: '4440001', display: '+1 555-000-4001', verified_name: 'Tenant B Shop',
                                                                          is_on_biz_app: true }] },
                   'WABA-STD' => { name: 'Std', numbers: [{ id: '5550001', display: '+1 555-000-5001', verified_name: 'Std' }] },
                   'WABA-MULTI' => { name: 'Multi', numbers: [{ id: '6660001', display: '+1 555-000-6001' },
                                                             { id: '6660002', display: '+1 555-000-6002' }] },
                   'WABA-HOOKFAIL' => { name: 'Hook', numbers: [{ id: '7770001', display: '+1 555-000-7001', is_on_biz_app: true }] }
                 })

# re-runnable: remove inboxes created by a previous run of this script
Channel::Whatsapp.where(phone_number: %w[+15550003001 +15550004001 +15550005001 +15550007001]).find_each { |ch| ch.inbox&.destroy! }

def authorize(user, account_id, params) = H.api(:post, "/api/v1/accounts/#{account_id}/whatsapp/authorization", user, params)
def counts = [Inbox.count, Channel::Whatsapp.count]

# ------------------------------------------------------------------ onboarding
puts "\n== Coexistence onboarding (WhatsApp Business App number, waba_id only)"
before_counts = counts
status, body = authorize(admin_a, A['account_id'], { code: "coex-a-#{run}", waba_id: 'WABA-COEX-A', is_coexistence: true })
H.check('onboarding: accepted with only code + waba_id (no business_id, no phone_number_id)', status == 200 && body['success'], "http=#{status} #{body}")
coex_inbox = Inbox.find_by(id: body['id'])
coex = coex_inbox&.channel
coex_inbox&.inbox_members&.find_or_create_by!(user: agent_a) # the agent works this inbox, like any other
cfg = coex&.provider_config || {}
H.check('onboarding: one inbox + one channel created', counts == before_counts.map { |c| c + 1 })
H.check('onboarding: same whatsapp_cloud provider and Embedded Signup source',
        coex&.provider == 'whatsapp_cloud' && cfg['source'] == 'embedded_signup', cfg.except('api_key', 'webhook_verify_token').inspect)
H.check('onboarding: Coexistence marker stored (is_coexistence: true)', cfg['is_coexistence'] == true)
H.check('onboarding: phone number resolved from the WABA', coex&.phone_number == '+15550003001' && cfg['phone_number_id'] == '3330001')
H.check('onboarding: inbox named by phone number (Lynomia naming kept)', coex_inbox&.name == '+15550003001', coex_inbox&.name)
H.check('onboarding: /register NOT called for a Business App number', FakeGraph.calls('POST', %r{/3330001/register\z}).empty?)
H.check('onboarding: no post-signup health check / verification probe', FakeGraph.calls('GET', %r{\A/3330001\z}).empty?)
sub = FakeGraph.calls('POST', %r{/WABA-COEX-A/subscribed_apps\z}).last
H.check('onboarding: app subscribed to WABA with messages + smb_message_echoes',
        sub && (JSON.parse(sub[:body])['subscribed_fields'] & %w[messages smb_message_echoes]).size == 2, sub&.dig(:body))
override = FakeGraph.calls('POST', %r{\A/3330001\z}).last
H.check('onboarding: webhook routed to this number only (phone-level override)',
        override && JSON.parse(override[:body]).dig('webhook_configuration', 'override_callback_uri') == "#{ENV.fetch('FRONTEND_URL')}/webhooks/whatsapp/+15550003001")
H.check('onboarding: channel not flagged for reauthorization', coex && !coex.reauthorization_required?)
H.check('onboarding: token kept server-side (token exchange done by backend with app secret)',
        FakeGraph.calls('GET', %r{/oauth/access_token\z}).last&.dig(:query, 'client_secret') == H::APP_SECRET)

puts "\n== Existing Embedded Signup flow unchanged (normal FINISH)"
status, body = authorize(admin_a, A['account_id'], { code: "std-#{run}", business_id: 'BIZ-STD', waba_id: 'WABA-STD', phone_number_id: '5550001' })
std = Inbox.find_by(id: body['id'])&.channel
H.check('standard signup: still works', status == 200 && std.present?, "http=#{status}")
H.check('standard signup: no Coexistence marker', std && !std.provider_config.key?('is_coexistence'), std&.provider_config&.keys.inspect)

# ------------------------------------------------------------------ idempotency
puts "\n== Idempotency"
subs_before = FakeGraph.calls('POST', /subscribed_apps\z/).size
before_counts = counts
status_dup, body_dup = authorize(admin_a, A['account_id'], { code: "coex-a-#{run}", waba_id: 'WABA-COEX-A', is_coexistence: true })
status_retry, = authorize(admin_a, A['account_id'], { code: "coex-a-retry-#{run}", waba_id: 'WABA-COEX-A', is_coexistence: true })
H.check('duplicate callback: rejected with a clear error', status_dup == 422 && body_dup['error'].to_s.include?('+15550003001'), body_dup.to_s)
H.check('retry callback: rejected the same way', status_retry == 422)
H.check('duplicate/retry: no duplicate inbox or channel', counts == before_counts)
H.check('duplicate/retry: no duplicate webhook subscription', FakeGraph.calls('POST', /subscribed_apps\z/).size == subs_before)
status_other, = authorize(admin_b, B['account_id'], { code: "coex-a-steal-#{run}", waba_id: 'WABA-COEX-A', is_coexistence: true })
H.check('same number from another tenant: rejected (global phone uniqueness)', status_other == 422 && counts == before_counts)

# ------------------------------------------------------------------ failures
puts "\n== Failure handling"
[
  ['expired authorization code', { code: "expired-#{run}", waba_id: 'WABA-COEX-B', is_coexistence: true }, 'verification code'],
  ['invalid WABA', { code: "c1-#{run}", waba_id: 'WABA-DOES-NOT-EXIST', is_coexistence: true }, 'phone numbers fetch failed'],
  ['invalid phone number id', { code: "c2-#{run}", waba_id: 'WABA-STD', phone_number_id: '999', is_coexistence: true }, 'No matching phone number'],
  ['ambiguous multi-number WABA without phone_number_id', { code: "c3-#{run}", waba_id: 'WABA-MULTI', is_coexistence: true }, 'Multiple phone numbers'],
  ['missing waba_id', { code: "c4-#{run}", is_coexistence: true }, 'waba_id'],
  ['missing code (user cancelled / no code)', { waba_id: 'WABA-COEX-B', is_coexistence: true }, 'code']
].each do |name, params, expect_msg|
  before_counts = counts
  status, body = authorize(admin_b, B['account_id'], params)
  H.check("failure: #{name} -> 422, nothing created", status == 422 && counts == before_counts && body.to_s.include?(expect_msg),
          "http=#{status} #{body.to_s[0, 140]}")
end
FakeGraph.failures[:meta_down] = true
before_counts = counts
status, body = authorize(admin_b, B['account_id'], { code: "down-#{run}", waba_id: 'WABA-COEX-B', is_coexistence: true })
FakeGraph.failures.delete(:meta_down)
H.check('failure: Meta API error (500) -> 422, nothing created', status == 422 && counts == before_counts, "http=#{status} #{body.to_s[0, 120]}")
FakeGraph.failures[:subscribe] = true
status, body = authorize(admin_b, B['account_id'], { code: "hook-#{run}", waba_id: 'WABA-HOOKFAIL', is_coexistence: true })
FakeGraph.failures.delete(:subscribe)
hook_channel = Inbox.find_by(id: body.is_a?(Hash) ? body['id'] : nil)&.channel
H.check('failure: webhook subscription error -> inbox kept but flagged "reconnect needed" (upstream 4.18 behaviour)',
        status == 200 && hook_channel&.reauthorization_required?, "http=#{status} reauth=#{hook_channel&.reauthorization_required?}")

# ------------------------------------------------------------------ messaging on the Business App number
puts "\n== Messaging on the WhatsApp Business App number"
disp = '15550003001'
cust = '966500000001'
wid = ->(s) { "wamid.COEX-#{run}-#{s}" }
code = H.post_webhook("+#{disp}", H.inbound('WABA-COEX-A', '3330001', disp, from: cust, id: wid.call(1), type: 'text',
                                                                           content: { body: 'السلام عليكم، هل الطلب جاهز؟ 🙏' }, name: 'عميل'))
in1 = Message.find_by(source_id: wid.call(1))
conv = in1&.conversation
H.check('customer -> WhatsApp: Arabic + emoji arrives in Lynomia', code == 200 && in1&.incoming? && in1.inbox_id == coex_inbox.id, "http=#{code}")
H.post_webhook("+#{disp}", H.inbound('WABA-COEX-A', '3330001', disp, from: cust, id: wid.call(2), type: 'image',
                                                                    content: { id: 'media-img-c', mime_type: 'image/png', sha256: 'x', caption: 'photo' }))
H.post_webhook("+#{disp}", H.inbound('WABA-COEX-A', '3330001', disp, from: cust, id: wid.call(3), type: 'document',
                                                                    content: { id: 'media-doc-c', mime_type: 'application/pdf', sha256: 'x', filename: 'po.pdf' }))
H.post_webhook("+#{disp}", H.inbound('WABA-COEX-A', '3330001', disp, from: cust, id: wid.call(4), type: 'audio',
                                                                    content: { id: 'media-aud-c', mime_type: 'audio/ogg; codecs=opus', sha256: 'x', voice: true }))
H.post_webhook("+#{disp}", H.inbound('WABA-COEX-A', '3330001', disp, from: cust, id: wid.call(5), type: 'video',
                                                                    content: { id: 'media-vid-c', mime_type: 'video/mp4', sha256: 'x' }))
media = [2, 3, 4, 5].map { |i| Message.find_by(source_id: wid.call(i)) }
H.check('customer -> WhatsApp: image, document, audio, video stored with attachments',
        media.all? { |m| m&.attachments&.first&.file&.attached? && m.conversation_id == conv&.id })
H.post_webhook("+#{disp}", H.inbound('WABA-COEX-A', '3330001', disp, from: cust, id: wid.call(6), type: 'text', content: { body: 'English reply to that' },
                                                                    context: { id: wid.call(1) }))
q = Message.find_by(source_id: wid.call(6))
H.check('customer -> WhatsApp: quoted reply linked', q&.content_attributes&.dig('in_reply_to') == in1&.id)

token_before = FakeGraph.calls('POST', %r{/3330001/messages\z}).size
status, body = H.api(:post, "/api/v1/accounts/#{A['account_id']}/conversations/#{conv.display_id}/messages", agent_a,
                     { content: 'أهلاً! الطلب جاهز للاستلام ✅' })
out = Message.find_by(id: body['id'])&.reload
send_req = FakeGraph.calls('POST', %r{/3330001/messages\z})[token_before..].last
H.check('Lynomia agent -> customer: sent through the Cloud API', status == 200 && out&.source_id.to_s.start_with?('wamid.FAKE'), "http=#{status}")
H.check('Lynomia agent -> customer: uses this number\'s own token', send_req && send_req[:token] == "EAAG-coex-a-#{run}")

# business owner replies from the WhatsApp Business App on the phone -> smb_message_echoes
H.post_webhook("+#{disp}", H.echo('WABA-COEX-A', '3330001', disp, to: cust, id: wid.call('echo1'), type: 'text',
                                                                  content: { body: 'رد من الهاتف 📱' }))
echo = Message.find_by(source_id: wid.call('echo1'))
H.check('owner -> customer from the phone app: appears in the SAME conversation as outgoing',
        echo&.outgoing? && echo.conversation_id == conv.id && echo.content == 'رد من الهاتف 📱', "type=#{echo&.message_type} conv=#{echo&.conversation_id}")
H.check('owner echo: marked as external echo, no Lynomia sender, not re-sent to Meta',
        echo&.content_attributes&.dig('external_echo') == true && echo.sender_id.nil? &&
        FakeGraph.calls('POST', %r{/3330001/messages\z}).size == token_before + 1)
H.post_webhook("+#{disp}", H.echo('WABA-COEX-A', '3330001', disp, to: cust, id: wid.call('echo1'), type: 'text', content: { body: 'رد من الهاتف 📱' }))
H.check('owner echo delivered twice: no duplicate', Message.where(source_id: wid.call('echo1')).count == 1)
H.post_webhook("+#{disp}", H.echo('WABA-COEX-A', '3330001', disp, to: cust, id: out.source_id, type: 'text', content: { body: out.content }))
H.check('echo of a message Lynomia itself sent: no duplicate', Message.where(source_id: out.source_id).count == 1)
H.post_webhook("+#{disp}", H.echo('WABA-COEX-A', '3330001', disp, to: cust, id: wid.call('echo2'), type: 'image',
                                                                  content: { id: 'media-img-e', mime_type: 'image/png', sha256: 'x' }))
echo_img = Message.find_by(source_id: wid.call('echo2'))
H.check('owner sends an image from the phone: synced with attachment', echo_img&.outgoing? && echo_img.attachments.first&.file&.attached?)
%w[sent delivered read].each { |st| H.post_webhook("+#{disp}", H.status('WABA-COEX-A', '3330001', disp, wamid: out.source_id, status: st, recipient: cust)) }
H.check('delivery/read statuses applied', out.reload.status == 'read', out.status)
H.check('no duplicate inbound messages in the conversation',
        conv.messages.where("source_id LIKE ?", "wamid.COEX-#{run}-%").reorder(nil).group(:source_id).count.values.all? { |n| n == 1 })

puts "\n== Token revoked"
FakeGraph.failures[:revoked_tokens] = ["EAAG-coex-a-#{run}"]
status, body = H.api(:post, "/api/v1/accounts/#{A['account_id']}/conversations/#{conv.display_id}/messages", agent_a, { content: 'after revoke' })
failed = Message.find_by(id: body['id'])&.reload
FakeGraph.failures.delete(:revoked_tokens)
H.check('revoked token: message marked failed with the Meta error (no silent loss)', failed&.status == 'failed' && failed.external_error.present?,
        "status=#{failed&.status} err=#{failed&.external_error}")

# ------------------------------------------------------------------ multi-tenant isolation
puts "\n== Multi-tenant isolation"
status, = authorize(admin_b, B['account_id'], { code: "x-#{run}", waba_id: 'WABA-COEX-A', inbox_id: coex_inbox.id })
H.check('tenant B cannot reauthorize tenant A inbox (inbox_id of A)', status == 404, "http=#{status}")
status, = authorize(admin_b, A['account_id'], { code: "x2-#{run}", waba_id: 'WABA-COEX-B', is_coexistence: true })
H.check('tenant B cannot create inboxes inside tenant A', status == 401, "http=#{status}")
status, = authorize(agent_a, A['account_id'], { code: "x3-#{run}", waba_id: 'WABA-COEX-A', inbox_id: coex_inbox.id })
H.check('tenant A agent cannot reauthorize/reconfigure (admin only)', status == 401, "http=#{status}")
status, = H.api(:get, "/api/v1/accounts/#{A['account_id']}/inboxes/#{coex_inbox.id}", admin_b)
H.check('tenant B cannot read tenant A inbox', status == 401, "http=#{status}")
status, = H.api(:patch, "/api/v1/accounts/#{A['account_id']}/inboxes/#{coex_inbox.id}", admin_b, { name: 'hijack' })
H.check('tenant B cannot modify tenant A inbox', status == 401 && coex_inbox.reload.name == '+15550003001', "http=#{status}")
_, list_b = H.api(:get, "/api/v1/accounts/#{B['account_id']}/inboxes", admin_b)
H.check('tenant B inbox list never contains tenant A inbox or token',
        list_b.to_json.exclude?("coex-a-#{run}") && list_b['payload'].none? { |i| i['id'] == coex_inbox.id })
_, as_agent = H.api(:get, "/api/v1/accounts/#{A['account_id']}/inboxes/#{coex_inbox.id}", agent_a)
H.check('tenant A agent does not receive the WhatsApp token', as_agent.to_json.exclude?("coex-a-#{run}") && !as_agent.key?('provider_config'))
# webhook routing: payload for A's number but phone_number_id of B's number -> must not land anywhere
before = Message.count
code = H.post_webhook('+15550004001', H.inbound('WABA-COEX-A', '2220001', disp, from: cust, id: wid.call('mix'), type: 'text', content: { body: 'mixed' }))
H.check('webhook with mismatched number/phone_number_id is not routed to any tenant', Message.count == before && Message.find_by(source_id: wid.call('mix')).nil?,
        "http=#{code}")
code = H.post_webhook("+#{disp}", H.inbound('WABA-COEX-A', '3330001', disp, from: cust, id: wid.call('forged'), type: 'text', content: { body: 'forged' }),
                      secret: 'not-the-app-secret')
H.check('webhook with a forged signature is rejected', code == 401 && Message.find_by(source_id: wid.call('forged')).nil?, "http=#{code}")
b_inbox = Inbox.find(B['inbox_id'])
H.check('tenant B conversations untouched by tenant A traffic', b_inbox.conversations.joins(:messages).where('messages.source_id LIKE ?', "wamid.COEX-#{run}-%").none?)

# ------------------------------------------------------------------ existing numbers untouched by all of the above
puts "\n== Existing numbers untouched"
[['A', '+15550001001'], ['B', '+15550002001']].each do |k, phone|
  ch = Channel::Whatsapp.find_by(phone_number: phone)
  H.check("existing #{k} number: no marker, not flagged, same token", !ch.provider_config.key?('is_coexistence') && !ch.reauthorization_required? &&
                                                                       ch.provider_config['api_key'].start_with?('EAAG'))
end

puts "\n== Inbox deletion (Coexistence number)"
FakeGraph.log.clear
status, = H.api(:delete, "/api/v1/accounts/#{A['account_id']}/inboxes/#{coex_inbox.id}", admin_a)
H.check('admin can delete the Coexistence inbox', [200, 204].include?(status) && Inbox.find_by(id: coex_inbox.id).nil?, "http=#{status}")
puts "INFO  Graph calls on delete: #{FakeGraph.log.map { |l| "#{l[:method]} #{l[:path]}" }.uniq.join(', ')}"
H.check('delete: other tenants\' numbers and WABAs not unsubscribed', FakeGraph.calls('DELETE', /WABA-(A|B)\b/).empty?)

H.write_results(File.join(__dir__, 'out', 'coexistence.json'))
