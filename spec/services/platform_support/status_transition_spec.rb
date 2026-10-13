require 'rails_helper'

RSpec.describe PlatformSupport::StatusTransition do
  it 'gives the customer exactly one edge: closing a ticket they were told is resolved' do
    expect(described_class::CUSTOMER_ALLOWED).to eq('resolved' => ['closed'])
    expect(described_class.customer_allowed?('resolved', 'closed')).to be(true)
  end

  it 'allows a no-op, so an idempotent client retry does not 422' do
    PlatformSupport::Ticket.statuses.each_key do |status|
      expect(described_class.customer_allowed?(status, status)).to be(true)
    end
  end

  it 'refuses every other edge the customer could ask for' do
    %w[open in_progress waiting_on_customer waiting_on_lynomia].each do |target|
      expect(described_class.customer_allowed?('resolved', target)).to be(false)
    end
    expect(described_class.customer_allowed?('open', 'resolved')).to be(false)
    expect(described_class.customer_allowed?('closed', 'open')).to be(false)
  end

  it 'raises a 422 naming the attempted edge and what would have been allowed' do
    expect { described_class.ensure_customer_allowed!('open', 'resolved') }
      .to raise_error(CustomExceptions::PlatformTickets::InvalidStatusTransition) { |error|
        expect(error.http_status).to eq(422)
        expect(error.message).to include('open', 'resolved')
      }
  end

  it 'does not raise for an allowed edge' do
    expect { described_class.ensure_customer_allowed!('resolved', 'closed') }.not_to raise_error
  end

  it 'lists the customer\'s options from a status, including staying put' do
    expect(described_class.customer_allowed_from('resolved')).to eq(%w[resolved closed])
    expect(described_class.customer_allowed_from('open')).to eq(['open'])
  end
end
