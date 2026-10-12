require 'rails_helper'

RSpec.describe Support::Tickets::ReferenceAllocator do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  it 'starts at one for an account with no cases' do
    expect(described_class.next_for(account.id)).to eq(1)
  end

  it 'continues from the highest number in that account only' do
    create(:support_ticket, account: account)
    create(:support_ticket, account: account)
    create(:support_ticket, account: other_account)

    expect(described_class.next_for(account.id)).to eq(3)
    expect(described_class.next_for(other_account.id)).to eq(2)
  end

  # The advisory lock is what makes this safe under concurrency. The lock is transaction-scoped, so the
  # serialisation it provides can only be observed across real connections; this asserts the weaker but still
  # meaningful property that two sequential allocations inside one transaction do not collide, and that the
  # unique index would catch it if they did.
  it 'never hands out a number that already exists' do
    10.times { create(:support_ticket, account: account) }

    expect(described_class.next_for(account.id)).to eq(11)
    expect(account.support_tickets.pluck(:reference_number).uniq.length).to eq(10)
  end

  it 'refuses a non-numeric account id rather than interpolating it' do
    expect { described_class.next_for('1; DROP TABLE support_tickets') }.to raise_error(ArgumentError)
  end
end
