require 'rails_helper'

RSpec.describe Webhooks::SmsEventsJob do
  subject(:job) { described_class.perform_later(params) }

  let!(:sms_channel) { create(:channel_sms) }
  let!(:params) do
    {
      channel_id: sms_channel.id,
      time: '2022-02-02T23:14:05.309Z',
      type: 'message-received',
      to: sms_channel.phone_number,
      description: 'Incoming message received',
      message: {
        'id': '3232420-2323-234324',
        'owner': sms_channel.phone_number,
        'applicationId': '2342349-324234d-32432432',
        'time': '2022-02-02T23:14:05.262Z',
        'segmentCount': 1,
        'direction': 'in',
        'to': [
          sms_channel.phone_number
        ],
        'from': '+14234234234',
        'text': 'test message'
      }
    }
  end

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(params)
      .on_queue('default')
  end

  context 'when invalid params' do
    it 'returns nil when no bot_token' do
      expect(described_class.perform_now({})).to be_nil
    end

    it 'returns nil when invalid type' do
      expect(described_class.perform_now({ type: 'invalid' })).to be_nil
    end

    # The controller authenticates the delivery and resolves the channel; the payload is never allowed to
    # pick the tenant, so a job without channel_id is dropped (docs/p11/00-p10-security-closure.md).
    it 'returns nil when the job carries no channel_id' do
      expect(described_class.perform_now(params.except(:channel_id))).to be_nil
    end

    it 'returns nil when channel_id names a channel that no longer exists' do
      expect(described_class.perform_now(params.merge(channel_id: 0))).to be_nil
    end
  end

  context 'when valid params' do
    it 'calls Sms::IncomingMessageService if the message type is message-received' do
      process_service = double
      allow(Sms::IncomingMessageService).to receive(:new).and_return(process_service)
      allow(process_service).to receive(:perform)
      expect(Sms::IncomingMessageService).to receive(:new).with(inbox: sms_channel.inbox,
                                                                params: params[:message].with_indifferent_access)
      expect(process_service).to receive(:perform)
      described_class.perform_now(params)
    end

    # These two used to assert `channel:` and the nested `params[:message]`. Sms::DeliveryStatusService takes
    # `inbox:` and reads the envelope -- `type`, `description`, `errorCode` all live there, and its own spec
    # has always passed it that way -- so every real receipt raised ArgumentError. Because the service was a
    # double here, the test never ran the real initializer and the mismatch survived. Asserting the true
    # contract now; spec/requests/webhooks/sms_security_spec.rb also exercises it unmocked.
    %w[message-delivered message-failed].each do |event_type|
      it "calls Sms::DeliveryStatusService with the envelope for #{event_type}" do
        params[:type] = event_type
        process_service = double
        allow(Sms::DeliveryStatusService).to receive(:new).and_return(process_service)
        allow(process_service).to receive(:perform)
        expect(Sms::DeliveryStatusService).to receive(:new).with(inbox: sms_channel.inbox,
                                                                 params: params.with_indifferent_access)
        expect(process_service).to receive(:perform)
        described_class.perform_now(params)
      end
    end

    it 'does not call any service if the message type is not supported' do
      params[:type] = 'message-sent'
      expect(Sms::IncomingMessageService).not_to receive(:new)
      expect(Sms::DeliveryStatusService).not_to receive(:new)
      described_class.perform_now(params)
    end
  end
end
