# Lynomia Campaigns at volume (docs/campaigns/06-performance.md). Run with `rails runner` in the E2E environment, on an
# Audience perf account (docs/audience/e2e/perf.rb seed <contacts>: contacts, two WooCommerce stores whose hosts are
# never called, links, summaries, conversations, 5% tagged vip).
#
#   measure <contacts>  four shared audiences (basic, conversation, Commerce, composite) in that account, an SMS and a
#                       WhatsApp Cloud inbox, and the account's `vip` label; for each audience, alone and beside the label:
#                       - the preview count as POST /campaigns/audience_preview computes it (median / max of 5 uncached runs)
#                       - dispatch resolution: the campaign's recipients iterated as the Enterprise WhatsApp sender
#                         iterates them (find_each), with the SQL statements counted per batch (no N+1); nothing sent
#                       then two real sends through Chatwoot's senders, with each channel's provider call replaced in this
#                       process only (nothing leaves it): an SMS campaign on the basic audience + vip, and a WhatsApp
#                       campaign (Enterprise: campaign_recipients rows) on the composite audience + vip, and the same WhatsApp
#                       campaign on the vip label alone as the baseline of the unchanged sender; EXPLAIN ANALYZE
#                       of the composite count and of one dispatch batch; outbound HTTP counted (must be 0).
#                       Contacts without a phone number get a synthetic +1555… one (perf data only). Everything else the run
#                       creates is removed at the end.
require 'json'
require 'net/http'

module CountedHttp
  def request(*)
    $campaign_http_calls += 1 # rubocop:disable Style/GlobalVars
    super
  end
end
$campaign_http_calls = 0 # rubocop:disable Style/GlobalVars
Net::HTTP.prepend(CountedHttp)

# The provider calls, replaced for this process: they return what a provider returns, and count.
module PerfSms
  def send_text_message(*)
    $campaign_sent += 1 # rubocop:disable Style/GlobalVars
    "perf-sms-#{$campaign_sent}" # rubocop:disable Style/GlobalVars
  end
end

module PerfWhatsapp
  def send_template(*)
    $campaign_sent += 1 # rubocop:disable Style/GlobalVars
    "wamid.perf.#{SecureRandom.hex(8)}"
  end
end
$campaign_sent = 0 # rubocop:disable Style/GlobalVars
Channel::Sms.prepend(PerfSms)
Channel::Whatsapp.prepend(PerfWhatsapp)

TEMPLATE = { 'name' => 'perf_offer', 'language' => 'en', 'status' => 'APPROVED', 'category' => 'MARKETING',
             'components' => [{ 'type' => 'BODY', 'text' => 'Eid offer for {{1}}' }] }.freeze

def report(result) = puts("SIM #{result.to_json}")

def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000

def spread(times)
  sorted = times.sort
  { median_ms: sorted[sorted.size / 2].round(1), max_ms: sorted.last.round(1) }
end

def condition(key, operator, values, query_operator = nil)
  { 'attribute_key' => key, 'filter_operator' => operator, 'values' => values, 'query_operator' => query_operator }
end

def payloads
  {
    'basic' => [condition('email', 'contains', ['perf1'])],
    'conversation' => [condition('conversation_status', 'equal_to', %w[open resolved])],
    'commerce' => [condition('commerce_spend_sar', 'is_greater_than', ['1000'])],
    'composite' => [condition('commerce_spend_sar', 'is_greater_than', ['1000'], 'AND'), condition('conversation_status', 'equal_to', ['open'], 'AND'),
                    condition('labels', 'equal_to', ['vip'])]
  }
end

# The SQL statements a block runs (cache, schema and transaction statements aside).
def counting_queries
  count = 0
  callback = lambda do |*, payload|
    count += 1 unless payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/)
  end
  result = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }
  [result, count]
end

def preview_count(campaign)
  runs = Array.new(5) do
    ActiveRecord::Base.uncached do
      started = clock
      count = campaign.audience_contacts.count
      [clock - started, count]
    end
  end
  spread(runs.map(&:first)).merge(count: runs.first.last)
end

def dispatch_resolution(campaign)
  ActiveRecord::Base.uncached do
    started = clock
    ids, queries = counting_queries do
      [].tap { |seen| campaign.audience_contacts.find_each { |contact| seen << contact.id } }
    end
    batches = (ids.size / 1000.0).ceil
    { recipients: ids.size, unique: ids.uniq.size, ms: (clock - started).round(1), batches: batches, sql_statements: queries }
  end
end

def explain(sql) = ActiveRecord::Base.connection.select_values("EXPLAIN (ANALYZE, BUFFERS) #{sql}")

def send_campaign(campaign, service)
  $campaign_sent = 0 # rubocop:disable Style/GlobalVars
  started = clock
  _, queries = counting_queries { ActiveRecord::Base.uncached { service.new(campaign: campaign).perform } }
  { ms: (clock - started).round(1), sent: $campaign_sent, sql_statements: queries, status: campaign.reload.campaign_status } # rubocop:disable Style/GlobalVars
