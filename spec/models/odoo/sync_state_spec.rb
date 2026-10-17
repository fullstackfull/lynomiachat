require 'rails_helper'

# The one invariant that would break silently (custom/app/models/odoo/sync_state.rb).
RSpec.describe Odoo::SyncState do
  # `db/migrate/20261016120300_create_odoo_sync_events.rb` indexes `state IN (4, 5, 6)` for the Errors screen.
  # Reordering the enum would leave that index selecting healthy rows and hiding broken ones, with every spec
  # still green -- so the Ruby side and the SQL side are compared directly.
  it 'keeps the unhealthy states on the integers the partial index selects' do
    expect(described_class::UNHEALTHY.map { |state| described_class::STATES.fetch(state) }).to eq([4, 5, 6])
  end

  it 'keeps the unhealthy states contiguous and last, which is what makes an IN list safe to write by hand' do
    values = described_class::STATES.values

    expect(values).to eq((0..6).to_a)
    expect(values.last(3)).to eq(described_class::UNHEALTHY.map { |state| described_class::STATES.fetch(state) })
  end

  # Every table that tracks progress uses this vocabulary, so a model that quietly defined its own would make
  # the Errors screen incomplete.
  it 'is the vocabulary of all three tracking tables' do
    [Odoo::CustomerMapping, Odoo::DocumentMapping, Odoo::SyncEvent].each do |model|
      expect(model.states.symbolize_keys).to eq(described_class::STATES)
    end
  end

  it 'does not count retrying as unhealthy, because a row with a next attempt time fixes itself' do
    expect(described_class::UNHEALTHY).not_to include(:retrying)
  end
end
