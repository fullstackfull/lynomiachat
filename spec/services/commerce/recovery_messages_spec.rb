require 'rails_helper'

# Preparing a recovery message (docs/commerce/31-sales-recovery.md): only into the reply box, only inside the channel's
# reply window, never twice within the cooldown without an administrator, never with an unsafe link. Zid's documented
# abandoned carts API answers.
RSpec.describe Commerce::RecoveryMessages do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:store) do
    create(:commerce_store, :zid, account: account, external_store_id: '318001', base_url: 'https://my-store.zid.store',
                                  metadata: { 'time_zone' => 'Asia/Riyadh' })
  end
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:contact) { create(:contact, account: account, name: 'Omar Khalil') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp.inbox, contact: contact,
                          contact_inbox: create(:contact_inbox, contact: contact, inbox: whatsapp.inbox, source_id: '966551112233'))
  end
  let(:cart_id) { 'c0ffee01-0000-4000-8000-000000000000' }
  let(:cart) do
    { id: cart_id, url: 'https://my-store.zid.store/cart/recover/1', phase: 'payment_method', customer_mobile: '966551112233',
      cart_total: 120.5, currency_code: 'SAR', products: [{ name: 'Oud', quantity: 2 }],
      created_at: 2.hours.ago.in_time_zone('Asia/Riyadh').strftime('%F %T') }
  end
  let(:detail) do
    lambda do |fields = {}|
      stub_request(:get, %r{/abandoned-carts/#{cart_id}\z}).to_return(status: 200, body: { abandoned_cart: cart.merge(fields) }.to_json)
    end
  end
  let(:prepare) do
    lambda do |user = agent, override: false|
      described_class.new(store: store, conversation: conversation, user: user, account_user: account.account_users.find_by(user: user))
                     .prepare(cart_id, override_cooldown: override)
    end
  end

  around { |example| with_modified_env(COMMERCE_ALLOW_PRE_UAT_PROVIDERS: 'true') { example.run } }

  before do
    InstallationConfig.where(name: 'ZID_RECOVERY_ENABLED').first_or_initialize.update!(value: true, locked: false)
    GlobalConfig.clear_cache
    Redis::Alfred.scan_each(match: 'COMMERCE::RECOVERY_PREPARE::*') { |key| Redis::Alfred.delete(key) }
    create(:message, conversation: conversation, account: account, inbox: whatsapp.inbox, message_type: :incoming, created_at: 1.hour.ago)
    detail.call
  end

  it 'reads the cart again and returns the message parts for the reply box, sending nothing' do
    result = nil
    expect { result = prepare.call }.not_to change(Message, :count)

    expect(result).to include(recovery_url: 'https://my-store.zid.store/cart/recover/1', first_name: 'Omar', total: '120.5', currency: 'SAR',
                              store: { id: store.id, name: store.name }, items_count: 2)
    run = Commerce::ActionRun.find(result[:run_id])
    expect(run).to have_attributes(action_type: 'recovery_message', status: 'pending', external_resource_id: cart_id, requested_by: agent,
                                   conversation_id: conversation.id)
    expect(run.metadata.keys).to contain_exactly('url_digest', 'total', 'currency', 'match')
    expect(run.metadata.to_json).not_to include('recover/1', '966551112233')
  end

  it 'prepares nothing outside the channel\'s reply window, and says why' do
    conversation.messages.incoming.update_all(created_at: 25.hours.ago) # rubocop:disable Rails/SkipsModelValidations

    expect { prepare.call }.to raise_error(Commerce::Error) { |error| expect(error.as_json).to eq(code: 'CANNOT_REPLY', reason: 'messaging_window') }
    expect(Commerce::ActionRun.count).to eq(0)
  end

  it 'refuses a second message within the cooldown, unless an administrator overrides it once' do
    run = Commerce::ActionRun.find(prepare.call[:run_id])
    run.update!(status: :succeeded, completed_at: 1.hour.ago)

    expect { prepare.call }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('RECOVERY_COOLDOWN') }
    expect { prepare.call(agent, override: true) }.to raise_error(Pundit::NotAuthorizedError)
    expect(prepare.call(admin, override: true)).to include(:run_id)
    expect(Commerce::ActionRun.last.metadata).to include('override_cooldown' => true)

    run.update!(completed_at: 25.hours.ago)
    expect(prepare.call).to include(:run_id)
  end

  it 'prepares nothing for a recovered, expired or someone else\'s cart, or with an unsafe link' do
    {
      { phase: 'completed' } => 'CART_NOT_ABANDONED', { order_id: 9 } => 'CART_NOT_ABANDONED',
      { created_at: 40.days.ago.in_time_zone('Asia/Riyadh').strftime('%F %T') } => 'CART_NOT_ABANDONED',
      { customer_mobile: '966500000000' } => 'NOT_FOUND', { url: 'javascript:alert(1)' } => 'INVALID_RECOVERY_URL',
      { url: 'https://bit.ly/abc' } => 'INVALID_RECOVERY_URL', { url: 'http://my-store.zid.store/cart' } => 'INVALID_RECOVERY_URL'
    }.each do |fields, code|
      detail.call(fields)
      expect { prepare.call }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq(code) }
    end
    expect(Commerce::ActionRun.count).to eq(0)
  end

  it 'reads nothing while the installation keeps the provider\'s carts off' do
    InstallationConfig.find_by!(name: 'ZID_RECOVERY_ENABLED').update!(value: false)
    GlobalConfig.clear_cache

    expect { prepare.call }.to raise_error(Commerce::Error, 'RECOVERY_DISABLED')
    expect(a_request(:get, /abandoned-carts/)).not_to have_been_made
  end

  it 'limits how many messages an agent prepares' do
    Redis::Alfred.set("COMMERCE::RECOVERY_PREPARE::ACCOUNT::#{account.id}::USER::#{agent.id}", described_class::PREPARE_LIMIT, ex: 600)

    expect { prepare.call }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('RATE_LIMITED') }
  end
end
