require 'rails_helper'

# The operator notification, rendered rather than merely enqueued.
#
# The request spec proves a job is queued; this proves the message a configured installation would actually
# send -- recipient, reply-to, and that the template renders inside the shared mailer layout with the
# visitor's fields in it. A mailer that enqueues and then raises on render is a lead silently lost in a
# retrying job, which is exactly the failure an enqueue-only assertion misses.
describe Marketing::QuoteMailer do
  let(:quote) do
    SiteQuoteRequest.create!(name: 'Noura Al-Sabah', email: 'noura@example.com', company: 'Example Co',
                             phone: '+96555555555', team_size: '4-10', channels: %w[whatsapp email],
                             locale: 'ar', message: 'We sell online and need WhatsApp.')
  end

  context 'when a notification address is configured' do
    before do
      InstallationConfig.find_or_initialize_by(name: 'MARKETING_QUOTE_NOTIFICATION_EMAIL')
                        .update!(value: 'sales@example.com')
      GlobalConfig.clear_cache
    end

    it 'addresses the configured operator and replies to the visitor' do
      mail = described_class.new_request(quote)

      expect(mail.to).to eq(['sales@example.com'])
      expect(mail.reply_to).to eq(['noura@example.com'])
    end

    # The id is enough to find the row, and a subject line is logged and forwarded where a body is not.
    it 'keeps the visitor name out of the subject' do
      mail = described_class.new_request(quote)

      expect(mail.subject).to eq("New quote request ##{quote.id} from the website")
      expect(mail.subject).not_to include('Noura')
    end

    it 'renders the request the operator has to answer' do
      body = described_class.new_request(quote).body.encoded

      expect(body).to include('Noura Al-Sabah')
      expect(body).to include('noura@example.com')
      expect(body).to include('Example Co')
      expect(body).to include('whatsapp, email')
      expect(body).to include('We sell online and need WhatsApp.')
      expect(body).not_to include('translation missing')
    end

    it 'renders an empty optional field as a dash rather than blank' do
      bare = SiteQuoteRequest.create!(name: 'A', email: 'a@example.com', locale: 'en')

      expect(described_class.new_request(bare).body.encoded).to include('-')
    end
  end

  # Returning without calling `mail` yields a NullMail, so `deliver_later` on it is a no-op: nothing is
  # queued and no recipient is invented. The row is still saved and listed in Super Admin.
  context 'when no notification address is configured' do
    before do
      InstallationConfig.find_by(name: 'MARKETING_QUOTE_NOTIFICATION_EMAIL')&.destroy
      GlobalConfig.clear_cache
    end

    it 'sends nothing at all' do
      expect(described_class.new_request(quote).message).to be_a(ActionMailer::Base::NullMail)
    end

    it 'queues nothing when delivered' do
      expect { described_class.new_request(quote).deliver_now }.not_to change(ActionMailer::Base.deliveries, :size)
    end
  end
end
