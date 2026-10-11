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

  # Every counter from one pass over the campaign's recipients.
  #
  # The page polls this endpoint every five seconds while a campaign is processing
  # (WhatsAppCampaignAnalyticsPage.vue:305-310), and asking for each counter with its own `count` meant a pass
  # per counter -- three of them on predicates no index can serve, over a campaign that may address tens of
  # thousands of contacts. `FILTER (WHERE ...)` is the standard way to ask one scan several questions.
  # `count(source_id)` is the same idea spelled differently: counting a nullable column counts its non-null
  # values, which is exactly "accepted by Meta".
  #
  # Having the state counts in that same row is also what keeps `status_counts` and the six headline counters
  # from disagreeing inside one response -- the property the previous shape got from sharing one grouped query.
  COUNTERS = {
    'audience' => 'count(*)',
    'accepted' => 'count(source_id)',
    'delivered' => "count(*) FILTER (WHERE #{Analytics::Campaigns::Metrics::DELIVERED_SQL})",
    'failed' => 'count(*) FILTER (WHERE campaign_recipients.failed_at IS NOT NULL)'
  }.merge(
    # Namespaced, because `delivered` and `failed` mean different things as a state and as a counter above: the
    # counters read the timestamps, a state is the furthest point the row has reached. The integers come from
    # the enum, so they are the mapping the stored rows carry rather than a second copy of it.
    CampaignRecipient.statuses.to_h do |state, value|
      ["state:#{state}", "count(*) FILTER (WHERE campaign_recipients.status = #{value})"]
    end
  ).freeze

  def initialize(campaign)
    @campaign = campaign
  end

  # `audience` is the whole snapshot -- the denominator of every rate the interface computes and the total the
  # breakdown chart subtracts its known segments from -- so it is `count(*)` rather than a sum of states.
  #
  # `sent` reads the identifier Meta returned rather than the state, because a recipient since delivered or
  # read was also sent. `delivered` and `failed` read the timestamps, like P8 does, which is sound only because
  # the record refuses to mark a delivered or read recipient failed, so a set timestamp is terminal.
  def as_json(*)
    {
      'audience' => counter('audience'),
      'sent' => counter('accepted'),
      'delivered' => counter('delivered'),
      'read' => state_counter('read'),
      'failed' => counter('failed'),
      'skipped' => state_counter('skipped'),
      'status_counts' => STATES.index_with { |state| state_counter(state) }
    }
  end

  private

  # `account_id` is not in the predicate. A campaign belongs to exactly one account and the controller resolved
  # this one inside `Current.account.campaigns` before reaching here, so the column adds no isolation -- and
  # including it put the query outside the (campaign_id, ...) indexes this read path has.
  def recipients
    @recipients ||= CampaignRecipient.where(campaign_id: @campaign.id)
  end

  def counter(name)
    counters.fetch(name).to_i
  end

  def state_counter(state)
    counters.fetch("state:#{state}").to_i
  end

  # An aggregate with no GROUP BY always answers with exactly one row, so there is no empty case to handle: a
  # campaign with no recipients yet reports zero for every counter. `pick` adds the LIMIT 1 that says so.
  def counters
    @counters ||= COUNTERS.keys.zip(
      recipients.pick(*COUNTERS.values.map { |expression| Arel.sql(expression) })
    ).to_h
  end
end
