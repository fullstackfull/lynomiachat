require 'rails_helper'

# Commerce conditions in Chatwoot automation rules (docs/automation/03-audience-and-commerce-conditions.md): the Audience
# fields and semantics, for the contact of the rule's conversation, from local summaries only.
RSpec.describe AutomationRules::ConditionsFilterService do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:store) { create(:commerce_store, account: account) }
  let(:buyer) { create(:contact, account: account, email: 'buyer@example.com') }
  let(:unread) { create(:contact, account: account, email: 'unread@example.com') }
  let(:stranger) { create(:contact, account: account, email: 'stranger@example.com') }
  let(:conversations) { [buyer, unread, stranger].index_with { |contact| create(:conversation, account: account, inbox: inbox, contact: contact) } }

  before do
    account.enable_features!('lynomia_commerce')
    link = create(:commerce_customer_link, store: store, contact: buyer)
    Commerce::ContactMetric.create!(account: account, customer_link: link, orders_count: 3, active_orders_count: 1,
                                    last_purchase_at: 5.days.ago, spend: { 'SAR' => '1500.00' }, order_statuses: %w[completed processing],
                                    payment_statuses: %w[paid], shipment_statuses: %w[in_transit], fetched_at: Time.current)
    create(:commerce_customer_link, store: store, contact: unread)
  end

  def condition(key, operator, values, query_operator = nil)
    { 'attribute_key' => key, 'filter_operator' => operator, 'values' => values, 'query_operator' => query_operator }
  end

  def rule_with(*conditions)
    account.automation_rules.create!(name: 'Commerce', event_name: 'conversation_created', conditions: conditions,
                                     actions: [{ 'action_name' => 'add_label', 'action_params' => ['vip'] }])
  end

  def matching(*conditions)
    rule = rule_with(*conditions)
    conversations.select { |_, conversation| described_class.new(rule, conversation).perform }.keys
  end

  it 'reads links: linked store and platform' do
    expect(matching(condition('commerce_provider', 'equal_to', ['woocommerce']))).to contain_exactly(buyer, unread)
    expect(matching(condition('commerce_store', 'is_present', []))).to contain_exactly(buyer, unread)
    expect(matching(condition('commerce_store', 'is_not_present', []))).to contain_exactly(stranger)
    expect(matching(condition('commerce_store', 'equal_to', [store.id]))).to contain_exactly(buyer, unread)
  end

  it 'compares visible spend in its own currency and visible orders, never treating unknown as zero' do
    expect(matching(condition('commerce_spend_sar', 'is_greater_than', ['1000']))).to contain_exactly(buyer)
    expect(matching(condition('commerce_spend_usd', 'is_greater_than', ['0']))).to be_empty
    expect(matching(condition('commerce_orders_count', 'is_less_than', ['5']))).to contain_exactly(buyer)
    expect(matching(condition('commerce_orders_count', 'equal_to', ['0']))).to be_empty
  end

  it 'filters by last visible purchase, active order and order, payment and shipment states' do
    expect(matching(condition('commerce_last_purchase_at', 'is_greater_than', [(Time.zone.today - 30).iso8601]))).to contain_exactly(buyer)
    expect(matching(condition('commerce_active_order', 'equal_to', ['true']))).to contain_exactly(buyer)
    expect(matching(condition('commerce_active_order', 'equal_to', ['false']))).to be_empty
    expect(matching(condition('commerce_order_status', 'equal_to', ['processing']))).to contain_exactly(buyer)
    expect(matching(condition('commerce_order_status', 'not_equal_to', ['cancelled']))).to contain_exactly(buyer)
    expect(matching(condition('commerce_payment_status', 'equal_to', ['paid']))).to contain_exactly(buyer)
    expect(matching(condition('commerce_shipment_status', 'equal_to', ['in_transit']))).to contain_exactly(buyer)
  end

  it 'combines with existing and audience conditions through the rule\'s AND / OR chain, and calls no store' do
    admin = create(:user, account: account, role: :administrator)
    big = create(:custom_filter, account: account, user: admin, filter_type: :contact, shared: true, name: 'Big',
                                 query: { 'payload' => [condition('commerce_spend_sar', 'is_greater_than', ['1000'])] })

    expect(matching(condition('contact_audience', 'equal_to', [big.id], 'AND'), condition('commerce_provider', 'equal_to', ['woocommerce'], 'OR'),
                    condition('email', 'contains', ['stranger']))).to contain_exactly(buyer, stranger)
    expect(a_request(:any, /.*/)).not_to have_been_made
  end

  it 'rejects another account\'s store, bad values and Commerce keys without Lynomia Commerce when the rule is saved' do
    foreign = create(:commerce_store, account: create(:account))
    invalid = [condition('commerce_store', 'equal_to', [foreign.id]), condition('commerce_spend_sar', 'is_greater_than', ['-5']),
               condition('commerce_order_status', 'equal_to', ['teleported']), condition('commerce_orders_count', 'contains', ['1'])]
    invalid.each do |bad|
      expect(account.automation_rules.new(name: 'x', event_name: 'conversation_created', conditions: [bad], actions: [])).not_to be_valid
    end

    account.disable_features!('lynomia_commerce')
    rule = account.automation_rules.new(name: 'x', event_name: 'conversation_created', actions: [],
                                        conditions: [condition('commerce_store', 'is_present', [])])
    expect(rule).not_to be_valid
    expect(rule.errors[:conditions].join).to include('Lynomia Commerce')
  end

  it 'stops matching when the account loses Lynomia Commerce' do
    rule = rule_with(condition('commerce_store', 'is_present', []))
    account.disable_features!('lynomia_commerce')

    expect(described_class.new(rule, conversations[buyer]).perform).to be(false)
  end
end
