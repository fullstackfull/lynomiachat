# frozen_string_literal: true

# Existing WhatsApp API regression. Run it on the pre-upgrade code and again, unchanged, after the upgrade
# against the SAME migrated staging data. No reconnect, no credential change, no manual data fix in between.
# usage: rails runner check_existing_whatsapp.rb <label>
require_relative 'lib'

label = ARGV[0] || 'run'
ids = JSON.parse(File.read(File.join(__dir__, 'out', 'seed_ids.json')))
FakeGraph.reset!(wabas: {
                   'WABA-A' => { name: 'Tenant A Biz', numbers: [{ id: '1110001', display: '+1 555-000-1001', verified_name: 'Tenant A' }] },
                   'WABA-B' => { name: 'Tenant B Biz', business_id: 'BIZ-B', numbers: [{ id: '2220001', display: '+1 555-000-2001', verified_name: 'Tenant B' }] }
                 })
run = "#{label}-#{Time.now.to_i}"
snapshot = {}

[['A', 'WABA-A', '1110001', '15550001001', '15557770001'], ['B', 'WABA-B', '2220001', '15550002001', '15557770002']].each do |k, waba, pid, display, customer|
  t = ids[k]
  inbox = Inbox.find(t['inbox_id'])
  channel = inbox.channel
  admin = User.find_by(email: t['admin'])
  agent = User.find_by(email: t['agent'])
  before_config = channel.provider_config.deep_dup
  snapshot[k] = { provider: channel.provider, provider_config_keys: before_config.keys.sort, source: before_config['source'],
                  api_key_readable: channel.provider_config['api_key'].to_s.start_with?('EAAG') }
  H.check("#{k}: channel still whatsapp_cloud with readable token (no reconnect)",
          channel.provider == 'whatsapp_cloud' && snapshot[k][:api_key_readable])
  H.check("#{k}: channel not flagged for reauthorization", !channel.reauthorization_required?)

  # ---- inbound ----
  wamid = ->(s) { "wamid.IN-#{run}-#{k}-#{s}" }
  cases = [
    ['text Arabic', 'text', { body: 'مرحبا، أريد الاستفسار عن طلبي' }],
    ['text English + emoji', 'text', { body: 'Hello 👋 is my order ready? 😀' }],
    ['image', 'image', { id: 'media-img-1', mime_type: 'image/png', sha256: 'x', caption: 'صورة الفاتورة' }],
    ['video', 'video', { id: 'media-vid-1', mime_type: 'video/mp4', sha256: 'x' }],
    ['document', 'document', { id: 'media-doc-1', mime_type: 'application/pdf', sha256: 'x', filename: 'invoice.pdf' }],
    ['audio', 'audio', { id: 'media-aud-1', mime_type: 'audio/ogg; codecs=opus', sha256: 'x', voice: true }]
  ]
  cases.each_with_index do |(name, type, content), i|
    code = H.post_webhook("+#{display}", H.inbound(waba, pid, display, from: customer, id: wamid.call(i), type: type, content: content))
    msg = Message.find_by(source_id: wamid.call(i))
    ok = code == 200 && msg&.incoming? && msg.inbox_id == inbox.id
    ok &&= msg.content.to_s.include?(content[:body]) if type == 'text'
    ok &&= msg.attachments.any? && msg.attachments.first.file.attached? if type != 'text'
    H.check("#{k}: inbound #{name}", ok, "http=#{code} msg=#{msg&.id} attachments=#{msg&.attachments&.size}")
  end
  conversation = Message.find_by(source_id: wamid.call(0))&.conversation
  H.check("#{k}: all inbound in one conversation for the contact", conversation && conversation.messages.incoming.where('source_id LIKE ?', "wamid.IN-#{run}-#{k}-%").count == cases.size)
  contact_phone = conversation&.contact&.phone_number
  H.check("#{k}: contact phone mapped", contact_phone == "+#{customer}", contact_phone.inspect)

  # quoted reply (context.id -> in_reply_to)
  code = H.post_webhook("+#{display}", H.inbound(waba, pid, display, from: customer, id: wamid.call('q'), type: 'text',
                                                                                 content: { body: 'بخصوص الرسالة السابقة' }, context: { id: wamid.call(0) }))
  q = Message.find_by(source_id: wamid.call('q'))
  H.check("#{k}: inbound quoted reply linked (in_reply_to)", code == 200 && q.present? && q.content_attributes['in_reply_to'].present?,
          "in_reply_to=#{q&.content_attributes&.dig('in_reply_to').inspect}")

  # duplicate delivery of the same inbound wamid must not duplicate the message
  H.post_webhook("+#{display}", H.inbound(waba, pid, display, from: customer, id: wamid.call(0), type: 'text', content: { body: 'dup' }))
  H.check("#{k}: duplicate inbound webhook is deduplicated", Message.where(source_id: wamid.call(0)).count == 1)

  # ---- outbound (agent reply through the real API) ----
  sends_before = FakeGraph.calls('POST', %r{/#{pid}/messages\z}).size
  status, body = H.api(:post, "/api/v1/accounts/#{inbox.account_id}/conversations/#{conversation.display_id}/messages", agent,
                       { content: 'أهلاً، طلبك في الطريق 🚚', message_type: 'outgoing' })
  out = Message.find_by(id: body.is_a?(Hash) ? body['id'] : nil)&.reload
  sent = FakeGraph.calls('POST', %r{/#{pid}/messages\z})[sends_before..]
  req = sent.last && JSON.parse(sent.last[:body])
  H.check("#{k}: outbound text sent via Cloud API", status == 200 && out&.source_id.to_s.start_with?('wamid.FAKE') && req&.dig('text', 'body') == 'أهلاً، طلبك في الطريق 🚚',
          "http=#{status} source_id=#{out&.source_id} to=#{req&.dig('to') || req&.dig('recipient')}")
  H.check("#{k}: outbound uses Cloud API token of this tenant", sent.last && sent.last[:token] == channel.provider_config['api_key'])

  # outbound media (attachment on an agent message)
  m = conversation.messages.new(account_id: inbox.account_id, inbox_id: inbox.id, message_type: :outgoing, sender: agent, content: 'المرفق')
  m.attachments.new(account_id: inbox.account_id, file_type: :image,
                    file: { io: StringIO.new(FakeGraph::PNG), filename: 'receipt.png', content_type: 'image/png' })
  m.save!
  SendReplyJob.perform_now(m.id)
  m.reload
  media_req = FakeGraph.calls('POST', %r{/#{pid}/messages\z}).last
  media_body = media_req && JSON.parse(media_req[:body])
  H.check("#{k}: outbound image sent", m.source_id.to_s.start_with?('wamid.FAKE') && media_body&.dig('type') == 'image', "type=#{media_body&.dig('type')}")

  # outbound template
  status, body = H.api(:post, "/api/v1/accounts/#{inbox.account_id}/conversations/#{conversation.display_id}/messages", admin,
                       { content: 'مرحبا Ali، طلبك #55 في الطريق', message_type: 'outgoing',
                         template_params: { name: 'order_update', category: 'UTILITY', language: 'ar',
                                            processed_params: { body: { '1' => 'Ali', '2' => '#55' } } } })
  tpl_req = FakeGraph.calls('POST', %r{/#{pid}/messages\z}).last
  tpl_body = tpl_req && JSON.parse(tpl_req[:body])
  H.check("#{k}: outbound template sent", status == 200 && tpl_body&.dig('type') == 'template' && tpl_body.dig('template', 'name') == 'order_update',
          "http=#{status} type=#{tpl_body&.dig('type')}")

  # ---- statuses ----
  %w[sent delivered read].each do |st|
    H.post_webhook("+#{display}", H.status(waba, pid, display, wamid: out.source_id, status: st, recipient: customer))
  end
  H.check("#{k}: delivery/read status applied", out.reload.status == 'read', "status=#{out.status}")

  # ---- webhook verification handshake (GET) ----
  H.session.get("/webhooks/whatsapp/+#{display}", params: { 'hub.mode' => 'subscribe', 'hub.verify_token' => channel.provider_config['webhook_verify_token'], 'hub.challenge' => 'c123' })
  H.check("#{k}: webhook verify handshake", H.session.response.status == 200 && H.session.response.body.include?('c123'))

  # ---- forged webhook must be rejected for embedded-signup channels ----
  if before_config['source'] == 'embedded_signup'
    code = H.post_webhook("+#{display}", H.inbound(waba, pid, display, from: customer, id: wamid.call('forged'), type: 'text', content: { body: 'x' }), secret: 'wrong')
    H.check("#{k}: forged signature rejected", code == 401 && Message.find_by(source_id: wamid.call('forged')).nil?, "http=#{code}")
  end

  channel.reload
  H.check("#{k}: credentials untouched by traffic", channel.provider_config.slice('api_key', 'phone_number_id', 'business_account_id', 'source') ==
                                                    before_config.slice('api_key', 'phone_number_id', 'business_account_id', 'source'))
  H.check("#{k}: no /register call during normal traffic", FakeGraph.calls('POST', %r{/register\z}).empty?)
end

File.write(File.join(__dir__, 'out', "existing_snapshot_#{label}.json"), JSON.pretty_generate(snapshot))
H.write_results(File.join(__dir__, 'out', "existing_#{label}.json"))
