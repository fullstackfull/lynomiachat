require 'rails_helper'

# Stripe's minor units into Odoo's major units (custom/app/services/odoo/money.rb).
#
# THIS IS NOT A STYLE TEST. Dividing by 100 is wrong for twenty-one currencies, and one of them is the one this
# installation's own operator bills in.
RSpec.describe Odoo::Money do
  describe 'two-decimal currencies' do
    it 'converts the common case' do
      expect(described_class.to_major(14_900, 'usd')).to eq(BigDecimal(149))
      expect(described_class.to_major(1, 'eur')).to eq(BigDecimal('0.01'))
    end
  end

  describe 'three-decimal currencies' do
    # KWD, and the reason this file exists: `1000 / 100.0` would read 10.000 KWD for an amount that is 1.000.
    it 'converts Kuwaiti dinar as thousandths' do
      expect(described_class.to_major(1000, 'kwd')).to eq(BigDecimal(1))
      expect(described_class.to_major(14_900, 'KWD')).to eq(BigDecimal('14.9'))
    end

    it 'covers every three-decimal currency Stripe publishes' do
      %w[bhd jod kwd omr tnd].each do |code|
        expect(described_class.exponent(code)).to eq(3), "#{code} should be a three-decimal currency"
      end
    end
  end

  describe 'zero-decimal currencies' do
    it 'converts Japanese yen as whole units' do
      expect(described_class.to_major(1000, 'jpy')).to eq(BigDecimal(1000))
    end

    it 'covers every zero-decimal currency Stripe publishes' do
      %w[bif clp djf gnf jpy kmf krw mga pyg rwf ugx vnd vuv xaf xof xpf].each do |code|
        expect(described_class.exponent(code)).to eq(0), "#{code} should be a zero-decimal currency"
      end
    end
  end

  it 'treats an unknown currency as two decimals, which is the safe majority case' do
    expect(described_class.exponent('zzz')).to eq(2)
  end

  # BigDecimal and not Float: an accounting amount that has been through binary floating point is an amount
  # that can disagree with itself.
  it 'returns a BigDecimal so a total comparison cannot drift' do
    expect(described_class.to_major(2990, 'usd')).to be_a(BigDecimal)
    expect(described_class.to_major(10, 'usd') * 3).to eq(BigDecimal('0.3'))
  end

  it 'scales the comparison tolerance to the currency, one minor unit either way' do
    expect(described_class.tolerance('usd')).to eq(BigDecimal('0.01'))
    expect(described_class.tolerance('kwd')).to eq(BigDecimal('0.001'))
    expect(described_class.tolerance('jpy')).to eq(BigDecimal(1))
  end
end
