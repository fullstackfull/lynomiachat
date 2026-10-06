require 'rails_helper'

# P6 Stage B: what `targeted_at` on a durable cart row means, and that two workers cannot set it twice
# (docs/commerce-production/07-abandoned-cart-automation.md §targeting).
#
# It means exactly one thing: a real Lynomia abandoned-cart outreach was successfully accepted for sending. The only
# moment that is true is a confirmed outgoing, non-private message carrying the link the recovery message was
# prepared with — which is what Commerce::RecoveryListener already detects.
RSpec.describe Commerce::RecoveryListener do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:account) { create(:account) }
  let(:store) { create(:commerce_store, :zid, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:recovery_url) { 'https://zid-store.zid.store/checkout/abc-123' }
  let(:cart) do
    Commerce::Cart.create!(account: account, commerce_store: store, provider: 'zid', provider_cart_id: 'zc-3003',
                           contact: contact, state: :abandoned, first_seen_at: 2.hours.ago,
                           last_provider_event_at: 2.hours.ago, abandoned_at: 2.hours.ago)
  end

  # A prepared-but-unsent recovery message, exactly as Commerce::RecoveryMessages records one.
  let!(:run) do
    Commerce::ActionRun.create!(account_id: account.id, store: store, contact_id: contact.id, conversation_id: conversation.id,
                                provider: 'zid', action_type: Commerce::ActionRun::RECOVERY_MESSAGE,
                                external_resource_id: cart.provider_cart_id, idempotency_key: "commerce-recovery:#{SecureRandom.uuid}",
                                request_digest: Commerce::RecoveryMessages.url_digest(recovery_url), status: :pending)
  end

  # The listener is asynchronous, so a spec drives it the way spec/listeners/commerce/recovery_listener_spec.rb
  # does: create the message, then hand the event to the listener.
  def agent_sends!(body, private: false)
    message = create(:message, account: account, conversation: conversation, message_type: :outgoing, content: body,
                               private: private)
    described_class.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
    message
  end

  it 'is nil while the message is only prepared' do
    expect(cart.reload.targeted_at).to be_nil
    expect(run.reload).to be_pending
  end

  it 'is set when the prepared outreach is confirmed sent' do
    message = agent_sends!("Your cart is waiting: #{recovery_url}")

    expect(cart.reload.targeted_at).to be_within(2.seconds).of(message.created_at)
    expect(run.reload).to be_succeeded
  end

  it 'is not set by an outgoing message that does not carry the prepared link' do
    agent_sends!('Hello, can I help with anything?')

    expect(cart.reload.targeted_at).to be_nil
  end

  it 'is not set by a private note carrying the link' do
    agent_sends!("internal: #{recovery_url}", private: true)

    expect(cart.reload.targeted_at).to be_nil
  end

  it 'keeps the first send when two confirmations race' do
    first = agent_sends!("First: #{recovery_url}")
    targeted = cart.reload.targeted_at

    # A second confirmation for the same cart, as a retried listener or a concurrent worker would produce.
    agent_sends!("Again: #{recovery_url}")

    expect(cart.reload.targeted_at).to be_within(2.seconds).of(first.created_at)
    expect(cart.reload.targeted_at).to eq(targeted)
  end

  it 'claims the row with one conditional statement, not a read then a write' do
    body = File.read(Rails.root.join('custom/app/listeners/commerce/recovery_listener.rb'))

    expect(body).to include('targeted_at: nil').and include('update_all(targeted_at:')
  end

  describe 'what the lifecycle can then say, and what it cannot' do
    it 'reports a completion after targeting as a post-target completion, never as a recovery' do
      agent_sends!("Your cart is waiting: #{recovery_url}")
      cart.reload.update!(state: :completed, completed_at: 1.minute.from_now, provider_order_id: '9001')

      expect(cart.reload).to be_post_target_completion
      expect(cart).to be_order_attributed
      expect(Commerce::Cart.states.keys).not_to include('recovered')
      expect(Commerce::Cart.instance_methods).not_to include(:recovered?)
    end

    it 'reports a completion with no outreach as untargeted' do
      cart.update!(state: :completed, completed_at: Time.current)

      expect(cart.reload).to be_untargeted_completion
      expect(cart).not_to be_post_target_completion
    end

    it 'keeps a completion with no provider order id unattributed' do
      cart.update!(state: :completed, completed_at: Time.current, provider_order_id: nil)

      expect(cart.reload).not_to be_order_attributed
    end
  end
end
