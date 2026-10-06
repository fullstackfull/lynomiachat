require 'rails_helper'

# A template that Meta rejects, pauses or disables stops being sendable. That used to happen with no log line and no
# audit row -- this runs inside without_auditing -- so the first anyone knew was a campaign quietly refusing to send.
RSpec.describe Whatsapp::Templates::StatusUpdate do
  let(:account) { create(:account) }
  let(:waba) { 'waba-observability-1' }
  let(:template) do
    Whatsapp::MessageTemplate.create!(account: account, business_account_id: waba, name: 'order_update',
                                      language: 'en_US', category: 'UTILITY', meta_template_id: '55501',
                                      meta_status: 'PENDING',
                                      components: [{ 'type' => 'BODY', 'text' => 'Order {{1}}' }])
  end

  def apply(event, extra = {})
    captured = { info: [], warn: [], error: [] }
    captured.each_key { |level| allow(Rails.logger).to receive(level) { |line| captured[level] << line } }
    described_class.new(waba, { message_template_id: template.meta_template_id, event: event }.merge(extra)).perform
    captured.transform_values { |lines| lines.grep(/WHATSAPP_TEMPLATE_STATUS_CHANGED/) }
  end

  it 'reports an approval at info, because it is what the operator was waiting for' do
    lines = apply('APPROVED')

    expect(lines[:info].size).to eq(1)
    expect(lines[:info].first).to include('from=PENDING', 'to=APPROVED', 'template=order_update',
                                          'language=en_US', "account=#{account.id}", "waba=#{waba}")
    expect(lines[:warn] + lines[:error]).to be_empty
  end

  it 'reports a rejection at warning, with Meta own reason' do
    lines = apply('REJECTED', reason: 'INCORRECT_CATEGORY')

    expect(lines[:warn].size).to eq(1)
    expect(lines[:warn].first).to include('to=REJECTED', 'reason=INCORRECT_CATEGORY')
  end

  it 'reports a pause at warning' do
    expect(apply('PAUSED')[:warn].first).to include('to=PAUSED')
  end

  it 'reports a permanent disable at error, because the template can never be sent again' do
    lines = apply('DISABLED')

    expect(lines[:error].size).to eq(1)
    expect(lines[:error].first).to include('from=PENDING', 'to=DISABLED')
  end

  it 'reports nothing when the status did not actually change' do
    lines = apply('PENDING')
    expect(lines.values.flatten).to be_empty
  end

  it 'reports nothing for an event that is not a status, since the status is unchanged' do
    lines = apply('FLAGGED')

    expect(lines.values.flatten).to be_empty
    expect(template.reload.meta_payload['last_event']).to eq('FLAGGED')
  end

  it 'still applies the status to the row' do
    apply('APPROVED')
    expect(template.reload.meta_status).to eq('APPROVED')
  end
end
