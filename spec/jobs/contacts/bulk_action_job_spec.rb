require 'rails_helper'

RSpec.describe Contacts::BulkActionJob, type: :job do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:params) { { 'ids' => [1], 'labels' => { 'add' => ['vip'] } } }

  it 'invokes the bulk action service with account and user' do
    service_instance = instance_double(Contacts::BulkActionService, perform: true)

    allow(Contacts::BulkActionService).to receive(:new).and_return(service_instance)

    described_class.perform_now(account.id, user.id, params)

    expect(Contacts::BulkActionService).to have_received(:new).with(
      account: account,
      user: user,
      params: params
    )
    expect(service_instance).to have_received(:perform)
  end

  it 'names the initiating user as the performer of every write' do
    performer = nil
    allow(Contacts::BulkActionService).to receive(:new).and_return(
      instance_double(Contacts::BulkActionService).tap do |service|
        allow(service).to receive(:perform) { performer = Current.user }
      end
    )

    described_class.perform_now(account.id, user.id, params)

    expect(performer).to eq(user)
    expect(Current.user).to be_nil
  end

  it 'tells the initiating user, and only them, that the work is done' do
    allow(Contacts::BulkActionService).to receive(:new).and_return(
      instance_double(Contacts::BulkActionService, perform: true)
    )

    expect { described_class.perform_now(account.id, user.id, params) }
      .to have_enqueued_job(ActionCableBroadcastJob)
      .with([user.pubsub_token], 'contact.bulk_action_completed', { account_id: account.id })
  end

  it 'does not announce completion when the bulk action fails' do
    allow(Contacts::BulkActionService).to receive(:new).and_raise(StandardError, 'boom')

    expect { described_class.perform_now(account.id, user.id, params) }.to raise_error(StandardError)
    expect(ActionCableBroadcastJob).not_to have_been_enqueued
  end
end
