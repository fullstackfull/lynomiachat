require 'rails_helper'

# D-12: two reports for one recipient, processed at the same moment, must resolve deterministically.
#
# This is the one scenario the rest of the suite cannot express. Transactional fixtures put every example on a
# single connection inside a single transaction, where two threads cannot contend for a row lock at all: the
# second would either see the first's uncommitted write or block for ever. So this file opts out of them, uses a
# connection per thread, and removes what it commits.
#
# What it proves is that the outcome is decided by the forward-only rule rather than by commit order. Without
# `with_lock` in CampaignRecipient#record_outcome! both threads would read `sent`, both would consider their own
# report an advance, and whichever committed last would win -- so a `delivered` report landing a millisecond
# after a `read` report would demote the recipient, and the campaign's read count would lose it.
RSpec.describe CampaignRecipient, type: :model do
  self.use_transactional_tests = false

  let(:reported_at) { Time.zone.at(1_760_000_000) }

  # One committed account graph per example, shared by every round in it. A round then costs a contact and a
  # recipient rather than a whole account, and there is one graph to take down at the end instead of twenty.
  let(:account) { Account.create!(name: "concurrency-#{SecureRandom.hex(4)}") }
  let(:inbox) do
    Inbox.create!(account: account, name: 'concurrency',
                  channel: Channel::WebWidget.create!(account: account, website_url: 'https://concurrency.example'))
  end
  let(:campaign) do
    Campaign.create!(account: account, inbox: inbox, title: 'c', message: 'c', campaign_type: :one_off,
                     scheduled_at: 1.hour.ago)
  end

  # Nothing here is rolled back, so this file has to remove what it commits -- and a leak in a non-transactional
  # file is not its own problem, it is every later file's. `WorkingHour.today` is not scoped to an inbox and
  # several specs assert on `Contact.count`, so rows left behind here fail files that never heard of campaigns.
  #
  # Deleted directly, children first, and with `delete_all`: a teardown removes rows, it does not exercise
  # cascade behaviour. `Account`'s own cascade is `dependent: :destroy_async`, which deletes the account first
  # and leaves the children to a job -- and `Contact`'s destroy callbacks read `contact.account`, which by then
  # is gone. Running product callbacks is not a teardown's business anyway.
  #
  # The audit rows the inbox's create writes are deliberately outside any cascade: `audits` carries no foreign
  # key to `accounts`, because a trail has to outlive what it describes. This file removes its own, since it is
  # not here to test the trail.
  #
  # Then the guard that would have caught this file leaking in the first place: every table that has an
  # `account_id` is asked whether anything still points at the account this example made. It names the table
  # rather than reporting a count that drifted, and it needs nothing carried between hooks.
  after do
    described_class.where(account_id: account.id).delete_all
    Contact.where(account_id: account.id).delete_all
    Campaign.where(account_id: account.id).delete_all
    WorkingHour.where(account_id: account.id).delete_all
    Inbox.where(account_id: account.id).delete_all
    Channel::WebWidget.where(account_id: account.id).delete_all
    Custom::AuditLog.where(associated_type: 'Account', associated_id: account.id).delete_all
    Account.where(id: account.id).delete_all

    leaked = tables_still_referencing(account.id)
    raise "campaign_recipient_concurrency_spec left rows behind: #{leaked.join(', ')}" if leaked.any?
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

  # Named after this file, so that a row which somehow still outlives it says where it came from.
  def build_recipient
    described_class.create!(
      account: account, campaign: campaign, inbox: inbox, status: :sent, sent_at: reported_at,
      contact: Contact.create!(account: account, name: "concurrency-#{SecureRandom.hex(4)}"),
      source_id: "wamid.concurrency-#{SecureRandom.hex(4)}"
    )
  end

  # Both reports are applied through freshly loaded instances, because an ActiveRecord object is not safe to
  # share between threads -- which is also true of the two webhook workers this is standing in for.
  def apply_concurrently(recipient_id, first, second)
    [first, second].map do |state|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.find(recipient_id).record_outcome!(state, reported_at: reported_at)
        end
      end
    end.each(&:join)
  end

  # Ten rounds in each order. One round can pass by luck; a demotion that only happens when the threads
  # interleave a particular way would show up across twenty.
  it 'ends at the furthest state reported, in either order, every time' do
    outcomes = []

    10.times do
      recipient = build_recipient
      apply_concurrently(recipient.id, 'delivered', 'read')
      outcomes << recipient.reload.attributes.values_at('status', 'delivered_at', 'read_at')
    end
    10.times do
      recipient = build_recipient
      apply_concurrently(recipient.id, 'read', 'delivered')
      outcomes << recipient.reload.attributes.values_at('status', 'delivered_at', 'read_at')
    end

    expect(outcomes.map(&:first).uniq).to eq(['read'])
    # Both timestamps are set whichever thread won the lock first: each report stamps its own event even when it
    # does not move the state, which is what lets P8 count a read-before-delivered recipient as delivered.
    expect(outcomes).to all(satisfy { |(_status, delivered_at, read_at)| delivered_at.present? && read_at.present? })
  end

  # A delivery racing a failure. Meta sent both, so which event happened first is not something this end knows;
  # what must never happen is a row that carries both timestamps, because the analytics read the two
  # independently and would count that one recipient as delivered AND as failed.
  it 'resolves a delivery racing a failure to exactly one of the two' do
    results = Array.new(10) do
      recipient = build_recipient
      apply_concurrently(recipient.id, 'delivered', 'failed')
      recipient.reload.attributes.values_at('status', 'delivered_at', 'failed_at')
    end

    expect(results.map(&:first).uniq).to all(be_in(%w[delivered failed]))
    results.each do |status, delivered_at, failed_at|
      if status == 'delivered'
        expect([delivered_at.present?, failed_at]).to eq([true, nil])
      else
        # The failure took the lock first and is terminal: the later delivery report stamps nothing.
        expect([failed_at.present?, delivered_at]).to eq([true, nil])
      end
    end
  end

  # The rule the race above depends on, stated on its own so a regression names itself.
  it 'treats a failure as terminal' do
    recipient = build_recipient
    recipient.record_outcome!('failed', reported_at: reported_at, error_code: '131026')

    expect(recipient.record_outcome!('delivered', reported_at: reported_at + 60)).to be(false)
    expect(recipient.record_outcome!('read', reported_at: reported_at + 120)).to be(false)
    expect(recipient.reload).to have_attributes(status: 'failed', delivered_at: nil, read_at: nil)
  end
end
