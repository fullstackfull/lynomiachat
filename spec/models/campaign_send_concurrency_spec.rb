require 'rails_helper'

# TWO WORKERS, ONE CAMPAIGN. The properties a send ceiling and a send ledger are worthless
# without.
#
# The scheduler selects due campaigns every five minutes and enqueues one job each. A job that
# is retried, a worker that was killed mid-run and restarted, and two schedulers overlapping
# during a deploy all produce the same shape: two processes holding the same campaign row at
# the same moment. Nothing in a single-threaded spec can tell whether the protection against
# that is a real row lock or a check that happens to run first.
#
# So this file opts out of transactional fixtures -- under them both threads share one
# connection inside one transaction and cannot contend for a lock at all -- takes a connection
# per thread, and removes what it commits.
RSpec.describe 'concurrent campaign sending', type: :model do
  self.use_transactional_tests = false

  let(:account) { Account.create!(name: "send-concurrency-#{SecureRandom.hex(4)}") }
  let(:inbox) do
    Inbox.create!(account: account, name: 'send-concurrency',
                  channel: Channel::Sms.create!(account: account, phone_number: "+1555#{rand(1_000_000..9_999_999)}",
                                                provider_config: { 'api_key' => 'k' }))
  end
  let(:campaign) do
    Campaign.create!(account: account, inbox: inbox, title: 'c', message: 'hello', campaign_type: :one_off,
                     scheduled_at: 1.hour.ago)
  end

  # Nothing here is rolled back, so this file has to remove what it commits -- and a leak in a
  # non-transactional file is not its own problem, it is every later file's.
  after do
    CampaignRecipient.where(account_id: account.id).delete_all
    Campaign.where(account_id: account.id).delete_all
    Contact.where(account_id: account.id).delete_all
    WorkingHour.where(account_id: account.id).delete_all
    Inbox.where(account_id: account.id).delete_all
    Channel::Sms.where(account_id: account.id).delete_all
    Custom::AuditLog.where(associated_type: 'Account', associated_id: account.id).delete_all
    Account.where(id: account.id).delete_all
    Redis::Alfred.delete(Campaigns::Throttle.key(account))

    leaked = tables_still_referencing(account.id)
    raise "campaign_send_concurrency_spec left rows behind: #{leaked.join(', ')}" if leaked.any?
  end

  def tables_still_referencing(account_id)
    connection = ActiveRecord::Base.connection
    connection.tables.filter_map do |table|
      next unless connection.columns(table).any? { |column| column.name == 'account_id' }

      count = connection.select_value(
        "SELECT COUNT(*) FROM #{connection.quote_table_name(table)} WHERE account_id = #{connection.quote(account_id)}"
      )
      "#{table} (#{count})" if count.positive?
    end
  end

  # Each thread loads its own instance, because an ActiveRecord object is not safe to share
  # between threads -- which is also true of the two Sidekiq workers this stands in for.
  def trigger_concurrently(campaign_id, threads: 4)
    Array.new(threads) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Campaign.find(campaign_id).trigger!
        end
      end
    end.each(&:join)
  end

  # THE DOUBLE-SEND PROPERTY. `mark_processing!` flips the status under `with_lock`, so the
  # losers find it already `processing` and return without executing. Without the lock all four
  # would read `active`, all four would consider themselves the first, and the audience would
  # be messaged four times.
  it 'executes the send exactly once when four workers pick up the same campaign' do
    campaign
    runs = Concurrent::AtomicFixnum.new(0)
    allow(Sms::OneoffSmsCampaignService).to receive(:new) do
      runs.increment
      instance_double(Sms::OneoffSmsCampaignService, perform: nil)
    end

    trigger_concurrently(campaign.id)

    expect(runs.value).to eq(1)
  end

  # THE LEDGER'S OWN GUARANTEE, independent of the lock above. Even if two workers somehow both
  # reached the loop, the unique index on (campaign_id, contact_id) means one recipient cannot
  # acquire two outcome rows -- so a double send could never be recorded as two, and the
  # analytics denominator stays the audience.
  it 'refuses a second outcome row for the same recipient' do
    contact = Contact.create!(account: account, name: 'shopper')
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: contact, status: :sent)

    expect do
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: contact, status: :sent)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  # THE CEILING UNDER CONTENTION. The count is INCR's own return value rather than a separate
  # read, so eight concurrent claims take eight distinct slots. A read-then-write would let
  # several threads read the same number, each decide there was room, and overshoot by exactly
  # the number of workers -- the failure mode that makes a ceiling decorative under the only
  # conditions it is needed.
  #
  # Time is frozen because the window IS the key: eight claims that straddled a second
  # boundary would legitimately produce two runs of slot numbers and the assertion would be
  # about the clock rather than about atomicity.
  it 'hands out one slot per claim when eight threads claim at once' do
    travel_to(Time.zone.at(1_760_961_600)) do
      Redis::Alfred.delete(Campaigns::Throttle.key(account))

      claimed = Array.new(8) { Thread.new { Campaigns::Throttle.claim(account) } }.map(&:value)

      expect(claimed.sort).to eq((1..8).to_a)
    end
  end
end