end

def whatsapp_inbox(account, size)
  number = "+1555#{size.to_s.rjust(7, '0')}"
  channel_id = Channel::Whatsapp.insert!({ account_id: account.id, phone_number: number, provider: 'whatsapp_cloud',
                                           provider_config: { 'api_key' => 'unused', 'phone_number_id' => 'perf', 'business_account_id' => 'perf' },
                                           message_templates: [TEMPLATE], message_templates_last_updated: Time.current,
                                           created_at: Time.current, updated_at: Time.current }, returning: :id).rows.first.first
  Inbox.create!(account: account, name: 'Perf WhatsApp', channel: Channel::Whatsapp.find(channel_id))
end

def measure(size)
  account = Account.find_by!(name: "Lynomia Audience Perf #{size}")
  admin = account.users.find_by!(email: "perf_admin_#{size}@audience.lynomia.local")
  phoned = account.contacts.where(phone_number: [nil, '']).update_all("phone_number = '+1555' || lpad(id::text, 9, '0')")
  label = account.labels.find_or_create_by!(title: 'vip')
  label_created = label.previously_new_record?
  sms = Inbox.create!(account: account, name: 'Perf SMS', channel: Channel::Sms.create!(account: account, phone_number: "+1666#{size}"))
  whatsapp = whatsapp_inbox(account, size)
  feature_was = account.feature_enabled?(:whatsapp_campaign)
  account.enable_features!(:whatsapp_campaign)
  audiences = payloads.to_h do |kind, payload|
    [kind, account.custom_filters.create!(user: admin, filter_type: :contact, shared: true, name: "Perf campaign #{kind}", query: { payload: payload })]
  end

  results = audiences.to_h do |kind, audience|
    alone = account.campaigns.create!(title: "Perf #{kind}", message: 'Perf', inbox: sms, audience: [{ type: 'Audience', id: audience.id }])
    with_label = account.campaigns.create!(title: "Perf #{kind} + vip", message: 'Perf', inbox: sms,
                                           audience: [{ type: 'Label', id: label.id }, { type: 'Audience', id: audience.id }])
    [kind, { members: audience.members.count, preview: preview_count(alone), preview_with_vip: preview_count(with_label),
             dispatch: dispatch_resolution(alone), dispatch_with_vip: dispatch_resolution(with_label) }]
  end

  sms_campaign = account.campaigns.create!(title: 'Perf SMS send', message: 'Eid offer for {{contact.name}}', inbox: sms,
                                           audience: [{ type: 'Label', id: label.id }, { type: 'Audience', id: audiences['basic'].id }])
  whatsapp_campaign = account.campaigns.create!(title: 'Perf WhatsApp send', message: 'Eid offer', inbox: whatsapp,
                                                audience: [{ type: 'Label', id: label.id }, { type: 'Audience', id: audiences['composite'].id }],
                                                template_params: { 'name' => TEMPLATE['name'], 'namespace' => 'perf', 'category' => 'MARKETING',
                                                                   'language' => 'en', 'processed_params' => { 'body' => { '1' => '{{contact.name}}' } } })
  label_only = account.campaigns.create!(title: 'Perf WhatsApp label only', message: 'Eid offer', inbox: whatsapp,
                                         audience: [{ type: 'Label', id: label.id }], template_params: whatsapp_campaign.template_params)
  whatsapp_send = lambda do |campaign|
    send_campaign(campaign, Whatsapp::OneoffCampaignService)
      .merge(expected: campaign.audience_contacts.count, recipients: campaign.campaign_recipients.group(:status).count)
  end
  sends = {
    sms_basic_plus_vip: send_campaign(sms_campaign, Sms::OneoffSmsCampaignService).merge(expected: sms_campaign.audience_contacts.count),
    whatsapp_composite_plus_vip: whatsapp_send.call(whatsapp_campaign),
    # The same sender on a label-only campaign (no audience): the per-recipient statements are the sender's own.
    whatsapp_label_only: whatsapp_send.call(label_only)
  }
  composite = account.campaigns.find_by!(title: 'Perf composite + vip')
  report({ contacts: account.contacts.count, phone_numbers_added: phoned, results: results, sends: sends,
           explain_composite_count: explain(composite.audience_contacts.unscope(:select).select('COUNT(*)').to_sql),
           explain_dispatch_batch: explain(composite.audience_contacts.reorder(:id).limit(1000).to_sql),
           http_calls: $campaign_http_calls }) # rubocop:disable Style/GlobalVars
ensure
  if account
    account.campaigns.where('title LIKE ?', 'Perf %').destroy_all
    account.custom_filters.where('name LIKE ?', 'Perf campaign %').delete_all
    [sms, whatsapp].compact.each { |inbox| inbox.channel.delete && inbox.delete }
    label.destroy! if label_created
    account.disable_features!(:whatsapp_campaign) unless feature_was
  end
end

size = Integer(ARGV[1] || '10000')
case ARGV[0]
when 'measure' then measure(size)
else abort 'usage: perf.rb measure <contacts>'
end
