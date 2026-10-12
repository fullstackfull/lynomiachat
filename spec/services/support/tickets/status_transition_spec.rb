require 'rails_helper'

RSpec.describe Support::Tickets::StatusTransition do
  describe '.allowed?' do
    it 'lets any active state reach any other active state' do
      Support::Ticket::ACTIVE_STATUSES.each do |from|
        Support::Ticket::ACTIVE_STATUSES.each do |to|
          expect(described_class.allowed?(from, to)).to be(true), "#{from} -> #{to} should be allowed"
        end
      end
    end

    it 'lets any active state reach either terminal state' do
      expect(described_class.allowed?('open', 'resolved')).to be(true)
      expect(described_class.allowed?('waiting_on_customer', 'closed')).to be(true)
    end

    it 'lets a resolved case be closed or reopened' do
      expect(described_class.allowed?('resolved', 'closed')).to be(true)
      expect(described_class.allowed?('resolved', 'open')).to be(true)
    end

    it 'lets a closed case only reopen' do
      expect(described_class.allowed?('closed', 'open')).to be(true)
      expect(described_class.allowed?('closed', 'resolved')).to be(false)
      expect(described_class.allowed?('closed', 'in_progress')).to be(false)
    end

    # An idempotent client retry must not 422.
    it 'treats a no-op as allowed' do
      Support::Ticket.statuses.each_key { |state| expect(described_class.allowed?(state, state)).to be(true) }
    end
  end

  describe '.ensure!' do
    it 'raises with the attempted edge and the allowed set' do
      expect { described_class.ensure!('closed', 'resolved') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Tickets::InvalidStatusTransition') })
    end

    it 'says nothing when the edge is allowed' do
      expect { described_class.ensure!('open', 'resolved') }.not_to raise_error
    end
  end
end
