require 'rails_helper'

# Two real connections inserting the same phone number at the same moment (docs/contacts/11-phone-uniqueness.md
# §E5). Separate from `contact_phone_uniqueness_spec.rb` because it cannot run inside a transaction: each thread
# needs its own connection, and a transactional example would hide one thread's row from the other.
RSpec.describe Contact, type: :model do
  describe 'two simultaneous creates with the same phone number' do
    self.use_transactional_tests = false

    let!(:account) { create(:account) }
    let(:number) { '+966551119500' }

    after do
      account.contacts.delete_all
      account.destroy!
    end

    it 'lets exactly one of them win' do
      ready = Concurrent::CountDownLatch.new(2)
      go = Concurrent::CountDownLatch.new(1)

      outcomes = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            contact = described_class.new(account_id: account.id, name: 'Race', phone_number: number)
            ready.count_down
            go.wait(5)
            contact.save ? :saved : :rejected
          rescue ActiveRecord::RecordNotUnique
            :refused
          end
        end
      end

      ready.wait(5)
      go.count_down
      results = outcomes.map(&:value)

      expect(results.count(:saved)).to eq(1)
      # The loser is told either by its own validation, if the winner committed in time for the SELECT to see
      # it, or by the index. Which one is a matter of microseconds; that there is exactly one row is not.
      expect(results - [:saved]).to all(be_in([:rejected, :refused]))
      expect(account.contacts.where(phone_number: number).count).to eq(1)
    end
  end
end
