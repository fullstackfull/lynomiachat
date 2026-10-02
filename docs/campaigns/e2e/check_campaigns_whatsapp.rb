# frozen_string_literal: true

# Lynomia Campaigns WhatsApp E2E (docs/campaigns/07-e2e.md). Runs with `rails runner` in production mode on the staging
# harness database seeded by docs/chatwoot-upgrade/staging-harness/seed_pre_upgrade.rb.
#
# Real: Chatwoot's labels, contacts, saved filters (a shared audience) and campaigns APIs as Tenant A's administrator,
# the audience preview, the scheduler (TriggerScheduledItemsJob -> Campaigns::TriggerOneoffCampaignJob ->
# Campaign#trigger!), the WhatsApp campaign sender with Enterprise's campaign_recipients, Chatwoot's WhatsApp Cloud
# provider, Meta's signed status webhook. Simulated: Meta (FakeGraph, in process). Every recipient is a harness contact
# with a +1 555 test number: nothing can reach a customer, and any host other than Meta fails closed.
require_relative '../../chatwoot-upgrade/staging-harness/lib'

HARNESS = File.join(__dir__, '..', '..', 'chatwoot-upgrade', 'staging-harness')
ids = JSON.parse(File.read(File.join(HARNESS, 'out', 'seed_ids.json')))
ACCOUNT = Account.find(ids['A']['account_id'])
ADMIN = User.find_by!(email: ids['A']['admin'])
AGENT = User.find_by!(email: ids['A']['agent'])
INBOX = Inbox.find(ids['A']['inbox_id'])
ACCOUNT_B = Account.find(ids['B']['account_id'])
ADMIN_B = User.find_by!(email: ids['B']['admin'])
PHONE = '+15550001001'
PHONE_ID = '1110001'
WABA = 'WABA-A'
DISPLAY = '+1 555-000-1001'
API = "/api/v1/accounts/#{ACCOUNT.id}".freeze
TEMPLATE = { 'name' => 'hello_world', 'namespace' => '', 'category' => 'MARKETING', 'language' => 'en_US', 'processed_params' => {} }.freeze

FakeGraph.reset!(wabas: { WABA => { name: 'Tenant A Biz', numbers: [{ id: PHONE_ID, display: DISPLAY, verified_name: 'Tenant A' }] } })

