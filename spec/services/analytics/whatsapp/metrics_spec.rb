require 'rails_helper'

RSpec.describe Analytics::Whatsapp::Metrics do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:date_range) do
    Analytics::DateRange.new(account: account, since: '2026-10-01', until_value: '2026-10-07', group_by: 'day')
  end
  let(:other_account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:web_inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:web_conversation) { create(:conversation, account: account, inbox: web_inbox, contact: contact) }
  let(:template) { build_template(account, 'order_delivered', 'en_US') }

  def build_template(for_account, name, language)
    Whatsapp::MessageTemplate.create!(account: for_account, business_account_id: 'WABA1', name: name,
                                      language: language, category: 'UTILITY',
                                      components: [{ 'type' => 'BODY', 'text' => 'x' }])
  end

  def metrics(filters: {})
    described_class.new(
      account: account, date_range: date_range,
      filters: Analytics::FilterSet.new(account: account, family: :whatsapp, params: filters)
    )
  end

  def send_message(status: :sent, at: Time.utc(2026, 10, 2, 10, 0), on: nil, template_params: nil,
                   content_attributes: {})
    create(:message, account: account, inbox: (on || conversation).inbox, conversation: on || conversation,
                     message_type: :outgoing, status: status, created_at: at,
                     content_attributes: content_attributes,
                     additional_attributes: template_params ? { 'template_params' => template_params } : {})
  end

  describe 'messages_sent' do
    it 'counts outgoing WhatsApp messages inside the account-timezone window' do
      send_message
      # 22:00 UTC on 30 September is 1 October in Kuwait, so it belongs to this range.
      send_message(at: Time.utc(2026, 9, 30, 22, 0))
      # 20:00 UTC on 30 September is still 30 September locally, so it does not.
      send_message(at: Time.utc(2026, 9, 30, 20, 0))

      expect(metrics.messages_sent).to eq(2)
    end

    it 'ignores inboxes that are not WhatsApp' do
      send_message(on: web_conversation)
      expect(metrics.messages_sent).to eq(0)
    end

    it 'ignores incoming messages' do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :incoming, created_at: Time.utc(2026, 10, 2, 10, 0))

      expect(metrics.messages_sent).to eq(0)
    end

    it "never counts another account's messages" do
      other_channel = create(:channel_whatsapp, account: other_account, provider: 'whatsapp_cloud',
                                                sync_templates: false, validate_provider_config: false)
      other_contact = create(:contact, account: other_account)
      other_conversation = create(:conversation, account: other_account, inbox: other_channel.inbox, contact: other_contact)
      create(:message, account: other_account, inbox: other_channel.inbox, conversation: other_conversation,
                       message_type: :outgoing, created_at: Time.utc(2026, 10, 2, 10, 0))

      expect(metrics.messages_sent).to eq(0)
    end
  end

  describe 'coexistence echoes' do
    it 'excludes an echo from the sent count, because its delivered status is written locally' do
      send_message(status: :delivered, content_attributes: { external_echo: true })
      send_message(status: :delivered)

      expect(metrics.messages_sent).to eq(1)
      expect(metrics.delivered).to eq(1)
    end

    it 'reports the excluded echoes rather than hiding the exclusion' do
      send_message(status: :delivered, content_attributes: { external_echo: true })
      expect(metrics.coexistence_echoes).to eq(1)
    end
  end

  describe 'delivery states' do
    it 'counts a read message as delivered, because the ladder keeps only the furthest state' do
      send_message(status: :read)

      expect(metrics.delivered).to eq(1)
      expect(metrics.read).to eq(1)
    end

    it 'does not count a merely sent message as delivered' do
      send_message(status: :sent)
      expect(metrics.delivered).to eq(0)
    end

    it 'counts a failed message' do
      send_message(status: :failed, content_attributes: { external_error: '131049: Message undeliverable' })
      expect(metrics.failed).to eq(1)
    end
  end

  describe 'rates' do
    it 'reports delivery, read and failure as percentages of what was sent' do
      send_message(status: :delivered)
      send_message(status: :read)
      send_message(status: :failed)
      send_message(status: :sent)

      expect(metrics.delivery_rate).to eq(50.0)
      expect(metrics.read_rate).to eq(25.0)
      expect(metrics.failure_rate).to eq(25.0)
    end

    it 'returns nil rather than zero when nothing was sent' do
      expect(metrics.delivery_rate).to be_nil
      expect(metrics.read_rate).to be_nil
      expect(metrics.failure_rate).to be_nil
    end
  end

  describe 'template_messages_sent' do
    it 'counts only messages that carry template_params' do
      send_message(template_params: { 'name' => 'order_delivered', 'language' => 'en_US' })
      send_message

      expect(metrics.template_messages_sent).to eq(1)
    end
  end

  describe 'template_id filter' do
    it 'matches on the name and language the message recorded' do
      send_message(template_params: { 'name' => 'order_delivered', 'language' => 'en_US' })
      send_message(template_params: { 'name' => 'order_delivered', 'language' => 'ar' })
      send_message(template_params: { 'name' => 'welcome', 'language' => 'en_US' })

      expect(metrics(filters: { 'template_id' => template.id }).messages_sent).to eq(1)
    end

    it 'compares the language case-insensitively, as the sender does' do
      send_message(template_params: { 'name' => 'order_delivered', 'language' => 'EN_US' })

      expect(metrics(filters: { 'template_id' => template.id }).messages_sent).to eq(1)
    end

    it 'refuses a template id from another account' do
      foreign = build_template(other_account, 'order_delivered', 'en_US')

      expect { metrics(filters: { 'template_id' => foreign.id }) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::UnknownFilterValue') })
    end
  end

  describe 'series' do
    it 'emits one point per bucket including the zeros' do
      send_message(at: Time.utc(2026, 10, 1, 10, 0))
      points = metrics.series(:messages_sent)

      expect(points.length).to eq(7)
      expect(points.first).to eq(bucket: '2026-10-01', value: 1)
      expect(points.sum { |point| point[:value] }).to eq(1)
    end

    it 'buckets by the account timezone, not naive UTC' do
      send_message(at: Time.utc(2026, 10, 1, 22, 0))
      points = metrics.series(:messages_sent)

      expect(points.find { |point| point[:bucket] == '2026-10-02' }[:value]).to eq(1)
      expect(points.find { |point| point[:bucket] == '2026-10-01' }[:value]).to eq(0)
    end
  end

  describe 'breakdowns' do
    it 'groups templates by the name and language the message recorded' do
      send_message(template_params: { 'name' => 'order_delivered', 'language' => 'en_US' })
      send_message(template_params: { 'name' => 'order_delivered', 'language' => 'en_US' })
      send_message(template_params: { 'name' => 'welcome', 'language' => 'ar' })

      rows = metrics.breakdown(:template)

      expect(rows.first).to eq(id: 'order_delivered:en_US', label: 'order_delivered (en_US)', value: 2)
      expect(rows.last).to eq(id: 'welcome:ar', label: 'welcome (ar)', value: 1)
    end

    it 'groups failures by the refusal Meta gave, verbatim' do
      send_message(status: :failed, content_attributes: { external_error: '131049: Message undeliverable' })
      send_message(status: :failed, content_attributes: { external_error: '131049: Message undeliverable' })
      send_message(status: :failed, content_attributes: { external_error: '131042: Business eligibility payment issue' })

      rows = metrics.breakdown(:failure)

      expect(rows.first).to eq(id: '131049: Message undeliverable', label: '131049: Message undeliverable', value: 2)
    end

    it 'groups by inbox with the inbox name' do
      send_message
      rows = metrics.breakdown(:inbox)

      expect(rows).to eq([{ id: inbox.id, label: inbox.name, value: 1 }])
    end
  end
end
