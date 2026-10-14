require 'rails_helper'

# The notification, and the owner's rule that a delivery problem must never cost a stored lead.
describe Marketing::QuoteNotificationJob do
  let(:quote) do
    SiteQuoteRequest.create!(name: 'Noura', email: 'noura@example.com', locale: 'en',
                             message: 'We sell online.')
  end

  # GlobalConfig keeps the value in Redis, which a rolled-back test transaction does not undo.
  before { GlobalConfig.clear_cache }

  after { GlobalConfig.clear_cache }

  def configure(address)
    InstallationConfig.find_or_initialize_by(name: Marketing::QuoteNotification::KEY).update!(value: address)
    GlobalConfig.clear_cache
  end

  context 'when an address is configured' do
    before { configure('sales@example.com') }

    it 'delivers to the configured recipient and records the outcome' do
      expect { described_class.perform_now(quote.id) }
        .to change(ActionMailer::Base.deliveries, :size).by(1)

      expect(ActionMailer::Base.deliveries.last.to).to eq(['sales@example.com'])
      expect(quote.reload.notification_attempted_at).to be_present
      expect(quote.notification_error).to be_nil
      expect(quote).to be_notification_delivered
    end

    # The lead is the record. A relay that refuses the message must leave the row readable, answerable and
    # intact -- and leave behind the one thing an operator needs: what went wrong.
    it 'records the failure and keeps the request' do
      allow(Marketing::QuoteMailer).to receive(:new_request).and_raise(Net::SMTPAuthenticationError, 'nope')
      quote_id = quote.id

      expect { described_class.perform_now(quote_id) }.not_to change(SiteQuoteRequest, :count)

      expect(quote.reload.notification_error).to include('Net::SMTPAuthenticationError')
      expect(quote.notification_attempted_at).to be_present
      expect(quote).to be_notification_failed
      expect(quote.name).to eq('Noura')
      expect(quote.status).to eq('new_request')
    end

    it 'does not raise on a failure, so the queue is not left retrying a message that may have arrived' do
      allow(Marketing::QuoteMailer).to receive(:new_request).and_raise(Errno::ECONNREFUSED)

      expect { described_class.perform_now(quote.id) }.not_to raise_error
    end

    it 'truncates a long error rather than refusing to record it' do
      allow(Marketing::QuoteMailer).to receive(:new_request).and_raise(StandardError, 'x' * 500)

      described_class.perform_now(quote.id)

      expect(quote.reload.notification_error.length).to be <= 250
    end

    # `update_columns` is deliberate: a row whose validations have since tightened still gets its delivery
    # recorded, because what is being written is the installation's own account of what happened.
    it 'records the outcome on a row that would no longer validate' do
      quote.update_columns(email: 'not-an-address')  # rubocop:disable Rails/SkipsModelValidations

      described_class.perform_now(quote.id)

      expect(quote.reload.notification_attempted_at).to be_present
    end
  end

  context 'when no address is configured' do
    before do
      InstallationConfig.find_by(name: Marketing::QuoteNotification::KEY)&.destroy
      GlobalConfig.clear_cache
    end

    # Not a failure state: nothing was attempted, so nothing is recorded and the screens that matter say so.
    it 'sends nothing and records nothing' do
      expect { described_class.perform_now(quote.id) }.not_to change(ActionMailer::Base.deliveries, :size)

      expect(quote.reload.notification_attempted_at).to be_nil
      expect(quote.notification_error).to be_nil
    end
  end

  # A request an operator deleted between the submission and the job running.
  it 'does nothing for a row that no longer exists' do
    configure('sales@example.com')
    id = quote.id
    quote.destroy!

    expect { described_class.perform_now(id) }.not_to raise_error
  end
end
