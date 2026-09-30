require 'rails_helper'

RSpec.describe Commerce::StoreConnection do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:connection) { described_class.new(account: account, user: admin) }
  let(:api) { 'https://shop.example.com/wp-json/wc/v3' }
  let(:credentials) { { 'consumer_key' => "ck_#{'a' * 40}", 'consumer_secret' => "cs_#{'b' * 40}" } }
  let(:connect) { connection.connect(provider: 'woocommerce', base_url: 'Shop.Example.com/', credentials: credentials, name: '') }

  before do
    allow(Resolv).to receive(:getaddresses).with('shop.example.com').and_return(['93.184.216.34'])
    stub_request(:get, "#{api}?_fields=namespace").to_return(status: 200, body: '{"namespace":"wc/v3"}')
    stub_request(:get, "#{api}/orders").with(query: hash_including('per_page' => '1')).to_return(status: 200, body: '[]')
    stub_request(:get, "#{api}/customers").with(query: hash_including('per_page' => '1')).to_return(status: 200, body: '[]')
  end

  describe '#connect' do
    it 'saves an active store only after the health check, with credentials encrypted at rest' do
      store = connect

      expect(store).to have_attributes(status: 'active', base_url: 'https://shop.example.com', external_store_id: 'shop.example.com',
                                       name: 'shop.example.com', created_by: admin, account: account)
      raw = Commerce::Store.connection.select_value("SELECT credentials FROM commerce_stores WHERE id = #{store.id}")
      expect(raw).not_to include('ck_', 'cs_', 'aaaa')
      expect(store.reload.credentials).to eq(credentials)
      expect(store.as_json).not_to have_key('credentials')
      expect(store.inspect).not_to include('ck_')
    end

    it 'records the connection in the audit log without credentials', if: defined?(Enterprise::AuditLog) do
      store = connect
      audit = Enterprise::AuditLog.where(auditable: store).last

      expect(audit).to have_attributes(comment: 'commerce.store_connected', user: admin, action: 'create')
      expect(audit.audited_changes.to_json).not_to include('ck_', 'cs_')
    end

    it 'saves nothing when the store rejects the keys' do
      stub_request(:get, "#{api}?_fields=namespace").to_return(status: 401)

      expect { connect }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('AUTH_INVALID') }
      expect(Commerce::Store.count).to eq(0)
    end

    it 'refuses to store credentials when encryption is not configured, before calling the store' do
      with_modified_env(ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY: nil) do
        expect { connect }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('ENCRYPTION_NOT_CONFIGURED') }
      end
      expect(a_request(:any, /.*/)).not_to have_been_made
      expect(Commerce::Store.count).to eq(0)
    end

    it 'refuses unsafe store URLs before calling them' do
      expect do
        connection.connect(provider: 'woocommerce', base_url: 'http://169.254.169.254', credentials: credentials)
      end.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('INVALID_STORE_URL') }
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'refuses a store another account has connected' do
      create(:commerce_store, base_url: 'https://shop.example.com', external_store_id: 'shop.example.com')

      expect { connect }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('STORE_ALREADY_CONNECTED') }
    end

    it 'refuses to connect the same store twice in one account' do
      connect

      expect { connection.connect(provider: 'woocommerce', base_url: 'https://shop.example.com', credentials: credentials) }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('STORE_ALREADY_CONNECTED') }
    end

    it 'takes over a store another account disconnected' do
      old = create(:commerce_store, base_url: 'https://shop.example.com', external_store_id: 'shop.example.com', status: :disconnected,
                                    credentials: nil)

      expect(connect.account).to eq(account)
      expect(Commerce::Store.exists?(old.id)).to be(false)
    end

    it 'reconnects a store this account disconnected, keeping its row and name' do
      old = create(:commerce_store, account: account, name: 'Syria Cosmetics', base_url: 'https://shop.example.com',
                                    external_store_id: 'shop.example.com', status: :disconnected, credentials: nil)

      expect(connect).to have_attributes(id: old.id, name: 'Syria Cosmetics', status: 'active')
    end
  end

  describe 'lifecycle' do
    let!(:store) { connect }
    let!(:link) { create(:commerce_customer_link, store: store, account: account) }

    it 'rotates credentials only after the new keys pass the health check' do
      new_credentials = { 'consumer_key' => "ck_#{'c' * 40}", 'consumer_secret' => "cs_#{'d' * 40}" }
      stub_request(:get, "#{api}?_fields=namespace").with(basic_auth: new_credentials.values).to_return(status: 401)

      expect { connection.rotate_credentials(store, new_credentials) }.to raise_error(Commerce::Error)
      expect(store.reload.credentials).to eq(credentials)
    end

    it 'disables and re-enables a store after a fresh health check' do
      connection.disable(store)
      expect(store.reload).to be_disabled

      connection.enable(store)
      expect(store.reload).to be_active
    end

    it 'disconnects: credentials and customer links are deleted' do
      connection.disconnect(store)

      expect(store.reload).to have_attributes(status: 'disconnected', credentials: nil)
      expect(Commerce::CustomerLink.exists?(link.id)).to be(false)
    end

    it 'cannot re-enable a disconnected store without new keys' do
      connection.disconnect(store)

      expect { connection.enable(store) }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('AUTH_INVALID') }
    end
  end
end
