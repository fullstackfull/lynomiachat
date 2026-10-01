require 'rails_helper'

# commerce.customer.updated goes to the account's ActionCable stream (docs/commerce/26-realtime-security.md §websocket):
# only that account's agents subscribe to it, and a widget visitor never does.
RSpec.describe RoomChannel do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:outsider) { create(:user, account: other_account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: create(:inbox, account: account)) }

  before { stub_connection }

  it 'streams an account only to its own agents' do
    subscribe(user_id: agent.id, pubsub_token: agent.pubsub_token, account_id: account.id)
    expect(subscription).to have_stream_from("account_#{account.id}")

    expect { subscribe(user_id: outsider.id, pubsub_token: outsider.pubsub_token, account_id: account.id) }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect { subscribe(user_id: agent.id, pubsub_token: outsider.pubsub_token, account_id: account.id) }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'never streams an account to a widget visitor' do
    subscribe(pubsub_token: contact_inbox.pubsub_token, account_id: account.id)

    expect(subscription).to be_confirmed
    expect(subscription.streams).to eq([contact_inbox.pubsub_token])
  end
end
