require 'rails_helper'

# Recovery links an agent may send (docs/commerce/31-sales-recovery.md §URL safety).
RSpec.describe Commerce::RecoveryUrl do
  let(:hosts) { ['shop.example.com', '.zid.store'] }

  it 'accepts https links on the store\'s own host or its provider\'s subdomains' do
    expect(described_class.safe('https://shop.example.com/cart/recover?token=abc', hosts: hosts)).to eq('https://shop.example.com/cart/recover?token=abc')
    expect(described_class.safe(' https://my-store.zid.store/c/9f1 ', hosts: hosts)).to eq('https://my-store.zid.store/c/9f1')
  end

  it 'refuses every other scheme, host, credential, port or shape' do
    [
      'javascript:alert(1)', 'data:text/html,<script>', 'file:///etc/passwd', 'http://shop.example.com/cart', 'ftp://shop.example.com/x',
      'https://evil.example/cart', 'https://shop.example.com.evil.example/cart', 'https://bit.ly/3abc', 'https://zid.store.evil.example/x',
      'https://user:pass@shop.example.com/cart', 'https://shop.example.com:8443/cart', "https://shop.example.com/a\nb", '//shop.example.com/cart',
      "https://shop.example.com/#{'a' * 2100}", '', nil
    ].each { |url| expect(described_class.safe(url, hosts: hosts)).to be_nil, url.to_s.first(60) }
  end
end
