require 'rails_helper'

RSpec.describe PlatformSupport::TicketQuery do
  let(:account) { create(:account) }
  let(:reporter) { create(:user, account: account, role: :administrator) }
  let(:scope) { PlatformSupport::Ticket.where(account_id: account.id) }

  let!(:billing) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter: reporter, reporter_name: reporter.available_name,
                                    subject: 'Invoice is wrong', category: 'billing', priority: :low,
                                    status: :open, last_activity_at: 3.days.ago)
  end
  let!(:whatsapp) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter: reporter, reporter_name: reporter.available_name,
                                    subject: 'Template stuck in review', category: 'whatsapp', priority: :urgent,
                                    status: :resolved, last_activity_at: 1.hour.ago)
  end

  def call(params = {})
    described_class.new(scope: scope, params: params).call
  end

  it 'orders newest activity first, which is the order the index is built for' do
    expect(call.to_a).to eq([whatsapp, billing])
  end

  it 'filters by status, priority and category' do
    expect(call(status: ['resolved'])).to eq([whatsapp])
    expect(call(priority: ['low'])).to eq([billing])
    expect(call(category: %w[billing whatsapp])).to contain_exactly(billing, whatsapp)
  end

  it 'accepts a comma-separated list as well as an array, because both reach a Rails query string' do
    expect(call(category: 'billing,whatsapp')).to contain_exactly(billing, whatsapp)
  end

  it 'refuses an unknown filter value with a 422 naming the filter and the value' do
    expect { call(status: ['escalated']) }
      .to raise_error(CustomExceptions::PlatformTickets::UnknownFilterValue) { |error|
        expect(error.http_status).to eq(422)
        expect(error.message).to include('status', 'escalated')
      }
  end

  it 'refuses an unknown category and an unknown priority the same way' do
    expect { call(category: ['technical']) }
      .to raise_error(CustomExceptions::PlatformTickets::UnknownFilterValue)
    expect { call(priority: ['critical']) }
      .to raise_error(CustomExceptions::PlatformTickets::UnknownFilterValue)
  end

  it 'never silently drops a filter, because a dropped filter returns a page read as an answer' do
    expect { call(status: %w[open escalated]) }
      .to raise_error(CustomExceptions::PlatformTickets::UnknownFilterValue)
  end

  describe 'search' do
    it 'resolves a pasted reference to that one ticket' do
      expect(call(q: whatsapp.reference)).to eq([whatsapp])
      expect(call(q: whatsapp.reference_number.to_s)).to eq([whatsapp])
    end

    it 'does not fall through to a subject match when the reference misses' do
      expect(call(q: 'LYN-999999')).to be_empty
    end

    it 'matches the subject for anything that is not a reference' do
      expect(call(q: 'template')).to eq([whatsapp])
    end

    it 'treats a wildcard as a literal rather than as a pattern' do
      expect(call(q: '%')).to be_empty
    end
  end

  describe 'paging' do
    it 'defaults to 25 per page' do
      expect(call.limit_value).to eq(described_class::DEFAULT_PER_PAGE)
    end

    it 'accepts a per_page within range' do
      expect(call(per_page: '1').to_a).to eq([whatsapp])
    end

    it 'refuses a per_page that is not a number or is out of range, naming the maximum' do
      [{ per_page: 'all' }, { per_page: '0' }, { per_page: '101' }].each do |params|
        expect { call(params) }.to raise_error(CustomExceptions::PlatformTickets::InvalidLimit)
      end
    end
  end

  # Visibility is the policy scope's single answer; this service receives it already applied and cannot widen it.
  it 'cannot see past the scope it was handed' do
    other_account = create(:account)
    PlatformSupport::Ticket.create!(account: other_account, account_name_at_creation: other_account.name,
                                    reporter_name: 'Somebody', subject: 'Another account')

    expect(call.to_a).to contain_exactly(billing, whatsapp)
  end

  it 'offers no assignee or SLA filter, because the tenant knows about neither' do
    expect(call(assignee_id: 1, sla: 'breached').to_a).to contain_exactly(billing, whatsapp)
  end
end
