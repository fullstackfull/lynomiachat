# One campaign's funnel, counted the same way the cross-campaign analytics count it
# (docs/p-final/clean-room/specs/D-campaign-recipient-outcomes.md §2, §4.3).
#
# The definitions are deliberately the same expressions P8 uses -- `Analytics::Campaigns::Metrics::DELIVERED_SQL`
# is referenced rather than restated -- because an operator comparing this page with the account-wide campaign
# report will find any disagreement on the first comparison, and a build where the two disagree about one
# campaign's delivered count is a defect, not a rounding difference.
#
# `delivered` therefore counts a recipient whose `read_at` is set even when `delivered_at` is still null. Meta
# can report `read` before `delivered`, and a message that was read reached the device: counting it any other
# way would make the interface's chart clamp its delivered band to zero and show a campaign that was read but
# never delivered.
#
# `status_counts` is counted in the same query as the states it reports, so the six headline counters and the
# per-state tabs cannot drift apart within one response.
class Campaigns::RecipientMetrics
  # The six keys the metric cards read, plus the vocabulary the recipient table's tabs read
  # (app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue:189,213).
  STATES = CampaignRecipient.statuses.keys.freeze

  def initialize(campaign)
    @campaign = campaign
  end

  def as_json(*)
    {
      'audience' => audience,
      'sent' => accepted_by_provider,
      'delivered' => delivered,
      'read' => counts_by_state.fetch('read', 0),
      'failed' => failed,
      'skipped' => counts_by_state.fetch('skipped', 0),
      'status_counts' => STATES.index_with { |state| counts_by_state.fetch(state, 0) }
    }
  end

  private

  def recipients
    @recipients ||= CampaignRecipient.where(account_id: @campaign.account_id, campaign_id: @campaign.id)
  end

  # The whole snapshot, which is the denominator of every rate the interface computes and the total the
  # breakdown chart subtracts its known segments from -- so it has to be the row count, not a sum of states.
  def audience
    @audience ||= counts_by_state.values.sum
  end

  # Handed to Meta and accepted. Read from the identifier Meta returned rather than from the state, because a
  # recipient that has since been delivered or read was also sent.
  def accepted_by_provider
    recipients.where.not(source_id: nil).count
  end

  def delivered
    recipients.where(Analytics::Campaigns::Metrics::DELIVERED_SQL).count
  end

  # From the timestamp, like P8, which is only sound because the record refuses to mark a delivered or read
  # recipient failed -- so the timestamp is terminal once set.
  def failed
    recipients.where.not(failed_at: nil).count
  end

  def counts_by_state
    @counts_by_state ||= recipients.group(:status).count
  end
end
