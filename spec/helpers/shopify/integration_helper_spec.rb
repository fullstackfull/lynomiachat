require 'rails_helper'

RSpec.describe Shopify::IntegrationHelper do
  include described_class

  describe '#generate_shopify_token' do
    let(:account_id) { 1 }
    let(:client_secret) { 'test_secret' }
    let(:current_time) { Time.current }

    before do
      allow(GlobalConfigService).to receive(:load).with('SHOPIFY_CLIENT_SECRET', nil).and_return(client_secret)
      allow(Time).to receive(:current).and_return(current_time)
    end

    it 'generates a signed, time-bounded token bound to the account and the shop' do
      token = generate_shopify_token(account_id, ' My-Store.myshopify.com ')
      decoded_token = JWT.decode(token, client_secret, true, algorithm: 'HS256').first

      expect(decoded_token['sub']).to eq(account_id)
      expect(decoded_token['shop']).to eq('my-store.myshopify.com')
      expect(decoded_token['iat']).to eq(current_time.to_i)
      expect(decoded_token['exp']).to eq(current_time.to_i + described_class::STATE_TTL.to_i)
    end

    context 'when client secret is not configured' do
      let(:client_secret) { nil }

      it 'returns nil' do
        expect(generate_shopify_token(account_id, 'my-store.myshopify.com')).to be_nil
      end
    end

    context 'when an error occurs' do
      before do
        allow(JWT).to receive(:encode).and_raise(StandardError.new('Test error'))
      end

      it 'logs the error and returns nil' do
        expect(Rails.logger).to receive(:error).with('Failed to generate Shopify token: Test error')
        expect(generate_shopify_token(account_id, 'my-store.myshopify.com')).to be_nil
      end
    end
  end

  describe '#verify_shopify_token' do
    let(:account_id) { 1 }
    let(:client_secret) { 'test_secret' }
    let(:shop) { 'my-store.myshopify.com' }
    let(:valid_token) do
      JWT.encode({ sub: account_id, shop: shop, iat: Time.current.to_i, exp: 5.minutes.from_now.to_i }, client_secret, 'HS256')
    end

    before do
      allow(GlobalConfigService).to receive(:load).with('SHOPIFY_CLIENT_SECRET', nil).and_return(client_secret)
    end

    it 'successfully verifies and returns account_id from valid token' do
      expect(verify_shopify_token(valid_token, shop)).to eq(account_id)
    end

    it 'rejects a token issued for another shop' do
      expect(verify_shopify_token(valid_token, 'other-store.myshopify.com')).to be_nil
    end

    it 'rejects an expired token' do
      token = valid_token
      travel(6.minutes) { expect(verify_shopify_token(token, shop)).to be_nil }
    end

    it 'rejects a token without expiry or shop claims' do
      legacy_token = JWT.encode({ sub: account_id, iat: Time.current.to_i }, client_secret, 'HS256')

      expect(verify_shopify_token(legacy_token, shop)).to be_nil
    end

    context 'when token is blank' do
      it 'returns nil' do
        expect(verify_shopify_token('', shop)).to be_nil
        expect(verify_shopify_token(nil, shop)).to be_nil
      end
    end

    context 'when client secret is not configured' do
      let(:client_secret) { nil }
      let(:valid_token) { 'any-token' }

      it 'returns nil' do
        expect(verify_shopify_token(valid_token, shop)).to be_nil
      end
    end

    context 'when token is invalid' do
      it 'logs the error and returns nil' do
        expect(Rails.logger).to receive(:error).with(/Unexpected error verifying Shopify token:/)
        expect(verify_shopify_token('invalid_token', shop)).to be_nil
      end
    end
  end

  describe '#client_id' do
    it 'loads client_id from GlobalConfigService' do
      expect(GlobalConfigService).to receive(:load).with('SHOPIFY_CLIENT_ID', nil)
      client_id
    end
  end

  describe '#client_secret' do
    it 'loads client_secret from GlobalConfigService' do
      expect(GlobalConfigService).to receive(:load).with('SHOPIFY_CLIENT_SECRET', nil)
      client_secret
    end
  end
end
