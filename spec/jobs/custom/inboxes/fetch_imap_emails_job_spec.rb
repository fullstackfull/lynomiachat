require 'rails_helper'

# The worst gap the P9 discovery found: a plain-password IMAP inbox whose password was rotated writes NOTHING to
# Postgres and reports a SUCCESSFUL Sidekiq job (app/jobs/inboxes/fetch_imap_emails_job.rb:14-16), then stops
# polling itself so the inbox goes quiet rather than erroring.
RSpec.describe Custom::Inboxes::FetchImapEmailsJob do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_email, account: account, imap_enabled: true, imap_address: 'imap.test',
                           imap_login: 'bot@test', imap_password: 'secret', imap_port: 993)
  end

  it 'is prepended into the OSS job' do
    expect(Inboxes::FetchImapEmailsJob.ancestors).to include(described_class)
  end

  def run
    Inboxes::FetchImapEmailsJob.perform_now(channel)
  end

  context 'when the mail server refuses the credentials' do
    before do
      allow(Imap::FetchEmailService).to receive(:new)
        .and_return(instance_double(Imap::FetchEmailService).tap do |service|
          allow(service).to receive(:perform).and_raise(Net::IMAP::NoResponseError, imap_response)
        end)
    end

    let(:imap_response) do
      Net::IMAP::TaggedResponse.new('a1', 'NO', Net::IMAP::ResponseText.new(nil, 'Invalid credentials'), 'raw')
    end

    it 'records a critical, durable signal against the inbox' do
      run

      signal = Operations::Signal.open_signals.find_by(source: 'email_channel')
      expect(signal.signal).to eq('authentication_failed')
      expect(signal.severity).to eq('critical')
      expect(signal.subject).to eq(channel.inbox)
      expect(signal.account_id).to eq(account.id)
    end

    it 'never writes the password or the login into the signal' do
      run

      body = Operations::Signal.first.attributes.to_s
      expect(body).not_to include('secret')
      expect(body).not_to include('bot@test')
    end

    # One row with a rising count, not one row per poll.
    it 'increments rather than inserting on every poll' do
      3.times { run }

      expect(Operations::Signal.count).to eq(1)
      expect(Operations::Signal.first.occurrences).to eq(3)
    end
  end

  context 'when the connection itself fails' do
    before do
      allow(Imap::FetchEmailService).to receive(:new)
        .and_return(instance_double(Imap::FetchEmailService).tap do |service|
          allow(service).to receive(:perform).and_raise(Errno::ECONNREFUSED)
        end)
    end

    # A refused connection and a refused password are different problems with different fixes.
    it 'records a warning under a different signal name' do
      run

      signal = Operations::Signal.open_signals.find_by(source: 'email_channel')
      expect(signal.signal).to eq('connection_failed')
      expect(signal.severity).to eq('warning')
    end
  end

  context 'when the fetch succeeds' do
    before do
      allow(Imap::FetchEmailService).to receive(:new)
        .and_return(instance_double(Imap::FetchEmailService, perform: []))
    end

    it 'resolves whatever was open for that inbox' do
      Operations::SignalRecorder.new(source: :email_channel, account: account, subject: channel.inbox)
                                .record(:authentication_failed, severity: :critical)

      run

      expect(Operations::Signal.open_signals.count).to eq(0)
      expect(Operations::Signal.resolved.count).to eq(1)
    end

    it 'records nothing when there was nothing wrong' do
      expect { run }.not_to change(Operations::Signal, :count)
    end
  end
end
