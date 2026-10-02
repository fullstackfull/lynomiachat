# Lynomia Campaigns browser E2E control (docs/campaigns/07-e2e.md), run with `rails runner` on the E2E database:
#
#   setup       account A gets WhatsApp campaigns, its WhatsApp inbox the approved templates Chatwoot would have synced
#               from Meta, an `e2e-eid` label and five test contacts (+1 555 numbers, @campaigns.lynomia.local), and the
#               shared audience "E2E VIP buyers" (email contains vip.campaigns); earlier E2E campaigns are removed
#   locale      account A's language (en | ar), for the screenshots
#   campaign    the latest E2E campaign as stored: audience, status, schedule
#   usage       the E2E audience: shared, the campaigns still to send that use it
#   teardown    E2E campaigns, the audience, the test contacts and the label removed; WhatsApp campaigns back as they were
#
# Nothing here sends: the campaign is scheduled for tomorrow and deleted by the run. Every result is one line: SIM <json>.
def report(result) = puts("SIM #{result.to_json}") # rubocop:disable Rails/Output

TEMPLATES = [
  { 'name' => 'hello_world', 'status' => 'APPROVED', 'category' => 'MARKETING', 'language' => 'en_US', 'id' => 't2',
    'components' => [{ 'type' => 'BODY', 'text' => 'Hello World' }] }
].freeze
AUDIENCE = 'E2E VIP buyers'.freeze
LABEL = 'e2e-eid'.freeze
CONTACTS = [
  ['E2E Layla', 'layla@vip.campaigns.lynomia.local', '+15550003001', true],
  ['E2E Omar', 'omar@campaigns.lynomia.local', '+15550003002', true],
  ['E2E Sara', 'sara@vip.campaigns.lynomia.local', '+15550003003', false],
  ['E2E Noor', 'noor@campaigns.lynomia.local', '+15550003004', false],
  ['E2E Huda', 'huda@vip.campaigns.lynomia.local', '+15550003005', false]
].freeze

def account_a = Account.find_by!(name: 'Lynomia Demo A')
def whatsapp_inbox = account_a.inboxes.find_by!(channel_type: 'Channel::Whatsapp')
def audience = account_a.custom_filters.find_by(name: AUDIENCE)
def e2e_campaigns = account_a.campaigns.where('title LIKE ?', 'E2E %')

def clean
  e2e_campaigns.destroy_all
  audience&.destroy!
  account_a.contacts.where('email LIKE ?', '%campaigns.lynomia.local').destroy_all
  account_a.labels.where(title: LABEL).destroy_all
end

case ARGV[0]
when 'setup'
  clean
  account_a.update!(locale: 'en')
  feature_was = account_a.feature_enabled?(:whatsapp_campaign)
  account_a.enable_features!(:campaigns, :whatsapp_campaign)
  whatsapp_inbox.channel.update_columns(message_templates: TEMPLATES, message_templates_last_updated: Time.current) # rubocop:disable Rails/SkipsModelValidations
  label = account_a.labels.create!(title: LABEL, color: '#1f93ff')
  CONTACTS.each do |name, email, phone, tagged|
    contact = account_a.contacts.create!(name: name, email: email, phone_number: phone)
    contact.update_labels([LABEL]) if tagged
  end
  admin = User.find_by!(email: 'admin_a@commerce.lynomia.local')
  shared = account_a.custom_filters.create!(user: admin, filter_type: :contact, shared: true, name: AUDIENCE,
                                            query: { payload: [{ attribute_key: 'email', filter_operator: 'contains',
                                                                 values: ['vip.campaigns.lynomia.local'], query_operator: nil }] })
  report({ account_id: account_a.id, inbox_name: whatsapp_inbox.name, label_id: label.id, audience_id: shared.id, feature_was: feature_was })
when 'locale'
  account_a.update!(locale: ARGV[1])
  report({ locale: account_a.locale })
when 'campaign'
  campaign = e2e_campaigns.order(:id).last
  report(campaign ? campaign.slice(:title, :audience, :campaign_status, :campaign_type).merge(scheduled_at: campaign.scheduled_at&.iso8601) : {})
when 'usage'
  report(audience ? { shared: audience.shared, campaigns: Audience::Usage.campaigns(audience).count } : { exists: false })
when 'teardown'
  clean
  account_a.update!(locale: 'en')
  account_a.disable_features!(:whatsapp_campaign) if ARGV[1] == 'false'
  report({ cleaned: true })
else
  abort 'usage: ctl.rb setup | locale en|ar | campaign | usage | teardown <whatsapp_campaign_was>'
end
