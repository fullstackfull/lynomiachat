require 'rails_helper'

# Commerce triggers in Chatwoot automation (docs/automation/04-commerce-triggers.md): a new read of a linked customer's
# orders → normalized change → Chatwoot's dispatcher → AutomationRuleListener → existing conditions and actions.
RSpec.describe AutomationRuleListener do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:store) { create(:commerce_store, account: account) }
  let(:contact) { create(:contact, account: account, email: 'layla@example.com') }
  let(:link) { create(:commerce_customer_link, store: store, contact: contact, external_customer_id: '7') }
  let!(:older) { create(:conversation, account: account, inbox: inbox, contact: contact, last_activity_at: 2.days.ago) }
  let!(:latest) { create(:conversation, account: account, inbox: inbox, contact: contact, last_activity_at: 1.hour.ago) }
  let(:order) do
    lambda do |status|
      { 'external_order_id' => '23', 'order_number' => '1023', 'status' => status, 'payment_status' => 'paid', 'currency' => 'SAR',
        'total' => '120.00', 'created_at' => '2026-09-20T10:00:00Z', 'shipments' => [] }
    end
  end
  let(:read) { ->(orders, at) { Commerce::Cache::Result.new(value: orders, fetched_at: at.utc.iso8601, stale: false, error: nil) } }
  let(:shipped_rule) do
    account.automation_rules.create!(
      name: 'Shipped', event_name: 'commerce_order_shipped',
      conditions: [{ 'attribute_key' => 'commerce_event_provider', 'filter_operator' => 'equal_to', 'values' => ['woocommerce'],
                     'query_operator' => nil }],
      actions: [{ 'action_name' => 'add_label', 'action_params' => ['shipped'] },
                { 'action_name' => 'send_webhook_event', 'action_params' => ['https://n8n.example.com/webhook/shipped'] }]
    )
  end

  before { account.enable_features!('lynomia_commerce') }

  def ship!
    Commerce::ContactMetric.record(link, read.call([order.call('processing')], 2.minutes.ago))
    perform_enqueued_jobs(only: EventDispatcherJob) do
      Commerce::ContactMetric.record(link, read.call([order.call('shipped')], 1.minute.ago))
    end
  end

  it 'runs the rule on the contact\'s latest conversation with the existing actions, and the webhook carries the event' do
    shipped_rule

    ship!

    expect(latest.reload.label_list).to eq(['shipped'])
    expect(older.reload.label_list).to be_empty
    webhook = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |job| job['job_class'] == 'WebhookJob' }
    url, payload = ActiveJob::Arguments.deserialize(webhook['arguments'])
    expect(url).to eq('https://n8n.example.com/webhook/shipped')
    expect(payload[:event]).to eq('automation_event.commerce_order_shipped')
    expect(payload[:commerce]).to include(event: 'commerce_order_shipped', store_id: store.id, provider: 'woocommerce')
    expect(payload[:commerce][:order]).to include('number' => '1023', 'status' => 'shipped')
    expect(a_request(:any, /.*/)).not_to have_been_made
  end

  it 'emits nothing on the first read, on a cached read, or when no active rule wants the event' do
    shipped_rule
    expect(Rails.configuration.dispatcher).not_to receive(:dispatch)

    Commerce::ContactMetric.record(link, read.call([order.call('shipped')], 2.minutes.ago))
    Commerce::ContactMetric.record(link, read.call([order.call('shipped')], 2.minutes.ago))
    shipped_rule.update!(active: false)
    Commerce::ContactMetric.record(link, read.call([order.call('delivered')], 1.minute.ago))
  end

  it 'runs a rule once per event, however often the event is delivered' do
    rule = account.automation_rules.create!(name: 'Note', event_name: 'commerce_order_paid', conditions: [],
                                            actions: [{ 'action_name' => 'add_private_note', 'action_params' => ['Paid order'] }])
    event = Events::Base.new('commerce.order_paid', Time.zone.now, contact: contact, store_id: store.id, provider: 'woocommerce',
                                                                   event_name: 'commerce_order_paid', order: {}, event_id: "#{link.id}:abc:paid:1")

    2.times { described_class.instance.commerce_order_paid(event) }

    expect(latest.messages.where(private: true, content: 'Paid order').count).to eq(1)
    expect(rule.reload).to be_active
  end

  it 'matches the event\'s platform, not the contact\'s other links, and skips contacts without a conversation' do
    shipped_rule.update!(conditions: [{ 'attribute_key' => 'commerce_event_provider', 'filter_operator' => 'equal_to',
                                        'values' => ['salla'], 'query_operator' => nil }])
    ship!
    expect(latest.reload.label_list).to be_empty

    lonely = create(:contact, account: account)
    event = Events::Base.new('commerce.order_shipped', Time.zone.now, contact: lonely, event_name: 'commerce_order_shipped',
                                                                      provider: 'salla', event_id: 'x')
    expect { described_class.instance.commerce_order_shipped(event) }.not_to raise_error
  end

  it 'never chains: what the rule changed does not trigger other rules' do
    shipped_rule
    account.automation_rules.create!(name: 'Chained', event_name: 'conversation_updated', actions: [{ 'action_name' => 'add_label',
                                                                                                      'action_params' => ['chained'] }],
                                     conditions: [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'],
                                                    'query_operator' => nil }])

    perform_enqueued_jobs(only: EventDispatcherJob) { ship! }

    expect(latest.reload.label_list).to eq(['shipped'])
  end

  it 'refuses Commerce rules that would message the customer, wait, or run without Lynomia Commerce' do
    base = { name: 'x', event_name: 'commerce_order_shipped', conditions: [] }
    message = account.automation_rules.new(base.merge(actions: [{ 'action_name' => 'send_message', 'action_params' => ['Shipped!'] }]))
    delayed = account.automation_rules.new(base.merge(actions: [], execution_delay: 30))
    event_condition = account.automation_rules.new(name: 'x', event_name: 'conversation_created', actions: [],
                                                   conditions: [{ 'attribute_key' => 'commerce_event_provider', 'filter_operator' => 'equal_to',
                                                                  'values' => ['woocommerce'], 'query_operator' => nil }])

    expect([message, delayed, event_condition].map(&:valid?)).to eq([false, false, false])
    expect(message.errors[:actions].join).to include('send_message')

    account.disable_features!('lynomia_commerce')
    expect(account.automation_rules.new(base.merge(actions: []))).not_to be_valid
  end

  it 'leaves one log line per rule and event: ids, outcome and duration, no contact data' do
    shipped_rule
    lines = []
    allow(Rails.logger).to(receive(:info).and_wrap_original do |original, message|
      lines << message if message.to_s.include?('[Lynomia::Automation]')
      original.call(message)
    end)

    ship!
    event = Events::Base.new('commerce.order_shipped', Time.zone.now, contact: contact, event_name: 'commerce_order_shipped',
                                                                      store_id: store.id, provider: 'woocommerce', order: {},
                                                                      event_id: "#{link.id}:replay")
    2.times { described_class.instance.commerce_order_shipped(event) }

    entries = lines.map { |line| JSON.parse(line.delete_prefix('[Lynomia::Automation] ')) }
    expect(entries.pluck('outcome')).to eq(%w[executed executed duplicate])
    expect(entries.first).to include('rule_id' => shipped_rule.id, 'trigger' => 'commerce_order_shipped',
                                     'actions' => %w[add_label send_webhook_event])
    expect(entries.first['duration_ms']).to be_a(Numeric)
    expect(lines.join).not_to include(contact.email)
  end

  it 'stops Commerce triggers when the extensions are switched off' do
    shipped_rule

    with_modified_env LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED: 'false' do
      ship!
    end

    expect(latest.reload.label_list).to be_empty
  end
end
