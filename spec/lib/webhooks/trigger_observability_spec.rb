require 'rails_helper'

# An outbound webhook failure used to log the endpoint's full URL and nothing identifying, and the exception is
# swallowed so it never reaches Sidekiq's retry or dead set. The swallowing is upstream's delivery policy and is
# unchanged; these examples pin that the failure is now findable, and that a token in a customer's webhook URL does
# not end up in our logs.
RSpec.describe Webhooks::Trigger do
  let(:account) { create(:account) }
  let(:url) { 'https://customer.example.com/hooks/inbound?token=super-secret-value' }
  let(:payload) { { event: 'message_created', account: { id: account.id, name: account.name } } }
  let(:error) { StandardError.new('Connection refused') }

  def failure_lines(trigger)
    captured = []
    allow(Rails.logger).to receive(:error) { |line| captured << line }
    allow(Rails.logger).to receive(:warn)
    trigger.handle_failure(error)
    captured.grep(/OUTBOUND_WEBHOOK_FAILED/)
  end

  it 'names the account, the event and the webhook type' do
    lines = failure_lines(described_class.new(url, payload, :account_webhook, delivery_id: 'del-1'))

    expect(lines.size).to eq(1)
    expect(lines.first).to include("account=#{account.id}", 'event=message_created',
                                   'webhook_type=account_webhook', 'delivery=del-1',
                                   'endpoint_host=customer.example.com')
  end

  it 'does not put the endpoint URL or its query string in the log' do
    line = failure_lines(described_class.new(url, payload, :account_webhook)).first

    expect(line).not_to include('super-secret-value', 'token=', '/hooks/inbound')
  end

  it 'identifies the endpoint by a stable digest instead' do
    first = failure_lines(described_class.new(url, payload, :account_webhook)).first
    second = failure_lines(described_class.new(url, payload, :account_webhook)).first
    other = failure_lines(described_class.new('https://elsewhere.example.com/h', payload, :account_webhook)).first

    digest = ->(line) { line[/endpoint_digest=(\w+)/, 1] }
    expect(digest.call(first)).to eq(digest.call(second))
    expect(digest.call(first)).not_to eq(digest.call(other))
  end

  it 'records the HTTP status when the provider gave one' do
    http_error = SafeFetch::HttpError.new('502 Bad Gateway')
    trigger = described_class.new(url, payload, :account_webhook)
    captured = []
    allow(Rails.logger).to receive(:error) { |line| captured << line }
    allow(Rails.logger).to receive(:warn)

    trigger.handle_failure(http_error)

    expect(captured.grep(/OUTBOUND_WEBHOOK_FAILED/).first).to include('http_status=502')
  end

  it 'survives a payload with no account and an unparseable url' do
    lines = failure_lines(described_class.new('not a url', { event: 'message_created' }, :account_webhook))

    expect(lines.size).to eq(1)
    expect(lines.first).to include('event=message_created')
  end
end
