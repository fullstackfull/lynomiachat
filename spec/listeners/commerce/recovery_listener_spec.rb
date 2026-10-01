require 'rails_helper'

# A prepared recovery message counts as sent only when the agent's message carrying its link goes out
# (docs/commerce/31-sales-recovery.md §tracking).
RSpec.describe Commerce::RecoveryListener do
  include_context 'with commerce encryption'

  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:store) { create(:commerce_store, :zid, account: account) }
  let(:url) { 'https://my-store.zid.store/cart/recover/1?key=abc' }
  let!(:run) do
    digest = Commerce::RecoveryMessages.url_digest(url)
    Commerce::ActionRun.create!(account: account, store: store, conversation: conversation, contact: conversation.contact, requested_by: agent,
                                provider: 'zid', action_type: 'recovery_message', external_resource_id: 'c0ffee01',
                                idempotency_key: "commerce-recovery:#{SecureRandom.uuid}", request_digest: digest,
                                metadata: { 'url_digest' => digest })
  end
  let(:deliver) do
    lambda do |content, **attributes|
      message = create(:message, account: account, inbox: inbox, conversation: attributes.fetch(:conversation, conversation), sender: agent,
                                 content: content, message_type: attributes.fetch(:message_type, :outgoing),
                                 private: attributes.fetch(:private, false))
      listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
      message
    end
  end

  it 'is one of the asynchronous listeners' do
    expect(AsyncDispatcher.new.listeners).to include(described_class.instance)
  end

  it 'marks the recovery message sent when the agent sends its link, as text or as a link' do
    message = deliver.call("Hi Omar, complete your order here: [#{url}](#{url}).")

    expect(run.reload).to have_attributes(status: 'succeeded', completed_at: be_within(1.second).of(message.created_at))
    expect(run.metadata).to include('message_id' => message.id)
  end

  it 'ignores private notes, incoming messages, other links, other conversations and stale preparations' do
    deliver.call("note: #{url}", private: true)
    deliver.call("customer said #{url}", message_type: :incoming)
    deliver.call('https://my-store.zid.store/cart/recover/2')
    deliver.call(url, conversation: create(:conversation, account: account, inbox: inbox))
    expect(run.reload).to be_pending

    run.update!(created_at: 25.hours.ago)
    deliver.call(url)
    expect(run.reload).to be_pending
  end
end