# The templates the WhatsApp provider sent Meta, as [to, template name].
def template_sends
  FakeGraph.calls('POST', %r{/#{PHONE_ID}/messages\z}).map { |call| JSON.parse(call[:body]) }
           .select { |body| body['type'] == 'template' }.map { |body| [body['to'].to_s.delete('+'), body.dig('template', 'name')] }
end

def contact(name, email, phone, labels: [])
  status, body = H.api(:post, "#{API}/contacts", ADMIN, { name: name, email: email, phone_number: phone }.compact)
  raise "contact #{name}: #{status}" unless status == 200

  contact = Contact.find(body.dig('payload', 'contact', 'id'))
  H.api(:post, "#{API}/contacts/#{contact.id}/labels", ADMIN, { labels: labels }) if labels.any?
  contact
end

def preview(audience, user = ADMIN) = H.api(:post, "#{API}/campaigns/audience_preview", user, { audience: audience })

def create_campaign(title, audience, user: ADMIN, api: API, inbox: INBOX)
  H.api(:post, "#{api}/campaigns", user, { campaign: { title: title, message: 'Hello World', inbox_id: inbox.id, template_params: TEMPLATE,
                                                       scheduled_at: 1.minute.ago.iso8601, audience: audience } })
end

def digits(contact) = contact.phone_number.delete('+')

ACCOUNT.enable_features!(:whatsapp_campaign)
INBOX.channel.sync_templates # Chatwoot's own template sync, from Meta (FakeGraph)
H.check('setup: the WhatsApp inbox has the approved hello_world template from Meta',
        INBOX.channel.reload.message_templates.any? { |template| template['name'] == 'hello_world' })

# 1. Recipients: a label and a shared audience, made through Chatwoot's APIs.
H.api(:post, "#{API}/labels", ADMIN, { label: { title: 'e2e-eid', color: '#1f93ff' } })
label = ACCOUNT.labels.find_by!(title: 'e2e-eid')
layla = contact('Layla', 'layla@vip.campaigns.test', '+15550002001', labels: ['e2e-eid'])
omar = contact('Omar', 'omar@mail.campaigns.test', '+15550002002', labels: ['e2e-eid'])
sara = contact('Sara', 'sara@vip.campaigns.test', '+15550002003')
noor = contact('Noor', 'noor@mail.campaigns.test', '+15550002004')
ali = contact('Ali', 'ali@vip.campaigns.test', nil)
query = { payload: [{ attribute_key: 'email', filter_operator: 'contains', values: ['vip.campaigns.test'], query_operator: nil }] }
_, shared = H.api(:post, "#{API}/custom_filters", ADMIN, { custom_filter: { name: 'E2E VIP', filter_type: 'contact', shared: true, query: query } })
_, personal = H.api(:post, "#{API}/custom_filters", ADMIN, { custom_filter: { name: 'E2E mine', filter_type: 'contact', query: query } })
both = [{ type: 'Label', id: label.id }, { type: 'Audience', id: shared['id'] }]
H.check('1 a shared audience and a personal filter exist', shared['shared'] == true && personal['shared'] == false)

# 2. The preview: the server's count, each contact once.
counts = [[{ type: 'Label', id: label.id }], [{ type: 'Audience', id: shared['id'] }], both].map { |audience| preview(audience).last['count'] }
H.check('2 preview: label 2, audience 3 (Layla, Sara, Ali), both 4: Layla once', counts == [2, 3, 4], counts.inspect)
H.check('2 preview refuses a personal filter (422) and an agent (401)',
        preview([{ type: 'Audience', id: personal['id'] }]).first == 422 && preview(both, AGENT).first == 401)

# 3. The campaign, through Chatwoot's campaigns API: references, not conditions.
status, created = create_campaign('E2E Eid offer', both)
campaign = Campaign.find_by(display_id: created['id'], account: ACCOUNT)
H.check('3 the campaign is created with label and audience references', status == 200 && campaign.audience == both.map(&:stringify_keys) &&
                                                                       campaign.audience.to_json.exclude?('vip.campaigns.test'), created['audience'].inspect)
H.check('3 a personal filter is refused (422); an agent cannot create (401)',
        create_campaign('E2E personal', [{ type: 'Audience', id: personal['id'] }]).first == 422 &&
          create_campaign('E2E agent', both, user: AGENT).first == 401)
b_status, = create_campaign('E2E cross tenant', [{ type: 'Audience', id: shared['id'] }], user: ADMIN_B, api: "/api/v1/accounts/#{ACCOUNT_B.id}",
                                                                                     inbox: ACCOUNT_B.inboxes.first)
H.check('3 Tenant B cannot target Tenant A\'s audience (422)', b_status == 422 && ACCOUNT_B.campaigns.none?, "status #{b_status}")

# 4. Dynamic: a contact who joins the audience after the campaign was created receives it.
huda = contact('Huda', 'huda@vip.campaigns.test', '+15550002006')

# 5. The audience cannot go while the campaign is still to send.
delete_status, delete_body = H.api(:delete, "#{API}/custom_filters/#{shared['id']}", ADMIN)
unshare_status, = H.api(:patch, "#{API}/custom_filters/#{shared['id']}", ADMIN, { custom_filter: { shared: false } })
_, shown = H.api(:get, "#{API}/custom_filters/#{shared['id']}", ADMIN)
used_by = I18n.t('errors.custom_filters.used_by_campaigns', count: 1, locale: ACCOUNT.locale) # the account's language
H.check("5 deleting or unsharing the audience is refused (#{ACCOUNT.locale}): \"#{I18n.t('errors.custom_filters.used_by_campaigns', count: 1)}\"",
        delete_status == 422 && unshare_status == 422 && delete_body['error'] == used_by && shown['campaigns_count'] == 1, delete_body['error'])

# 6. The scheduler sends it: every recipient once, through Chatwoot's WhatsApp provider.
before = template_sends.size
TriggerScheduledItemsJob.perform_now
sends = template_sends.drop(before)
recipients = campaign.reload.campaign_recipients.includes(:contact).to_h { |recipient| [recipient.contact.name, recipient.status] }
H.check('6 the campaign is sent and completed', campaign.completed?, campaign.campaign_status)
H.check('6 Layla (label and audience), Omar (label), Sara (audience), Huda (joined later) get hello_world once each; Noor nothing',
        sends.sort == [layla, omar, sara, huda].map { |person| [digits(person), 'hello_world'] }.sort &&
          sends.none? { |to, _| to == digits(noor) }, sends.inspect)
H.check('6 campaign_recipients: 4 sent, Ali (no phone number) skipped by the channel check',
        recipients == { 'Layla' => 'sent', 'Omar' => 'sent', 'Sara' => 'sent', 'Huda' => 'sent', 'Ali' => 'skipped' }, recipients.inspect)

# 7. The scheduler again: nothing is sent twice.
TriggerScheduledItemsJob.perform_now
H.check('7 a second scheduler run sends nothing', template_sends.size == before + sends.size)

# 8. Meta's delivery status reaches the recipient row, as for any WhatsApp campaign.
wamid = campaign.campaign_recipients.find_by!(contact: layla).source_id
H.post_webhook(PHONE, H.status(WABA, PHONE_ID, DISPLAY, wamid: wamid, status: 'delivered', recipient: digits(layla)))
H.check('8 the delivered status updates Layla\'s recipient row', campaign.campaign_recipients.find_by!(contact: layla).delivered?)

# 9. Sent: the audience is free again.
delete_status, = H.api(:delete, "#{API}/custom_filters/#{shared['id']}", ADMIN)
H.check('9 once the campaign is completed the audience can be deleted', delete_status == 204 && !CustomFilter.exists?(shared['id']),
        "status #{delete_status}")

# 10. A label campaign is unchanged: its label's contacts, once each.
before = template_sends.size
_, label_only = create_campaign('E2E label only', [{ type: 'Label', id: label.id }])
TriggerScheduledItemsJob.perform_now
sends = template_sends.drop(before)
H.check('10 a label-only campaign sends to Layla and Omar once each',
        sends.sort == [layla, omar].map { |person| [digits(person), 'hello_world'] }.sort &&
          Campaign.find_by(display_id: label_only['id'], account: ACCOUNT).completed?, sends.inspect)

# 11. Nothing but Meta (FakeGraph) was called.
outside = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map { |signature| signature.uri.host }
                                  .reject { |host| %w[graph.facebook.com lookaside.fbsbx.com].include?(host) }
H.check('11 no host other than Meta (FakeGraph) was called', outside.empty?, outside.tally.inspect)

H.write_results(File.join(HARNESS, 'out', 'campaigns_whatsapp_results.json'))
