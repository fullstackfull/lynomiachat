require 'rails_helper'

# Lynomia Audience conditions in the contact filter (docs/audience/02, 03): Commerce conditions over customer links and
# their summaries, conversation conditions over the conversations the user may see.
RSpec.describe Contacts::FilterService do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:woo) { create(:commerce_store, account: account) }
  let(:woo2) { create(:commerce_store, account: account) }
  let(:buyer) { create(:contact, account: account, email: 'buyer@example.com') }
  let(:small) { create(:contact, account: account, email: 'small@example.com') }
  let(:unread) { create(:contact, account: account, email: 'unread@example.com') }
  let(:nobody) { create(:contact, account: account, email: 'nobody@example.com') }
  let(:summary) do
    lambda do |contact, store, **figures|
      link = create(:commerce_customer_link, store: store, contact: contact)
      Commerce::ContactMetric.create!({ account: account, customer_link: link, fetched_at: Time.current, orders_count: 0,
                                        active_orders_count: 0 }.merge(figures))
      link
    end
  end
  let(:run) { ->(*conditions) { described_class.new(account, admin, { payload: conditions }).perform[:contacts].to_a } }
  let(:condition) do
    lambda do |key, operator, values, query_operator = nil|
      { 'attribute_key' => key, 'filter_operator' => operator, 'values' => values, 'query_operator' => query_operator }.with_indifferent_access
    end
  end

  before do
    account.enable_features!('lynomia_commerce')
    summary.call(buyer, woo, orders_count: 4, active_orders_count: 1, last_purchase_at: 3.days.ago, spend: { 'SAR' => '1500.00', 'USD' => '20.00' },
                             order_statuses: %w[completed processing], payment_statuses: %w[paid], shipment_statuses: %w[in_transit])
    summary.call(small, woo, orders_count: 1, last_purchase_at: 90.days.ago, spend: { 'SAR' => '200.00' }, order_statuses: %w[completed],
                             payment_statuses: %w[paid])
    create(:commerce_customer_link, store: woo, contact: unread)
    nobody
  end

  describe 'store and provider conditions' do
    it 'matches contacts linked in a counted store, whatever their order data' do
      expect(run.call(condition.call('commerce_store', 'is_present', []))).to contain_exactly(buyer, small, unread)
      expect(run.call(condition.call('commerce_store', 'is_not_present', []))).to contain_exactly(nobody)
      expect(run.call(condition.call('commerce_store', 'equal_to', [woo.id]))).to contain_exactly(buyer, small, unread)
      expect(run.call(condition.call('commerce_provider', 'equal_to', %w[woocommerce salla]))).to contain_exactly(buyer, small, unread)
    end

    it 'never counts a suppressed link, a disabled store or a provider the installation switched off' do
      Commerce::CustomerLink.find_by!(contact: buyer).update!(match_source: :suppressed)
      woo2.update!(status: :disabled)
      summary.call(nobody, woo2, orders_count: 9)
      salla = create(:commerce_store, :salla, account: account)
      summary.call(nobody, salla, orders_count: 9)

      expect(run.call(condition.call('commerce_store', 'is_present', []))).to contain_exactly(small, unread)
      expect(run.call(condition.call('commerce_orders_count', 'is_greater_than', ['3']))).to be_empty
    end

    it 'ignores a store id of another account' do
      other = create(:commerce_store)

      expect(run.call(condition.call('commerce_store', 'equal_to', [other.id]))).to be_empty
    end
  end

  describe 'order conditions' do
    it 'compares visible orders and spend per currency, never across currencies' do
      expect(run.call(condition.call('commerce_orders_count', 'is_greater_than', ['2']))).to contain_exactly(buyer)
      expect(run.call(condition.call('commerce_spend_sar', 'is_greater_than', ['1000']))).to contain_exactly(buyer)
      expect(run.call(condition.call('commerce_spend_usd', 'is_greater_than', ['1000']))).to be_empty
      expect(run.call(condition.call('commerce_spend_sar', 'is_less_than', ['1000']))).to contain_exactly(small)
    end

    it 'does not treat a contact whose orders were never read as zero' do
      expect(run.call(condition.call('commerce_orders_count', 'is_less_than', ['3']))).to contain_exactly(small)
      expect(run.call(condition.call('commerce_orders_count', 'equal_to', ['0']))).to be_empty
      expect(run.call(condition.call('commerce_active_order', 'equal_to', ['false']))).to contain_exactly(small)
      expect(run.call(condition.call('commerce_order_status', 'not_equal_to', ['processing']))).to contain_exactly(small)
    end

    it 'decides "more than" from the known stores, "less than" only when every store is known' do
      create(:commerce_customer_link, store: woo2, contact: small)

      expect(run.call(condition.call('commerce_orders_count', 'is_greater_than', ['0']))).to contain_exactly(buyer, small)
      expect(run.call(condition.call('commerce_spend_sar', 'is_less_than', ['1000']))).to be_empty
    end

    it 'sums spend of the same currency across stores' do
      summary.call(small, woo2, orders_count: 1, spend: { 'SAR' => '900.00' })

      expect(run.call(condition.call('commerce_spend_sar', 'is_greater_than', ['1000']))).to contain_exactly(buyer, small)
    end

    it 'filters by last visible purchase, active orders and order, payment and shipping states' do
      after = (Time.zone.today - 30).iso8601
      expect(run.call(condition.call('commerce_last_purchase_at', 'is_greater_than', [after]))).to contain_exactly(buyer)
      expect(run.call(condition.call('commerce_last_purchase_at', 'days_before', ['30']))).to contain_exactly(small)
      expect(run.call(condition.call('commerce_active_order', 'equal_to', ['true']))).to contain_exactly(buyer)
      expect(run.call(condition.call('commerce_order_status', 'equal_to', %w[processing shipped]))).to contain_exactly(buyer)
      expect(run.call(condition.call('commerce_payment_status', 'equal_to', ['paid']))).to contain_exactly(buyer, small)
      expect(run.call(condition.call('commerce_shipment_status', 'equal_to', ['in_transit']))).to contain_exactly(buyer)
    end

    it 'joins Commerce, contact and label conditions with the existing AND / OR chain' do
      buyer.update!(label_list: ['vip'])

      expect(run.call(condition.call('commerce_spend_sar', 'is_greater_than', ['100'], 'AND'),
                      condition.call('labels', 'equal_to', ['vip']))).to contain_exactly(buyer)
      expect(run.call(condition.call('commerce_orders_count', 'is_greater_than', ['3'], 'OR'),
                      condition.call('email', 'equal_to', ['nobody@example.com']))).to contain_exactly(buyer, nobody)
    end

    it 'never calls a store' do
      run.call(condition.call('commerce_orders_count', 'is_greater_than', ['0'], 'AND'),
               condition.call('commerce_spend_sar', 'is_less_than', ['5'], 'OR'),
               condition.call('commerce_order_status', 'not_equal_to', ['completed']))

      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end

  describe 'conversation conditions' do
    let(:inbox) { create(:inbox, account: account) }
    let(:other_inbox) { create(:inbox, account: account) }
    let(:agent) { create(:user, account: account, role: :agent) }

    before do
      create(:inbox_member, user: agent, inbox: inbox)
      create(:conversation, account: account, inbox: inbox, contact: buyer, status: :open, priority: :high, assignee: agent)
      create(:conversation, account: account, inbox: other_inbox, contact: small, status: :open).update!(label_list: ['refund'])
    end

    it 'matches contacts that have, or have no, such a conversation' do
      expect(run.call(condition.call('conversation_status', 'equal_to', ['open']))).to contain_exactly(buyer, small)
      expect(run.call(condition.call('conversation_status', 'not_equal_to', ['open']))).to contain_exactly(unread, nobody)
      expect(run.call(condition.call('conversation_priority', 'equal_to', ['high']))).to contain_exactly(buyer)
      expect(run.call(condition.call('conversation_assignee', 'equal_to', [agent.id]))).to contain_exactly(buyer)
      expect(run.call(condition.call('conversation_inbox', 'equal_to', [other_inbox.id]))).to contain_exactly(small)
      expect(run.call(condition.call('conversation_labels', 'equal_to', ['refund']))).to contain_exactly(small)
    end

    # The exact payload the "Has contacted us" / "Has never contacted us" audience presets build
    # (docs/contacts/08-recipes-and-presets.md). Every status at once is how "a conversation at all" is asked,
    # because this condition offers equality only.
    it 'answers whether a contact has any conversation at all, over every status at once' do
      statuses = %w[open pending resolved snoozed]
      create(:conversation, account: account, inbox: inbox, contact: unread, status: :resolved)

      expect(run.call(condition.call('conversation_status', 'equal_to', statuses))).to contain_exactly(buyer, small, unread)
      expect(run.call(condition.call('conversation_status', 'not_equal_to', statuses))).to contain_exactly(nobody)
    end

    it 'only sees the conversations the user may see' do
      found = described_class.new(account, agent, { payload: [condition.call('conversation_status', 'equal_to', ['open'])] }).perform[:contacts]

      expect(found).to contain_exactly(buyer)
    end
  end

  describe 'invalid conditions' do
    let(:invalid_value) { CustomExceptions::CustomFilter::InvalidValue }

    it 'rejects an operator or a key the field does not take' do
      expect { run.call(condition.call('commerce_spend_sar', 'contains', ['1'])) }.to raise_error(CustomExceptions::CustomFilter::InvalidOperator)
      expect { run.call(condition.call('commerce_orders', 'equal_to', ['1'])) }.to raise_error(CustomExceptions::CustomFilter::InvalidAttribute)
    end

    it 'rejects values outside what the field documents' do
      expect { run.call(condition.call('commerce_spend_sar', 'is_greater_than', ['NaN'])) }.to raise_error(invalid_value)
      expect { run.call(condition.call('commerce_spend_sar', 'is_greater_than', ['-1'])) }.to raise_error(invalid_value)
      expect { run.call(condition.call('commerce_provider', 'equal_to', ["woocommerce' OR 1=1 --"])) }.to raise_error(invalid_value)
      expect { run.call(condition.call('conversation_status', 'equal_to', ['closed'])) }.to raise_error(invalid_value)
      expect { run.call(condition.call('commerce_last_purchase_at', 'days_before', ['0'])) }.to raise_error(invalid_value)
    end

    it 'bounds the number of conditions and of values' do
      too_many = Array.new(11) { condition.call('commerce_store', 'is_present', [], 'AND') }
      too_many.last['query_operator'] = nil

      expect { run.call(condition.call('commerce_store', 'equal_to', (1..51).to_a)) }.to raise_error(invalid_value)
      expect { run.call(*too_many) }.to raise_error(invalid_value)
    end

    it 'keeps label names out of the SQL text' do
      expect(run.call(condition.call('conversation_labels', 'equal_to', ["x') OR 1=1 --", ':audience_0']))).to be_empty
    end

    it 'offers no Commerce condition to an account without Lynomia Commerce' do
      account.disable_features!('lynomia_commerce')

      expect { run.call(condition.call('commerce_store', 'is_present', [])) }.to raise_error(CustomExceptions::CustomFilter::InvalidAttribute)
    end

    it 'leaves a contact custom attribute with the same key to its old meaning' do
      create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'commerce_store',
                                           attribute_display_type: 'text')
      nobody.update!(custom_attributes: { 'commerce_store' => 'main' })

      expect(run.call(condition.call('commerce_store', 'equal_to', ['main']))).to contain_exactly(nobody)
    end
  end
end
