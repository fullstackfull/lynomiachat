require 'rails_helper'

# STORE-SCOPED COMMERCE AGGREGATES (P5B).
#
# THE DEFECT THIS CLOSES. The Commerce aggregates -- orders count, spend, last purchase,
# active order, the status overlaps -- summed over EVERY counted link of a contact. A merchant
# with two connected stores who asked for "more than three orders" got contacts whose four
# orders were all at the other store. Nothing wrong was ever SENT, because the send boundary
# refuses a contact who is not this installation's customer; what was wrong was the number the
# merchant was shown and the people they believed they were addressing.
#
# THE SCOPE IS AN EVALUATION CONTEXT, NOT A CONDITION. It comes from who is asking -- a
# store-scoped campaign, or a request naming an installation -- rather than from another
# condition in the same payload. So one saved audience means "spent over 500 with us" for a
# store-scoped campaign and "over 500 anywhere" for the account's own contact filter, without
# being rewritten or duplicated per store.
#
# EVERY EXAMPLE PUTS THE CONTACT'S HISTORY AT THE OTHER STORE, because that is the shape that
# distinguishes a scoped aggregate from an unscoped one. An example where the contact only
# ever bought from one store passes either way and proves nothing.
RSpec.describe Audience::CommerceCondition do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:ours) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-1', status: :active) }
  let(:theirs) { create(:commerce_store, account: account, provider: 'shopify', external_store_id: 'sh-1', status: :active) }
  # An email, because the contact relation every filter is built on excludes contacts with no
  # email, phone number or identifier at all -- a nameless-only contact would be filtered out
  # before any Commerce condition ran, and every example here would pass vacuously.
  let(:shopper) { create(:contact, account: account, name: 'Shopper', email: 'shopper@example.test') }

  # Both providers switched on at the installation, because `counted_stores` selects only
  # stores whose provider is enabled -- a store of a disabled provider contributes nothing to
  # any aggregate, which would make every example below pass for the wrong reason.
  before do
    create(:installation_config, name: 'STORESYRIA_ENABLED', value: true)
    create(:installation_config, name: 'SHOPIFY_COMMERCE_ENABLED', value: true)
    account.enable_features!('lynomia_commerce')
  end

  def metric(store, attributes)
    link = create(:commerce_customer_link, account: account, store: store, contact: shopper,
                                           external_customer_id: "c-#{store.id}")
    Commerce::ContactMetric.create!({ account: account, customer_link: link, orders_count: 0,
                                      active_orders_count: 0, spend: {}, order_statuses: [],
                                      fetched_at: Time.current }.merge(attributes))
  end

  def matches(payload, store_id: nil)
    Contacts::FilterService.new(account, user, { payload: payload, commerce_store_id: store_id }).relation.to_a
  end

  def condition(key, operator, values)
    [{ 'attribute_key' => key, 'filter_operator' => operator, 'values' => values, 'query_operator' => nil }]
  end

  describe 'order counts' do
    before do
      metric(theirs, orders_count: 4)
      metric(ours, orders_count: 1)
    end

    it 'sums every store when nothing narrows it, which is what it has always done' do
      expect(matches(condition('commerce_orders_count', 'is_greater_than', ['3']))).to contain_exactly(shopper)
    end

    it 'counts only this store when the question is about this store' do
      expect(matches(condition('commerce_orders_count', 'is_greater_than', ['3']), store_id: ours.id)).to be_empty
    end

    it 'still matches on this store\'s own history' do
      expect(matches(condition('commerce_orders_count', 'is_greater_than', ['0']), store_id: ours.id)).to contain_exactly(shopper)
    end

    # The completeness rule has to narrow with the scope too. "Fewer than two orders" is only
    # answerable when every COUNTED link has a summary -- and once the scope is one store,
    # "every counted link" means that store's, not the other store's as well.
    it 'answers a could-be-false comparison against this store\'s links alone' do
      expect(matches(condition('commerce_orders_count', 'is_less_than', ['2']), store_id: ours.id)).to contain_exactly(shopper)
      expect(matches(condition('commerce_orders_count', 'is_less_than', ['2']))).to be_empty
    end
  end

  describe 'spend' do
    before do
      metric(theirs, spend: { 'SAR' => '900.00' })
      metric(ours, spend: { 'SAR' => '100.00' })
    end

    it 'sums every store unscoped' do
      expect(matches(condition('commerce_spend_sar', 'is_greater_than', ['500']))).to contain_exactly(shopper)
    end

    it 'sums this store alone when scoped' do
      expect(matches(condition('commerce_spend_sar', 'is_greater_than', ['500']), store_id: ours.id)).to be_empty
    end
  end

  describe 'order status' do
    before do
      metric(theirs, order_statuses: %w[refunded])
      metric(ours, order_statuses: %w[completed])
    end

    it 'finds a refund at either store unscoped' do
      expect(matches(condition('commerce_order_status', 'equal_to', ['refunded']))).to contain_exactly(shopper)
    end

    it 'does not attribute another store\'s refund to this one' do
      expect(matches(condition('commerce_order_status', 'equal_to', ['refunded']), store_id: ours.id)).to be_empty
    end

    # The negative form reads over the same narrowed population: "has never had a refund HERE"
    # must be true for somebody whose only refund was somewhere else.
    it 'reads never-refunded against this store only' do
      expect(matches(condition('commerce_order_status', 'not_equal_to', ['refunded']), store_id: ours.id)).to contain_exactly(shopper)
      expect(matches(condition('commerce_order_status', 'not_equal_to', ['refunded']))).to be_empty
    end
  end

  describe 'the presence conditions' do
    before { metric(theirs, orders_count: 2) }

    it 'sees a link at any store unscoped' do
      expect(matches(condition('commerce_store', 'is_present', []))).to contain_exactly(shopper)
    end

    it 'sees no link at a store the contact has never bought from' do
      expect(matches(condition('commerce_store', 'is_present', []), store_id: ours.id)).to be_empty
      expect(matches(condition('commerce_store', 'is_not_present', []), store_id: ours.id)).to contain_exactly(shopper)
    end
  end

  # TENANCY. The scope names an installation, so a scope naming somebody else's installation
  # is a tenancy error to refuse rather than a predicate to quietly match nothing on: an empty
  # audience reads as "nobody qualifies", which is the wrong answer to give somebody whose
  # real mistake was naming a store that is not theirs.
  describe 'a store that is not this account\'s' do
    it 'is refused rather than silently narrowing to nothing' do
      stranger = create(:commerce_store, account: create(:account), provider: 'storesyria', external_store_id: 'sy-x')
      metric(ours, orders_count: 1)

      expect { matches(condition('commerce_orders_count', 'is_greater_than', ['0']), store_id: stranger.id) }
        .to raise_error(CustomExceptions::CustomFilter::InvalidValue)
    end

    it 'refuses a disconnected store of this account too, because its links are not counted' do
      ours.update!(status: :disconnected)

      expect { matches(condition('commerce_orders_count', 'is_greater_than', ['0']), store_id: ours.id) }
        .to raise_error(CustomExceptions::CustomFilter::InvalidValue)
    end
  end
end
