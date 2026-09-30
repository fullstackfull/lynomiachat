require 'rails_helper'

# Payload shapes are Salla's documented app events (spec/fixtures/files/commerce/salla, docs/commerce/10-salla-install-correlation.md).
RSpec.describe Commerce::Salla::Installation do
  include_context 'with commerce encryption'
  include_context 'with salla app'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:authorize) { JSON.parse(file_fixture('commerce/salla/app_store_authorize.json').read) }
  let(:uninstalled) { JSON.parse(file_fixture('commerce/salla/app_uninstalled.json').read) }
  let(:user_info) { file_fixture('commerce/salla/user_info.json').read }
  let!(:user_info_stub) do
    stub_request(:get, 'https://accounts.salla.sa/oauth2/user/info').with(headers: { 'Authorization' => 'Bearer salla-access-token-fixture' })
                                                                    .to_return(status: 200, body: user_info)
  end

  def settings(code)
    JSON.parse(file_fixture('commerce/salla/app_settings_updated.json').read).tap do |payload|
      payload['data']['settings']['lynomia_connection_code'] = code
    end
  end

  def process(payload)
    described_class.new(payload).process
  end

  def code_for(target_account, user)
    Commerce::Salla::ConnectionCode.create(account: target_account, user: user)[:code]
  end

  def salla_store
    Commerce::Store.find_by(provider: 'salla', external_store_id: '1234509876')
  end

  def disable_salla
    InstallationConfig.find_by!(name: 'SALLA_ENABLED').update!(value: false)
    GlobalConfig.clear_cache
  end

  describe 'connecting a new store' do
    it 'never attaches an installation to an account on its own' do
      process(authorize)

      expect(Commerce::Store.count).to eq(0)
      expect(Commerce::Salla::ConnectionCode.status(account)).to eq(status: 'none')
    end

    it 'keeps waiting tokens encrypted in Redis' do
      process(authorize)

      raw = Redis::Alfred.get('COMMERCE::SALLA::MERCHANT::1234509876::TOKENS')
      expect(raw).to be_present
      expect(raw).not_to include('salla-access-token-fixture', 'salla-refresh-token-fixture')
    end

    it 'connects the store to the account whose code the merchant entered, authorization first' do
      code = code_for(account, admin)
      process(authorize)
      process(settings(code))

      expect(salla_store).to have_attributes(account_id: account.id, status: 'active', name: 'Syria Cosmetics', created_by_id: admin.id,
                                             base_url: 'https://salla.sa/dev-store-name')
      expect(Commerce::Salla::ConnectionCode.status(account)).to include(status: 'connected', store_id: salla_store.id)
    end

    it 'connects the store when the code arrives before the authorization' do
      process(settings(code_for(account, admin)))
      expect(Commerce::Salla::ConnectionCode.status(account)).to include(status: 'claimed')

      process(authorize)

      expect(salla_store.account_id).to eq(account.id)
      expect(Redis::Alfred.get('COMMERCE::SALLA::MERCHANT::1234509876::TOKENS')).to be_nil
      expect(Redis::Alfred.get('COMMERCE::SALLA::MERCHANT::1234509876::CLAIM')).to be_nil
    end

    it 'stores the tokens encrypted at rest, with their expiry and scope' do
      process(settings(code_for(account, admin)))
      process(authorize)

      expect(salla_store.credentials).to eq(
        'access_token' => 'salla-access-token-fixture', 'refresh_token' => 'salla-refresh-token-fixture', 'token_type' => 'bearer',
        'scope' => 'offline_access customers.read orders.read shipping.read',
        'access_token_expires_at' => Time.zone.at(1_900_000_000).utc.iso8601, 'refresh_token_expires_at' => nil
      )
      raw = Commerce::Store.connection.select_value("SELECT credentials FROM commerce_stores WHERE id = #{salla_store.id}")
      expect(raw).not_to include('salla-access-token-fixture', 'salla-refresh-token-fixture')
    end

    it 'identifies the store by the merchant id, keeping the authorizing user by id only' do
      process(settings(code_for(account, admin)))
      process(authorize)

      expect(salla_store.metadata).to include('authorized_by_salla_user_id' => 1_771_165_749)
      expect(salla_store.attributes.to_json).not_to include('testuser@email.partners')
    end

    it 'records the connection in the audit log without credentials', if: defined?(Enterprise::AuditLog) do
      process(settings(code_for(account, admin)))
      process(authorize)

      logs = Enterprise::AuditLog.where(associated: account).where("comment LIKE 'commerce.%'").order(:id)
      expect(logs.pluck(:comment, :user_id)).to eq([['commerce.salla.connect_started', admin.id], ['commerce.salla.connected', admin.id]])
      expect(logs.to_json).not_to include('salla-access-token-fixture', 'salla-refresh-token-fixture')
    end

    it 'accepts a code once' do
      code = code_for(account, admin)
      process(settings(code))
      process(authorize)
      process(uninstalled)

      process(settings(code))
      process(authorize)

      expect(salla_store).to be_disconnected
    end

    it 'ignores a code it did not issue' do
      code_for(account, admin)
      process(settings('ZZZZ-ZZZZ-ZZZZ-ZZZZ'))
      process(authorize)

      expect(Commerce::Store.count).to eq(0)
      expect(Commerce::Salla::ConnectionCode.status(account)).to include(status: 'waiting')
    end

    it 'refuses tokens that do not belong to the merchant of the event' do
      stub_request(:get, 'https://accounts.salla.sa/oauth2/user/info')
        .to_return(status: 200, body: JSON.parse(user_info).deep_merge('merchant' => { 'id' => 999 }).to_json)

      expect { process(authorize) }.to raise_error(Commerce::Error) { |error| expect(error.reason).to eq('salla_merchant_mismatch') }
      expect(Redis::Alfred.get('COMMERCE::SALLA::MERCHANT::1234509876::TOKENS')).to be_nil
    end

    it 'refuses tokens with a write scope, or without a scope it needs, and stores nothing' do
      process(settings(code_for(account, admin)))
      { 'offline_access customers.read orders.read_write shipping.read' => 'salla_write_scope',
        'offline_access customers.read orders.read' => 'salla_missing_scope' }.each do |scope, reason|
        payload = authorize.deep_merge('data' => { 'scope' => scope })

        expect { process(payload) }.to raise_error(Commerce::Error) { |error|
          expect([error.code, error.reason]).to eq(['PERMISSION_DENIED', reason])
        }
      end
      expect(Commerce::Store.count).to eq(0)
      expect(user_info_stub).not_to have_been_requested
    end

    it 'refuses a malformed authorization' do
      [authorize.merge('merchant' => '1234509876'), authorize.deep_merge('data' => { 'expires' => '1900000000' }),
       authorize.deep_merge('data' => { 'token_type' => 'mac' }), authorize.deep_merge('data' => { 'refresh_token' => nil })].each do |payload|
        expect { process(payload) }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('INVALID_RESPONSE') }
      end
    end
  end

  describe 'a store that is already connected' do
    before do
      process(settings(code_for(account, admin)))
      process(authorize)
    end

    it 'takes the tokens of a later authorization without creating another store' do
      stub_request(:get, 'https://accounts.salla.sa/oauth2/user/info').with(headers: { 'Authorization' => 'Bearer access-2' })
                                                                      .to_return(status: 200, body: user_info)

      2.times { process(authorize.deep_merge('data' => { 'access_token' => 'access-2', 'refresh_token' => 'refresh-2' })) }

      expect(Commerce::Store.where(provider: 'salla').count).to eq(1)
      expect(salla_store.credentials).to include('access_token' => 'access-2', 'refresh_token' => 'refresh-2')
    end

    it 'brings a store that needed re-authorization back, and keeps a disabled store disabled' do
      salla_store.update!(status: :needs_reauth)
      process(authorize)
      expect(salla_store).to be_active

      salla_store.update!(status: :disabled)
      process(authorize)
      expect(salla_store).to be_disabled
    end

    it 'audits a re-authorization without tokens', if: defined?(Enterprise::AuditLog) do
      process(authorize)

      log = Enterprise::AuditLog.where(auditable: salla_store, comment: 'commerce.salla.reauthorized').sole
      expect(log.to_json).not_to include('salla-access-token-fixture', 'salla-refresh-token-fixture')
    end

    it 'is never moved to another account: a code from another account is a conflict' do
      other_account = create(:account)
      other_admin = create(:user, account: other_account, role: :administrator)

      process(settings(code_for(other_account, other_admin)))

      expect(salla_store.account_id).to eq(account.id)
      expect(Commerce::Salla::ConnectionCode.status(other_account)).to include(status: 'conflict')
      expect(Commerce::Store.where(account: other_account)).to be_empty
    end

    it 'reports a second code from the same account as connected' do
      process(settings(code_for(account, admin)))

      expect(Commerce::Salla::ConnectionCode.status(account)).to include(status: 'connected', store_id: salla_store.id)
    end

    it 'is disconnected when the merchant uninstalls the app, keeping contacts and conversations' do
      contact = create(:contact, account: account)
      conversation = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: contact)
      create(:commerce_customer_link, store: salla_store, account: account, contact: contact)
      Redis::Alfred.setex("COMMERCE::V1::ACCOUNT::#{account.id}::STORE::#{salla_store.id}::ORDERS::x", '{}', 60)

      process(uninstalled)

      expect(salla_store).to have_attributes(status: 'disconnected', credentials: nil)
      expect(salla_store.customer_links).to be_empty
      expect(Redis::Alfred.get("COMMERCE::V1::ACCOUNT::#{account.id}::STORE::#{salla_store.id}::ORDERS::x")).to be_nil
      expect([Contact.exists?(contact.id), Conversation.exists?(conversation.id)]).to eq([true, true])
    end

    it 'audits the uninstall', if: defined?(Enterprise::AuditLog) do
      process(uninstalled)

      expect(Enterprise::AuditLog.where(auditable: salla_store).order(:id).last)
        .to have_attributes(comment: 'commerce.salla.disconnected', action: 'destroy', user_id: nil)
    end

    it 'needs a new code and a new authorization after an uninstall, then reuses its row' do
      store_id = salla_store.id
      process(uninstalled)

      process(authorize)
      expect(salla_store).to be_disconnected

      process(settings(code_for(account, admin)))
      expect(salla_store).to have_attributes(id: store_id, status: 'active')
    end

    it 'is released to another account only after it was disconnected' do
      other_account = create(:account)
      other_admin = create(:user, account: other_account, role: :administrator)
      process(uninstalled)

      process(settings(code_for(other_account, other_admin)))
      process(authorize)

      expect(salla_store.account_id).to eq(other_account.id)
    end
  end

  describe 'when the installation has Salla switched off' do
    it 'ignores new installations and codes without calling Salla' do
      code = code_for(account, admin)
      disable_salla

      process(settings(code))
      process(authorize)

      expect(Commerce::Store.count).to eq(0)
      expect(user_info_stub).not_to have_been_requested
    end

    it 'still keeps connected stores current and processes uninstalls' do
      process(settings(code_for(account, admin)))
      process(authorize)
      salla_store.update!(status: :needs_reauth)
      disable_salla

      process(authorize)
      expect(salla_store).to be_active

      process(uninstalled)
      expect(salla_store).to be_disconnected
    end
  end

  it 'ignores app.updated, which only announces the authorization that follows' do
    expect { process(JSON.parse(file_fixture('commerce/salla/app_updated.json').read)) }.not_to change(Commerce::Store, :count)
  end
end
