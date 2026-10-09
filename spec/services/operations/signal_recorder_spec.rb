require 'rails_helper'

RSpec.describe Operations::SignalRecorder do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }

  def recorder(source: :email_channel, on: inbox, for_account: account)
    described_class.new(source: source, account: for_account, subject: on)
  end

  describe 'dedup' do
    # The whole reason this table is one row per problem: an inbox polled every minute must not produce 1,440
    # rows a day.
    it 'increments one row rather than inserting a second' do
      recorder.record(:authentication_failed, reason: 'first')
      recorder.record(:authentication_failed, reason: 'second')
      recorder.record(:authentication_failed, reason: 'third')

      expect(Operations::Signal.count).to eq(1)
      signal = Operations::Signal.first
      expect(signal.occurrences).to eq(3)
      expect(signal.reason).to eq('third')
    end

    it 'keeps different subjects, signals, sources and accounts apart' do
      recorder.record(:authentication_failed)
      recorder(on: other_inbox).record(:authentication_failed)
      recorder.record(:connection_failed)
      recorder(source: :channel).record(:authentication_failed)
      described_class.new(source: :email_channel, account: other_account,
                          subject: create(:inbox, account: other_account)).record(:authentication_failed)

      expect(Operations::Signal.count).to eq(5)
    end

    it 'starts a new row once the previous one is resolved' do
      recorder.record(:authentication_failed)
      recorder.resolve_all

      recorder.record(:authentication_failed)

      expect(Operations::Signal.count).to eq(2)
      expect(Operations::Signal.open_signals.count).to eq(1)
    end

    # A unique index that treats NULLs as distinct would let two installation-wide rows through, which is where
    # dedup matters most.
    it 'dedups an installation-wide signal that has no account and no subject' do
      queue = described_class.new(source: :queue)
      queue.record(:no_workers)
      queue.record(:no_workers)

      expect(Operations::Signal.count).to eq(1)
      expect(Operations::Signal.first.occurrences).to eq(2)
    end
  end

  describe 'severity' do
    it 'only ever rises while a signal is open' do
      recorder.record(:connection_failed, severity: :critical)
      recorder.record(:connection_failed, severity: :info)

      expect(Operations::Signal.first.severity).to eq('critical')
    end
  end

  describe 'resolution' do
    it 'clears every open signal for the subject, not just one' do
      recorder.record(:authentication_failed)
      recorder.record(:connection_failed)
      recorder(on: other_inbox).record(:authentication_failed)

      recorder.resolve_all

      expect(Operations::Signal.open_signals.count).to eq(1)
      expect(Operations::Signal.open_signals.first.subject_id).to eq(other_inbox.id)
    end

    it 'clears one named signal when asked' do
      recorder.record(:authentication_failed)
      recorder.record(:connection_failed)

      recorder.resolve(:authentication_failed)

      expect(Operations::Signal.open_signals.pluck(:signal)).to eq(['connection_failed'])
    end

    # A problem that stopped being reported is not a problem that was fixed.
    it 'never resolves anything on its own' do
      recorder.record(:authentication_failed, at: 3.years.ago)

      expect(Operations::Signal.open_signals.count).to eq(1)
    end
  end

  describe 'sanitization' do
    it 'drops any detail key that is not on the allow-list' do
      recorder.record(:authentication_failed,
                      detail: { code: 'Net::IMAP::NoResponseError', imap_password: 'hunter2',
                                provider_config: { 'api_key' => 'secret' }, access_token: 'tok' })

      detail = Operations::Signal.first.detail
      expect(detail).to eq('code' => 'Net::IMAP::NoResponseError')
    end

    it 'drops a detail value that is not a scalar, and one that carries whitespace' do
      recorder.record(:authentication_failed,
                      detail: { code: { nested: true }, provider: 'a value with spaces', size: 7, queue: :default })

      expect(Operations::Signal.first.detail).to eq('size' => 7, 'queue' => 'default')
    end

    it "takes the subject's own credentials out of the reason, by value" do
      channel = create(:channel_email, :imap_email, account: account)
      channel.update!(imap_password: 'hunter2-not-in-a-row')

      signal = described_class.new(source: :email_channel, account: account, subject: channel.inbox)
                              .record(:authentication_failed,
                                      reason: 'LOGIN failed for care@example.com with hunter2-not-in-a-row')

      expect(signal.reason).to eq('LOGIN failed for care@example.com with [redacted]')
    end

    it 'takes a credential written inline in prose out of the reason, by shape' do
      signal = described_class.new(source: :webhook, account: account)
                              .record(:delivery_failed,
                                      reason: 'POST https://bot:s3cr3t@hooks.example.com/x failed; ' \
                                              'api_key=AKIAIOSFODNN7EXAMPLE token: abc.def.ghi')

      expect(signal.reason).to eq('POST https://[redacted]@hooks.example.com/x failed; ' \
                                  'api_key=[redacted] token: [redacted]')
    end

    it 'leaves the identifiers an operator needs alone' do
      signal = described_class.new(source: :whatsapp_channel, account: account)
                              .record(:delivery_failed,
                                      reason: 'Meta returned 131049 for wamid.HBgMOTY1NTAwMTEyMjMzFQIAERgSN0Y')

      expect(signal.reason).to eq('Meta returned 131049 for wamid.HBgMOTY1NTAwMTEyMjMzFQIAERgSN0Y')
    end

    it 'collapses and bounds the reason so provider prose cannot fill the column' do
      recorder.record(:authentication_failed, reason: "line one\n\n  line two   \ttail")
      expect(Operations::Signal.first.reason).to eq('line one line two tail')

      recorder.resolve_all
      recorder.record(:authentication_failed, reason: 'x' * 900)
      expect(Operations::Signal.open_signals.first.reason.length).to eq(described_class::MAX_REASON)
    end
  end

  describe 'never raising into its caller' do
    # These writers sit inside the jobs that fetch email for every account.
    it 'returns nil and logs rather than raising when the write fails' do
      allow(Operations::Signal).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'boom')
      allow(Rails.logger).to receive(:error)

      expect(recorder.record(:authentication_failed)).to be_nil
      expect(Rails.logger).to have_received(:error).with(/could not record email_channel/)
    end

    it 'returns zero and logs rather than raising when the resolve fails' do
      allow(Operations::Signal).to receive(:open_signals).and_raise(ActiveRecord::StatementInvalid, 'boom')
      allow(Rails.logger).to receive(:error)

      expect(recorder.resolve_all).to eq(0)
    end

    it 'refuses a signal name outside the allow-list without raising' do
      allow(Rails.logger).to receive(:error)

      expect(recorder.record(:everything_is_on_fire)).to be_nil
      expect(Operations::Signal.count).to eq(0)
    end
  end
end
