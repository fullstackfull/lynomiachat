require 'rails_helper'

RSpec.describe Lynomia::OperatorLog do
  describe '.line' do
    it 'writes one grep-able key=value line under a consistent prefix' do
      expect(described_class.line('QUEUE_HEALTH', { processes: 2, enqueued: 0 }))
        .to eq('[LYNOMIA][QUEUE_HEALTH] processes=2 enqueued=0')
    end

    it 'drops fields with no value rather than printing empty keys' do
      expect(described_class.line('X', { account: 1, code: nil })).to eq('[LYNOMIA][X] account=1')
    end

    it 'quotes a value containing spaces so the key=value shape survives' do
      expect(described_class.line('X', { error: '131049: not delivered' }))
        .to eq('[LYNOMIA][X] error="131049: not delivered"')
    end

    it 'collapses newlines so one event cannot become many log lines' do
      expect(described_class.line('X', { error: "first\n\nsecond" })).to eq('[LYNOMIA][X] error="first second"')
    end

    it 'truncates a long provider string so it cannot fill the log' do
      line = described_class.line('X', { error: 'a' * 500 })

      expect(line.length).to be < 250
      expect(line).to end_with('…"')
    end
  end

  describe 'levels' do
    it 'writes at the level the caller chose' do
      expect(Rails.logger).to receive(:warn).with('[LYNOMIA][X] a=1')
      described_class.warn('X', a: 1)
    end
  end
end
