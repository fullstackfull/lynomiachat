require 'rails_helper'

# A provider refusing to deliver an outgoing message used to be recorded in the database and nowhere else. These
# examples pin that it now reaches the log, at a level chosen by whether the operator can do anything about it, and
# that the line carries identifiers rather than customer content.
RSpec.describe Messages::StatusUpdateService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing) }

  def emitted(level)
    captured = []
    allow(Rails.logger).to receive(level) { |line| captured << line }
    yield
    captured.grep(/OUTGOING_DELIVERY_FAILED/)
  end

  it 'reports a recipient-scoped refusal as a warning, because Meta will refuse it again' do
    lines = emitted(:warn) { described_class.new(message, 'failed', '131049: Message not delivered').perform }

    expect(lines.size).to eq(1)
    expect(lines.first).to include('classification=META_RECIPIENT_DELIVERY_RESTRICTION', 'code=131049',
                                   'retry_policy=DO_NOT_AUTO_RETRY', "account=#{account.id}", "inbox=#{inbox.id}",
                                   "message=#{message.id}")
  end

  it 'reports a billing refusal as an error, because an operator can fix it' do
    lines = emitted(:error) { described_class.new(message, 'failed', '131042: payment issue').perform }

    expect(lines.size).to eq(1)
    expect(lines.first).to include('classification=META_BILLING_ELIGIBILITY', 'code=131042')
  end

  it 'reports an unclassified failure as an error, because nobody has decided what it means' do
    lines = emitted(:error) { described_class.new(message, 'failed', '999999: something new').perform }

    expect(lines.first).to include('classification=UNCLASSIFIED', 'code=999999')
  end

  it 'reports a failure with no provider code at all' do
    lines = emitted(:error) { described_class.new(message, 'failed', 'connection reset').perform }

    expect(lines.first).to include('classification=UNCLASSIFIED')
    expect(lines.first).not_to include('code=')
  end

  it 'never puts the message body or the recipient in the line' do
    message.update!(content: 'Your order 1234 is ready, Mohammed')
    contact = message.conversation.contact
    contact.update!(phone_number: '+96512345678')

    lines = emitted(:warn) { described_class.new(message, 'failed', '131049: Message not delivered').perform }

    expect(lines.first).not_to include('Mohammed', '1234', '96512345678')
  end

  it 'does not report again when an already-failed message is updated' do
    described_class.new(message, 'failed', '131049: Message not delivered').perform

    lines = emitted(:warn) { described_class.new(message, 'failed', '131049: Message not delivered').perform }

    expect(lines).to be_empty
  end

  it 'reports nothing for a successful delivery' do
    lines = emitted(:info) { described_class.new(message, 'delivered').perform }
    expect(lines).to be_empty
  end

  it 'still records the status and the error on the row' do
    described_class.new(message, 'failed', '131049: Message not delivered').perform

    expect(message.reload).to have_attributes(status: 'failed', external_error: '131049: Message not delivered')
  end
end
