require 'rails_helper'

RSpec.describe Analytics::Commerce::Metrics do
  include_context 'with commerce encryption'

  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:zid_store) { create(:commerce_store, :zid, account: account, name: 'Zid Shop') }
  let(:salla_store) { create(:commerce_store, :salla, account: account, name: 'Salla Shop') }
  let(:contact) { create(:contact, account: account) }

  let(:date_range) do
    Analytics::DateRange.new(account: account, since: '2026-10-01', until_value: '2026-10-07', group_by: 'day')
  end

  def metrics(filters: {})
    described_class.new(
      account: account, date_range: date_range,
      filters: Analytics::FilterSet.new(account: account, family: :commerce, params: filters)
    )
  end

  def cart(state: :abandoned, seen: Time.utc(2026, 10, 2, 9, 0), abandoned: Time.utc(2026, 10, 2, 9, 0),
           **attributes)
    store = attributes[:store] || zid_store
    Commerce::Cart.create!(
      account: account, commerce_store: store, provider: store.provider,
      provider_cart_id: "cart-#{SecureRandom.hex(6)}", contact: contact, state: state,
      first_seen_at: seen, last_provider_event_at: seen, abandoned_at: abandoned,
      targeted_at: attributes[:targeted], completed_at: attributes[:completed],
      currency: attributes.fetch(:currency, 'SAR'), visible_total: attributes.fetch(:total, 250.0)
    )
  end

  def action_run(action_type: 'refund_partial', status: :succeeded, at: Time.utc(2026, 10, 2, 9, 0),
                 error_code: nil, store: nil)
    owner = store || zid_store
    Commerce::ActionRun.create!(
      account: account, store: owner, provider: owner.provider, action_type: action_type,
      external_resource_id: '15', idempotency_key: "commerce-action:#{SecureRandom.uuid}",
      request_digest: 'd' * 64, status: status, error_code: error_code, created_at: at
    )
  end

  describe 'cart lifecycle' do
    it 'counts carts the provider first mentioned in the account-timezone window' do
      cart
      # 22:00 UTC on 30 September is 1 October in Kuwait, so it belongs to this range.
      cart(seen: Time.utc(2026, 9, 30, 22, 0), abandoned: Time.utc(2026, 9, 30, 22, 0))
      # 20:00 UTC on 30 September is still 30 September locally, so it does not.
      cart(seen: Time.utc(2026, 9, 30, 20, 0), abandoned: Time.utc(2026, 9, 30, 20, 0))

      expect(metrics.carts_seen).to eq(2)
    end

    it 'counts abandonment, targeting and completion by their own timestamps' do
      cart(targeted: Time.utc(2026, 10, 2, 10, 0))
      cart(state: :completed, completed: Time.utc(2026, 10, 3, 10, 0))

      expect(metrics.carts_abandoned).to eq(2)
      expect(metrics.carts_targeted).to eq(1)
      expect(metrics.carts_completed).to eq(1)
    end

    it "never counts another account's carts" do
      foreign_store = create(:commerce_store, :zid, account: other_account)
      Commerce::Cart.create!(account: other_account, commerce_store: foreign_store, provider: 'zid',
                             provider_cart_id: 'foreign-1', state: :abandoned,
                             first_seen_at: Time.utc(2026, 10, 2, 9, 0),
                             last_provider_event_at: Time.utc(2026, 10, 2, 9, 0),
                             abandoned_at: Time.utc(2026, 10, 2, 9, 0))

      expect(metrics.carts_seen).to eq(0)
    end
  end

  describe 'completions after outreach' do
    it 'counts a completion that followed outreach, and one that had none, separately' do
      cart(state: :completed, targeted: Time.utc(2026, 10, 2, 10, 0), completed: Time.utc(2026, 10, 2, 11, 0))
      cart(state: :completed, completed: Time.utc(2026, 10, 2, 11, 0))

      expect(metrics.post_target_completions).to eq(1)
      expect(metrics.untargeted_completions).to eq(1)
    end

    it 'does not count a completion that preceded the outreach as following it' do
      cart(state: :completed, targeted: Time.utc(2026, 10, 2, 11, 0), completed: Time.utc(2026, 10, 2, 10, 0))

      expect(metrics.post_target_completions).to eq(0)
      expect(metrics.untargeted_completions).to eq(0)
    end

    it 'agrees with the model about what a post-target completion is' do
      row = cart(state: :completed, targeted: Time.utc(2026, 10, 2, 10, 0), completed: Time.utc(2026, 10, 2, 11, 0))

      expect(row.post_target_completion?).to be(true)
      expect(metrics.post_target_completions).to eq(1)
    end
  end

  describe 'targeting_rate' do
    it 'is the share of the period\'s abandonments that were messaged' do
      cart(targeted: Time.utc(2026, 10, 2, 10, 0))
      cart
      cart
      cart

      expect(metrics.targeting_rate).to eq(25.0)
    end

    it 'returns nil rather than zero when nothing was abandoned' do
      expect(metrics.targeting_rate).to be_nil
    end
  end

  describe 'order actions' do
    it 'counts requested, failed and prepared recovery messages' do
      action_run
      action_run(status: :failed, error_code: 'PROVIDER_REFUSED')
      action_run(action_type: Commerce::ActionRun::RECOVERY_MESSAGE, status: :pending)

      expect(metrics.order_actions_requested).to eq(2)
      expect(metrics.order_actions_failed).to eq(1)
      expect(metrics.recovery_messages_prepared).to eq(1)
    end
  end

  describe 'current state' do
    it 'counts carts the provider called abandoned and never called completed, whatever the range' do
      cart(seen: Time.utc(2020, 1, 1), abandoned: Time.utc(2020, 1, 1))
      cart(state: :completed, completed: Time.utc(2026, 10, 2, 11, 0))

      expect(metrics.open_abandoned_now).to eq(1)
    end

    it 'counts actions that have not settled, including the ones whose answer was lost' do
      action_run(status: :pending, at: Time.utc(2020, 1, 1))
      action_run(status: :running, at: Time.utc(2020, 1, 1))
      action_run(status: :unknown, at: Time.utc(2020, 1, 1))
      action_run(status: :succeeded)

      expect(metrics.actions_unresolved_now).to eq(3)
    end
  end

  describe 'filters' do
    it 'narrows to one provider' do
      cart(store: zid_store)
      cart(store: salla_store)

      expect(metrics(filters: { 'provider' => 'zid' }).carts_seen).to eq(1)
    end

    it 'refuses a provider this product does not support' do
      expect { metrics(filters: { 'provider' => 'etsy' }) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::UnknownFilterValue') })
    end
  end

  describe 'series' do
    it 'emits one point per bucket including the zeros' do
      cart(seen: Time.utc(2026, 10, 1, 9, 0), abandoned: Time.utc(2026, 10, 1, 9, 0))
      points = metrics.series(:carts_abandoned)

      expect(points.length).to eq(7)
      expect(points.first).to eq(bucket: '2026-10-01', value: 1)
    end

    it 'buckets by the account timezone, not naive UTC' do
      cart(seen: Time.utc(2026, 10, 1, 22, 0), abandoned: Time.utc(2026, 10, 1, 22, 0))
      points = metrics.series(:carts_abandoned)

      expect(points.find { |point| point[:bucket] == '2026-10-02' }[:value]).to eq(1)
    end
  end

  describe 'breakdowns' do
    it 'groups by provider' do
      cart(store: zid_store)
      cart(store: zid_store)
      cart(store: salla_store)

      expect(metrics.breakdown(:provider).first).to eq(id: 'zid', label: 'zid', value: 2)
    end

    it 'groups by store with the store name' do
      cart(store: salla_store)

      expect(metrics.breakdown(:store)).to eq([{ id: salla_store.id, label: 'Salla Shop', value: 1 }])
    end

    it 'reports cart counts per currency, never a money total' do
      cart(currency: 'SAR', total: 100.0)
      cart(currency: 'SAR', total: 900.0)
      cart(currency: 'KWD', total: 50.0)

      rows = metrics.breakdown(:currency)

      expect(rows.first).to eq(id: 'SAR', label: 'SAR', value: 2)
      expect(rows.map { |row| row[:value] }).to contain_exactly(2, 1)
    end

    it 'groups action runs by type and failures by their code' do
      action_run(action_type: 'cancel_order')
      action_run(action_type: 'refund_partial', status: :failed, error_code: 'PROVIDER_REFUSED')

      expect(metrics.breakdown(:action_type).map { |row| row[:label] })
        .to contain_exactly('cancel_order', 'refund_partial')
      expect(metrics.breakdown(:action_error)).to eq([{ id: 'PROVIDER_REFUSED', label: 'PROVIDER_REFUSED', value: 1 }])
    end
  end
end
