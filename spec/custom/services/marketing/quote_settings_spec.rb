require 'rails_helper'

# The one editable sales setting, and the rules the owner set for it: it saves, it changes, it clears, it
# refuses malformed input, it stays empty by default, it is audited, and a change is live with no restart.
describe Marketing::QuoteSettings do
  let(:actor) { create(:super_admin) }

  # GlobalConfig keeps the value in Redis, which a rolled-back test transaction does not undo -- so without
  # this one example's address would be served to the next one's reads from the cache.
  before { GlobalConfig.clear_cache }

  after { GlobalConfig.clear_cache }

  # Nothing in this module or in Marketing::QuoteNotification carries a built-in address, so a fresh
  # installation has none -- the owner's requirement, asserted rather than assumed.
  describe 'the default' do
    it 'is empty, and sends nothing' do
      expect(described_class.address).to be_nil
      expect(described_class).not_to be_configured
      expect(described_class.status).to eq(:unconfigured)
    end
  end

  describe '.update' do
    it 'saves an address' do
      result = described_class.update('sales@example.com', actor: actor)

      expect(result).to be_ok
      expect(result.message).to eq(:saved)
      expect(described_class.address).to eq('sales@example.com')
      expect(InstallationConfig.find_by(name: described_class::KEY).value).to eq('sales@example.com')
    end

    it 'replaces an address that is already stored' do
      described_class.update('first@example.com', actor: actor)

      described_class.update('second@example.com', actor: actor)

      expect(described_class.address).to eq('second@example.com')
      expect(InstallationConfig.where(name: described_class::KEY).count).to eq(1)
    end

    it 'strips surrounding whitespace rather than storing it' do
      described_class.update("  sales@example.com\n", actor: actor)

      expect(described_class.address).to eq('sales@example.com')
    end

    # Blank is a real value meaning "send nothing": the row stays so the key remains visible, and
    # `configured?` answers false, which is what turns the mailer into a no-op.
    it 'clears the address without deleting the key' do
      described_class.update('sales@example.com', actor: actor)

      result = described_class.update('', actor: actor)

      expect(result).to be_ok
      expect(result.message).to eq(:cleared)
      expect(described_class.address).to be_nil
      expect(described_class).not_to be_configured
      expect(InstallationConfig.exists?(name: described_class::KEY)).to be(true)
    end

    it 'reports that nothing changed when the same address is submitted again' do
      described_class.update('sales@example.com', actor: actor)

      expect(described_class.update('sales@example.com', actor: actor).message).to eq(:unchanged)
    end

    context 'with input the application would not accept the other way round' do
      it 'refuses a malformed address and leaves the stored one alone' do
        described_class.update('sales@example.com', actor: actor)

        result = described_class.update('not-an-address', actor: actor)

        expect(result).not_to be_ok
        expect(result.message).to eq(:invalid)
        expect(described_class.address).to eq('sales@example.com')
      end

      it 'refuses a comma separated list, because one address is the contract' do
        result = described_class.update('a@example.com, b@example.com', actor: actor)

        expect(result.message).to eq(:invalid)
        expect(described_class.address).to be_nil
      end

      it 'refuses an address longer than the cap' do
        result = described_class.update("#{'a' * 180}@example.com", actor: actor)

        expect(result.message).to eq(:too_long)
        expect(described_class.address).to be_nil
      end
    end

    # The audit entry names the address it moved FROM and TO. `AuditTrail::Secrets` scrubs by key name and
    # does not match `value`, so the entry survives the write with its content intact.
    describe 'the audit trail' do
      it 'records who changed it and what it moved to' do
        expect { described_class.update('sales@example.com', actor: actor) }
          .to change { Custom::AuditLog.where(comment: described_class::AUDIT_EVENT).count }.by(1)

        entry = Custom::AuditLog.where(comment: described_class::AUDIT_EVENT).last
        expect(entry.user_id).to eq(actor.id)
        expect(entry.audited_changes['value']).to eq([nil, 'sales@example.com'])
      end

      it 'records a clear as a change to nothing' do
        described_class.update('sales@example.com', actor: actor)

        described_class.update('', actor: actor)

        expect(Custom::AuditLog.where(comment: described_class::AUDIT_EVENT).last.audited_changes['value'])
          .to eq(['sales@example.com', nil])
      end

      it 'records nothing for a refusal' do
        expect { described_class.update('not-an-address', actor: actor) }
          .not_to change(Custom::AuditLog, :count)
      end

      # The setting is already saved by then; a failed audit must not report the save as failed.
      it 'still reports success when the audit cannot be written' do
        allow(Custom::AuditLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'nope')

        expect(described_class.update('sales@example.com', actor: actor)).to be_ok
        expect(described_class.address).to eq('sales@example.com')
      end
    end

    # The owner's requirement that a new address apply without restarting Rails or redeploying. The mechanism
    # is InstallationConfig's `after_commit :clear_cache`, which evicts the Redis copy GlobalConfig serves --
    # so the next read through the mailer's own accessor sees the new value with nothing restarted.
    it 'is live for the mailer immediately, with no restart' do
      described_class.update('first@example.com', actor: actor)
      expect(Marketing::QuoteNotification.address).to eq('first@example.com')

      described_class.update('second@example.com', actor: actor)

      expect(Marketing::QuoteNotification.address).to eq('second@example.com')
    end
  end

  describe '.status' do
    let(:quote) { SiteQuoteRequest.create!(name: 'Noura', email: 'noura@example.com', locale: 'en') }

    before { described_class.update('sales@example.com', actor: actor) }

    # The owner's rule: no permanent success state merely because an address exists.
    it 'is :configured, and reports no delivery, before anything has been sent' do
      expect(described_class.status).to eq(:configured)
      expect(described_class.last_delivery).to be_nil
    end

    it 'is :failing when the most recent attempt failed' do
      quote.update_columns(notification_attempted_at: Time.current, notification_error: 'Net::SMTPError: nope')  # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.status).to eq(:failing)
      expect(described_class.last_failure).to eq(quote)
    end

    it 'is :configured again once a later attempt succeeds' do
      quote.update_columns(notification_attempted_at: 1.hour.ago, notification_error: 'Net::SMTPError: nope')  # rubocop:disable Rails/SkipsModelValidations
      later = SiteQuoteRequest.create!(name: 'B', email: 'b@example.com', locale: 'en')
      later.update_columns(notification_attempted_at: Time.current, notification_error: nil)  # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.status).to eq(:configured)
      expect(described_class.last_delivery).to eq(later)
      expect(described_class.last_failure).to eq(quote)
    end

    it 'is :unconfigured whatever the delivery history says, once the address is cleared' do
      quote.update_columns(notification_attempted_at: Time.current, notification_error: 'Net::SMTPError: nope')  # rubocop:disable Rails/SkipsModelValidations

      described_class.update('', actor: actor)

      expect(described_class.status).to eq(:unconfigured)
    end
  end

  describe '.send_test' do
    it 'refuses to send when there is no address, rather than inventing one' do
      result = described_class.send_test(actor: actor)

      expect(result).not_to be_ok
      expect(result.message).to eq(:not_configured)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'sends one message to the configured address and reports it' do
      described_class.update('sales@example.com', actor: actor)

      result = nil
      expect { result = described_class.send_test(actor: actor) }
        .to change(ActionMailer::Base.deliveries, :size).by(1)

      expect(result).to be_ok
      expect(result.message).to eq(:test_sent)
      expect(ActionMailer::Base.deliveries.last.to).to eq(['sales@example.com'])
    end

    # The answer an operator needs is what the mail server said, so a failure is reported rather than raised
    # into a 500 and rather than being reported as a success.
    it 'reports the failure when the mail server refuses it' do
      described_class.update('sales@example.com', actor: actor)
      delivery = instance_double(ActionMailer::MessageDelivery)
      allow(delivery).to receive(:deliver_now).and_raise(Net::SMTPAuthenticationError, 'bad credentials')
      allow(Marketing::QuoteMailer).to receive(:test_notification).and_return(delivery)

      result = described_class.send_test(actor: actor)

      expect(result).not_to be_ok
      expect(result.message).to eq(:test_failed)
      expect(result.detail).to include('Net::SMTPAuthenticationError')
    end
  end
end
