# One contact a one-off WhatsApp campaign addressed, and what became of the message sent to it
# (docs/p-final/clean-room/specs/D-campaign-recipient-outcomes.md).
#
# The row is written when the campaign runs, because a campaign's audience cannot be reconstructed afterwards: a
# campaign stores references to labels and shared audiences, never the conditions, and membership is resolved at
# send time (custom/app/models/custom/campaign_audience.rb). Recomputing it later would invent recipients that
# were never addressed and lose ones that were.
#
# From then on the row only moves FORWARD. Meta reports `sent`, `delivered`, `read` and `failed` asynchronously,
# out of order, and more than once, so a reported outcome is applied through #record_outcome!, which holds a lock
# on the row and refuses to go backwards. `#status` is therefore the furthest point reached, while the four
# timestamps are the log of what was actually reported -- which is why Analytics::Campaigns::Metrics counts
# delivery from `delivered_at IS NOT NULL OR read_at IS NOT NULL` rather than from the status.
class CampaignRecipient < ApplicationRecord
  # The numeric values are production data and are read by name from
  # custom/app/services/analytics/campaigns/metrics.rb. Neither may change.
  enum :status, { queued: 0, sent: 1, delivered: 2, read: 3, failed: 4, skipped: 5 }

  # How far along the ladder each state is. `skipped` is not on the ladder at all: Lynomia decided not to send,
  # so no provider report can move it, and no provider report should.
  LADDER = { 'queued' => 0, 'sent' => 1, 'delivered' => 2, 'read' => 3 }.freeze

  # The column that records "this event was reported", per reported state. A skip has none, because nothing was
  # attempted and so there is no provider event to time.
  REPORTED_AT_COLUMN = {
    'sent' => :sent_at, 'delivered' => :delivered_at, 'read' => :read_at, 'failed' => :failed_at
  }.freeze

  # A failure may still be recorded over `queued` or `sent`, never over a delivery: a message that reached the
  # device cannot un-arrive, and Metrics#failed reads `failed_at`, so recording one here would make the failure
  # count wrong for good.
  FAILURE_OVERRIDES = %w[queued sent].freeze

  belongs_to :account
  belongs_to :campaign
  belongs_to :contact
  belongs_to :inbox

  validates :status, presence: true

  scope :for_account, ->(account) { where(account_id: account.id) }

  # The one write that applies a reported outcome, used by both the provider report path and the send path.
  #
  # `reported_at` is the provider's own timestamp for the event. It is stamped whenever its event is reported,
  # even when the state does not move -- that is what lets a late `delivered` report backfill `delivered_at` on a
  # recipient already at `read` without demoting it.
  #
  # Idempotent: a redelivered report finds the timestamp already set and writes nothing at all, so the record is
  # byte-identical after the second application.
  def record_outcome!(state, reported_at: nil, error_code: nil, error_title: nil, error_message: nil)
    reported = state.to_s
    return false unless REPORTED_AT_COLUMN.key?(reported)

    with_lock do
      changes = if reported == 'failed'
                  failure_changes(reported_at, error_code, error_title, error_message)
                else
                  progress_changes(reported, reported_at)
                end
      next false if changes.empty?

      update!(changes)
      true
    end
  end

  private

  # A report on the ladder stamps its own timestamp whenever that timestamp is missing, and moves the state only
  # when it is further along than where the record already is. Those two rules together are the ladder: a `read`
  # report arriving before `delivered` leaves `delivered_at` null and the state at read, and the late
  # `delivered` report then backfills the timestamp without demoting the state.
  #
  # A failure is terminal, so nothing is stamped over one. Without that, a `delivered` report racing a `failed`
  # report could leave a row carrying both timestamps -- and the analytics read the two independently, so that
  # one row would be counted once as delivered and once as failed, and the interface's breakdown would add up
  # to more recipients than the campaign had.
  def progress_changes(reported, reported_at)
    return {} if failed?

    column = REPORTED_AT_COLUMN.fetch(reported)
    changes = {}
    changes[column] = reported_at || Time.current if public_send(column).blank?
    changes[:status] = reported if LADDER.fetch(reported) > LADDER.fetch(status, Float::INFINITY)
    changes
  end

  # A failure is all-or-nothing, and that is what makes `failed_at` readable as the failure count. Meta does
  # send late failures for messages it has already delivered, and a message that reached the device cannot
  # un-arrive -- so over a delivered or read recipient the report is dropped entirely, timestamp included.
  # Stamping `failed_at` "for the record" while leaving the state alone would make P8's failure count, which
  # reads that column, permanently wrong.
  def failure_changes(reported_at, error_code, error_title, error_message)
    return {} unless FAILURE_OVERRIDES.include?(status)

    changes = { status: 'failed' }
    changes[:failed_at] = reported_at || Time.current if failed_at.blank?
    changes.merge(failure_details(error_code, error_title, error_message))
  end

  # Only values the provider actually gave. A redelivered failure must not overwrite a stored code with a nil.
  def failure_details(error_code, error_title, error_message)
    { error_code: error_code, error_title: error_title, error_message: error_message }
      .compact
      .reject { |_column, value| value.to_s.strip.empty? }
  end
end
