require 'rails_helper'

RSpec.describe Commerce::StoreUrl do
  def reason_for(raw)
    described_class.parse(raw)
    nil
  rescue Commerce::Error => e
    e.reason
  end

  describe '.parse' do
    it 'normalizes a public https store URL' do
      uri = described_class.parse(' https://Shop.Example.com/store/ ')

      expect(uri.to_s).to eq('https://shop.example.com/store')
      expect(described_class.external_id(uri)).to eq('shop.example.com/store')
    end

    it 'assumes https when no scheme is given' do
      expect(described_class.parse('shop.example.com').to_s).to eq('https://shop.example.com')
    end

    {
      'http://shop.example.com' => 'https_required',
      'https://shop.example.com:8443' => 'port_not_allowed',
      'https://user:pass@shop.example.com' => 'invalid',
      'https://shop.example.com/?redirect=http://10.0.0.1' => 'invalid',
      'https://shop.example.com/#x' => 'invalid',
      'https://shop.example.com/a/../../admin' => 'invalid',
      'ftp://shop.example.com' => 'invalid',
      'file:///etc/passwd' => 'invalid',
      'javascript:alert(1)' => 'invalid',
      'https://' => 'invalid',
      'https://127.0.0.1' => 'ip_address_not_allowed',
      'https://10.0.0.5' => 'ip_address_not_allowed',
      'https://192.168.1.10' => 'ip_address_not_allowed',
      'https://169.254.169.254' => 'ip_address_not_allowed',
      'https://[::1]' => 'ip_address_not_allowed',
      'https://[fd00:ec2::254]' => 'ip_address_not_allowed',
      'https://8.8.8.8' => 'ip_address_not_allowed'
    }.each do |raw, reason|
      it "rejects #{raw} (#{reason})" do
        expect(reason_for(raw)).to eq(reason)
      end
    end

    context 'with an explicitly trusted internal host' do
      around { |example| with_modified_env(COMMERCE_TRUSTED_STORE_HOSTS: 'woo.internal, localhost') { example.run } }

      it 'allows http and a custom port for that host only' do
        uri = described_class.parse('http://woo.internal:8081/shop')

        expect(uri.to_s).to eq('http://woo.internal:8081/shop')
        expect(described_class.external_id(uri)).to eq('woo.internal:8081/shop')
        expect(reason_for('http://other.internal:8081')).to eq('https_required')
      end
    end
  end
end
