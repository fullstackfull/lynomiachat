require 'rails_helper'

RSpec.describe PlatformSupport::Ticket do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:reporter) { create(:user, account: account, role: :administrator) }
  let(:ticket) do
    described_class.create!(account: account, account_name_at_creation: account.name,
                            reporter: reporter, reporter_name: reporter.available_name,
                            subject: 'WhatsApp template stuck in review', category: 'whatsapp')
  end

  describe 'the frozen vocabularies' do
    it 'numbers the six statuses so the partial indexes can use status < 4' do
      expect(described_class.statuses).to eq(
        'open' => 0, 'in_progress' => 1, 'waiting_on_customer' => 2,
        'waiting_on_lynomia' => 3, 'resolved' => 4, 'closed' => 5
      )
    end

    it 'groups the statuses into open and closed with nothing left over' do
      expect(described_class::OPEN_STATUSES + described_class::CLOSED_STATUSES)
        .to match_array(described_class.statuses.keys)
    end

    it 'pauses the SLA clock for waiting_on_customer only, because waiting on ourselves is our own delay' do
      expect(described_class::SLA_PAUSING_STATUSES).to eq(%w[waiting_on_customer])
    end

    it 'uses the same four priorities, in the same order, as a conversation' do
      expect(described_class.priorities).to eq('low' => 0, 'medium' => 1, 'high' => 2, 'urgent' => 3)
    end

    it 'holds the approved eleven categories with other as the default' do
      expect(described_class::CATEGORIES).to eq(
        %w[billing account_access channel_connection whatsapp commerce campaigns automation
           performance data_export bug other]
      )
      expect(described_class.new.category).to eq('other')
    end

    it 'refuses a category outside the list rather than coercing it' do
      ticket.category = 'technical'
      expect(ticket).not_to be_valid
      expect(ticket.errors[:category]).to be_present
    end
  end

  describe 'the reference' do
    it 'renders the prefix and the padding from the bare column' do
      expect(ticket.reference).to eq("LYN-#{ticket.reference_number.to_s.rjust(6, '0')}")
      expect(ticket.reference).to start_with('LYN-')
    end

    it 'is globally sequential, not per account' do
      first = ticket
      second = described_class.create!(account: other_account, account_name_at_creation: other_account.name,
                                       reporter_name: 'Somebody else', subject: 'Different account')

      expect(second.reference_number).to eq(first.reference_number + 1)
    end

    it 'accepts either form when parsing, because a customer pastes LYN-000123 from an email' do
      expect(described_class.reference_number_from('LYN-000123')).to eq(123)
      expect(described_class.reference_number_from('123')).to eq(123)
      expect(described_class.reference_number_from('nonsense')).to be_nil
    end
  end

  describe 'what the subject account means' do
    it 'requires an account on create, so a live ticket always has a subject' do
      orphan = described_class.new(account_name_at_creation: 'Somebody', reporter_name: 'Someone',
                                   subject: 'No account')
      expect(orphan).not_to be_valid
      expect(orphan.errors[:account_id]).to be_present
    end

    it 'orphans rather than erases when the account is deleted, and keeps the name snapshot' do
      ticket
      Account.where(id: account.id).delete_all

      expect(ticket.reload).to have_attributes(account_id: nil, account_name_at_creation: account.name)
    end

    it 'falls out of a tenant scope once orphaned, with no rule needed to exclude it' do
      ticket
      Account.where(id: account.id).delete_all

      expect(described_class.where(account_id: account.id)).to be_empty
    end

    it 'refuses a reporter who is not a member of the subject account' do
      outsider = create(:user, account: other_account, role: :administrator)
      cross = described_class.new(account: account, account_name_at_creation: account.name,
                                  reporter: outsider, reporter_name: outsider.available_name,
                                  subject: 'Cross tenant')

      expect(cross).not_to be_valid
      expect(cross.errors[:reporter]).to be_present
    end

    # A ticket outlives the membership that opened it by design, so re-checking on every save would make an
    # operator's reply fail on a ticket whose reporter has since left.
    it 'still saves after the reporter leaves the account' do
      ticket
      AccountUser.where(account_id: account.id, user_id: reporter.id).delete_all

      expect { ticket.update!(last_activity_at: Time.current) }.not_to raise_error
    end
  end

  describe 'the derived unread flag' do
    it 'is false with no operator message' do
      expect(ticket).not_to be_unread
    end

    it 'is true when an operator replied and the customer has not looked since' do
      ticket.update!(last_operator_message_at: Time.current)
      expect(ticket.reload).to be_unread
      expect(described_class.unread).to include(ticket)
    end

    it 'is false once the customer has viewed the ticket after the reply' do
      ticket.update!(last_operator_message_at: 1.hour.ago, customer_last_viewed_at: Time.current)
      expect(ticket.reload).not_to be_unread
      expect(described_class.unread).not_to include(ticket)
    end

    it 'is true again when a newer operator message arrives after the last view' do
      ticket.update!(customer_last_viewed_at: 1.hour.ago, last_operator_message_at: Time.current)
      expect(ticket.reload).to be_unread
    end
  end

  describe 'lengths' do
    it 'caps the subject at 255 and the description at 10 000' do
      ticket.subject = 'a' * 256
      ticket.description = 'b' * 10_001
      expect(ticket).not_to be_valid
      expect(ticket.errors.attribute_names).to include(:subject, :description)
    end
  end

  it 'does not declare the audited macro, because the gem would attribute operator actions wrongly' do
    expect(described_class.respond_to?(:audited_options)).to be(false)
  end
end
