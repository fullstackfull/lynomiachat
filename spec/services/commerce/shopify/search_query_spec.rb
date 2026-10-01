require 'rails_helper'

RSpec.describe Commerce::Shopify::SearchQuery do
  it 'quotes emails and phones as exact phrases' do
    expect(described_class.email('sara.ali@example.com')).to eq('email:"sara.ali@example.com"')
    expect(described_class.phone('+966551112233')).to eq('phone:"+966551112233"')
  end

  it 'escapes quotes and backslashes so a value never leaves its phrase' do
    expect(described_class.email('a"b@example.com')).to eq('email:"a\"b@example.com"')
    expect(described_class.email('a\\b@example.com')).to eq('email:"a\\\\b@example.com"')
    expect(described_class.email('x" OR email:* OR "')).to eq('email:"x\" OR email:* OR \""')
    expect(described_class.email('x\\" OR tag:vip')).to eq('email:"x\\\\\" OR tag:vip"')
    expect(described_class.phone('+1") OR (phone:*')).to eq('phone:"+1\") OR (phone:*"')
  end

  it 'keeps every escaped value a single phrase: no unescaped quote inside it' do
    ['"', '\\', '\\"', '"\\', 'a"b\\c"d', '""""', '\\\\""\\'].each do |value|
      inner = described_class.email(value).delete_prefix('email:"').delete_suffix('"')

      expect(inner.gsub(/\\./, '')).not_to include('"', '\\')
    end
  end

  it 'quotes an order name as an exact phrase that no value can leave' do
    expect(described_class.order_name('1006')).to eq('name:"1006"')
    expect(described_class.order_name('1" OR name:*')).to eq('name:"1\\" OR name:*"')
  end

  it 'accepts only a positive integer customer id' do
    expect(described_class.customer_id('7001')).to eq('customer_id:7001')
    ['7001 OR tag:vip', '-1', '0', 'gid://shopify/Customer/7001', '', nil, '1e3'].each do |value|
      expect { described_class.customer_id(value) }.to raise_error(ArgumentError)
    end
  end
end
