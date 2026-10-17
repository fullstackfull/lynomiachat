require 'rails_helper'

# The error vocabulary every caller acts on (custom/app/services/odoo/error.rb).
RSpec.describe Odoo::Error do
  # `not_sent` may be repeated; `unknown_outcome` may NOT, because Odoo may have acted. Getting these two the
  # same way round is the difference between a safe retry and a double invoice.
  it 'keeps not_sent and unknown_outcome apart' do
    expect(described_class.new('UNREACHABLE').classification).to eq(:not_sent)
    expect(described_class.new('UNREACHABLE')).to be_retryable
    expect(described_class.new('TIMEOUT').classification).to eq(:unknown_outcome)
    expect(described_class.new('TIMEOUT')).not_to be_retryable
  end

  it 'classifies every code it accepts, so a new code cannot slip through unclassified' do
    described_class::CODES.each do |code|
      expect(described_class::CLASSIFICATIONS).to have_key(code), "#{code} has no classification"
    end
  end

  it 'refuses a code nobody declared' do
    expect { described_class.new('MADE_UP') }.to raise_error(ArgumentError)
  end
end
