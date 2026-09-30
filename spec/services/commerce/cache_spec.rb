require 'rails_helper'

RSpec.describe Commerce::Cache do
  include_context 'with commerce encryption'

  let(:store) { create(:commerce_store) }
  let(:other_store) { create(:commerce_store) }
  let(:orders) { [{ 'external_order_id' => '22', 'total' => '284.75' }] }

  before { [store, other_store].each { |s| described_class.purge(s) } }

  it 'fetches and caches on a miss' do
    result = described_class.fetch(store, :orders, 'guest:omar@example.com') { orders }

    expect(result).to have_attributes(value: orders, stale: false, error: nil)
    expect(described_class.fetch(store, :orders, 'guest:omar@example.com') { raise 'not called on a hit' }.value).to eq(orders)
  end

  it 'refreshes an entry older than 120 seconds' do
    described_class.fetch(store, :orders, '2') { orders }

    travel(described_class::FRESH_FOR + 1.second) do
      expect(described_class.fetch(store, :orders, '2') { [] }).to have_attributes(value: [], stale: false)
    end
  end

  it 'serves the last good data as stale, with its age, when the store is unavailable' do
    first = described_class.fetch(store, :orders, '2') { orders }

    travel(18.minutes) do
      result = described_class.fetch(store, :orders, '2') { raise Commerce::Error, 'TIMEOUT' }

      expect(result).to have_attributes(value: orders, stale: true, error: 'TIMEOUT', fetched_at: first.fetched_at)
    end
  end

  it 'expires entries after 24 hours, so stale data is never older than that' do
    described_class.fetch(store, :orders, '2') { orders }
    keys = []
    Redis::Alfred.scan_each(match: "COMMERCE::V1::ACCOUNT::#{store.account_id}::STORE::#{store.id}::*") { |key| keys << key }

    expect(Redis::Alfred.ttl(keys.sole)).to be_within(10).of(described_class::KEEP_FOR.to_i)
  end

  it 'raises when the store is unavailable and nothing was cached' do
    expect { described_class.fetch(store, :orders, '2') { raise Commerce::Error, 'STORE_UNAVAILABLE' } }.to raise_error(Commerce::Error)
  end

  it 'does not hide revoked keys behind stale data' do
    described_class.fetch(store, :orders, '2') { orders }

    travel(5.minutes) do
      expect { described_class.fetch(store, :orders, '2') { raise Commerce::Error, 'AUTH_INVALID' } }.to raise_error(Commerce::Error)
    end
  end

  it 'isolates stores and accounts, and purges one store only' do
    described_class.fetch(store, :orders, '2') { orders }
    described_class.fetch(other_store, :orders, '2') { [] }

    expect(described_class.fetch(other_store, :orders, '2') { raise 'hit expected' }.value).to eq([])
    described_class.purge(store)
    expect(described_class.fetch(store, :orders, '2') { [] }.value).to eq([])
    expect(described_class.fetch(other_store, :orders, '2') { raise 'hit expected' }.value).to eq([])
  end

  it 'keeps identifiers and credentials out of Redis keys and values' do
    described_class.fetch(store, :orders, 'guest:omar@example.com') { orders }
    keys = []
    Redis::Alfred.scan_each(match: "COMMERCE::V1::ACCOUNT::#{store.account_id}::STORE::#{store.id}::*") { |key| keys << key }

    expect(keys.sole).to match(/\ACOMMERCE::V1::ACCOUNT::#{store.account_id}::STORE::#{store.id}::ORDERS::\h{64}\z/o)
    expect(Redis::Alfred.get(keys.sole)).not_to include('omar', 'ck_factory', 'cs_factory')
  end
end
