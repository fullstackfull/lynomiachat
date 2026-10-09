# What the product's own durable records say about each operational area, installation wide
# (docs/p9/04-operations-center.md §computed).
#
# Every number here comes from a table the product was already writing, with ONE grouped query per area and no
# per-account loop. An area whose only source is Redis or a log line is not computed here at all: it is
# `unknown` with the reason "not recorded", because inventing a green badge for it would be the one thing this
# console must never do.
#
# THRESHOLDS ARE EXPLICIT AND ENVIRONMENT-TUNABLE. "One failed recipient" is not a critical campaign and
# labelling it so would train an operator to ignore the badge, so each area states the number it uses and shows
# it in the detail.
class Operations::ComputedSignals
  WINDOW = (ENV.fetch('OPERATIONS_WINDOW_HOURS', 24).to_i).hours
  CAMPAIGN_WINDOW = (ENV.fetch('OPERATIONS_CAMPAIGN_WINDOW_DAYS', 7).to_i).days

  # A send failure happens; a lot of them in one day is a problem. Below the warning line the area is healthy
  # with the count in its detail, so a reader can see it is not zero.
  WHATSAPP_FAILURES_WARNING = ENV.fetch('OPERATIONS_WHATSAPP_FAILURES_WARNING', 25).to_i
  WHATSAPP_FAILURES_CRITICAL = ENV.fetch('OPERATIONS_WHATSAPP_FAILURES_CRITICAL', 250).to_i
  # A share of a campaign's recipients, not a count: ten failures out of ten is a broken campaign and ten out of
  # ten thousand is not.
  CAMPAIGN_FAILURE_RATE_WARNING = ENV.fetch('OPERATIONS_CAMPAIGN_FAILURE_RATE_WARNING', 10).to_f
  CAMPAIGN_FAILURE_RATE_CRITICAL = ENV.fetch('OPERATIONS_CAMPAIGN_FAILURE_RATE_CRITICAL', 50).to_f
  CAMPAIGN_MINIMUM_RECIPIENTS = ENV.fetch('OPERATIONS_CAMPAIGN_MINIMUM_RECIPIENTS', 5).to_i
  FLOW_FAILURES_WARNING = ENV.fetch('OPERATIONS_FLOW_FAILURES_WARNING', 10).to_i

  def initialize(now: Time.current)
    @now = now
    @since = now - WINDOW
  end

  def call
    [whatsapp_delivery, whatsapp_templates, campaigns, automations, flows, commerce].sort_by(&:rank)
  end

  private

  # messages.status is the furthest state a send reached, and a failure keeps `failed` there, so counting failed
  # outgoing messages in a window is exactly the durable fact. Served by index_messages_on_created_at, bounded
  # by one day of volume rather than the whole table, and cached by the caller.
  def whatsapp_delivery
    inbox_ids = Inbox.where(channel_type: 'Channel::Whatsapp').select(:id)
    return Operations::Health.absent(:whatsapp_delivery, 'No WhatsApp inbox exists') unless inbox_ids.exists?

    failures = Message.where(created_at: @since.., message_type: :outgoing, private: false, status: :failed)
                      .where(inbox_id: inbox_ids)
    count = failures.count
    accounts = count.zero? ? 0 : failures.distinct.count(:account_id)
    component(:whatsapp_delivery, threshold_status(count, WHATSAPP_FAILURES_WARNING, WHATSAPP_FAILURES_CRITICAL),
              reason: count.zero? ? nil : "#{count} WhatsApp sends failed in the last #{WINDOW.inspect}",
              detail: { size: count, accounts: accounts, warning_at: WHATSAPP_FAILURES_WARNING,
                        critical_at: WHATSAPP_FAILURES_CRITICAL })
  end

  # A rejected template is a configuration problem that stays broken until someone edits it, so there is no
  # window: a rejection from last month is still a rejection.
  def whatsapp_templates
    return Operations::Health.absent(:whatsapp_templates, 'No template has been synced') unless
      Whatsapp::MessageTemplate.exists?

    rejected = Whatsapp::MessageTemplate.where(meta_status: 'REJECTED')
    count = rejected.count
    component(:whatsapp_templates, count.zero? ? Operations::Health::HEALTHY : Operations::Health::WARNING,
              reason: count.zero? ? nil : "#{count} templates were rejected by Meta",
              detail: { size: count, accounts: count.zero? ? 0 : rejected.distinct.count(:account_id) })
  end

  # Per campaign, because a failure RATE is only meaningful against that campaign's own recipient count. One
  # grouped query over campaign_recipients, then arithmetic in Ruby over at most a few rows.
  def campaigns
    rows = CampaignRecipient.where(created_at: (@now - CAMPAIGN_WINDOW)..)
                            .group(:campaign_id, :account_id)
                            .pluck(Arel.sql('campaign_id, account_id, COUNT(*), COUNT(failed_at)'))
    return Operations::Health.absent(:campaigns, 'No campaign has run recently') if rows.empty?

    bad = rows.filter_map { |_campaign, account, total, failed| campaign_rate(account, total, failed) }
    worst = bad.pluck(:rate).max.to_f
    component(:campaigns, campaign_status(bad, worst),
              reason: bad.empty? ? nil : "#{bad.length} recent campaigns are failing above #{CAMPAIGN_FAILURE_RATE_WARNING}%",
              detail: { size: bad.length, accounts: bad.pluck(:account).uniq.length,
                        warning_at: CAMPAIGN_FAILURE_RATE_WARNING, critical_at: CAMPAIGN_FAILURE_RATE_CRITICAL })
  end

  def campaign_rate(account, total, failed)
    return nil if total < CAMPAIGN_MINIMUM_RECIPIENTS

    rate = (failed.to_f / total) * 100
    return nil if rate < CAMPAIGN_FAILURE_RATE_WARNING

    { account: account, rate: rate }
  end

  def campaign_status(bad, worst)
    return Operations::Health::HEALTHY if bad.empty?

    worst >= CAMPAIGN_FAILURE_RATE_CRITICAL ? Operations::Health::CRITICAL : Operations::Health::WARNING
  end

  # A row whose worker died mid-action. Nothing reclaims them, and the P8 analytics already report them
  # per account; here it is the installation-wide count.
  def automations
    stranded = AutomationRulePendingExecution.abandoned
    count = stranded.count
    component(:automations, count.zero? ? Operations::Health::HEALTHY : Operations::Health::WARNING,
              reason: count.zero? ? nil : "#{count} delayed automation episodes were stranded mid-action",
              detail: { size: count, accounts: count.zero? ? 0 : stranded.distinct.count(:account_id) })
  end

  def flows
    failed = FlowSession.where(status: :failed, finished_at: @since..)
    count = failed.count
    component(:flows, threshold_status(count, FLOW_FAILURES_WARNING, nil),
              reason: count.zero? ? nil : "#{count} flow sessions failed in the last #{WINDOW.inspect}",
              detail: { size: count, accounts: count.zero? ? 0 : failed.distinct.count(:account_id),
                        warning_at: FLOW_FAILURES_WARNING })
  end

  # A store whose authorization is gone has stopped working entirely, which is the definition of critical here.
  def commerce
    return Operations::Health.absent(:commerce, 'No commerce store is connected') unless Commerce::Store.exists?

    broken = Commerce::Store.where(status: [:needs_reauth, :disconnected])
    count = broken.count
    component(:commerce, count.zero? ? Operations::Health::HEALTHY : Operations::Health::CRITICAL,
              reason: count.zero? ? nil : "#{count} commerce stores need to be reconnected",
              detail: { size: count, accounts: count.zero? ? 0 : broken.distinct.count(:account_id) })
  end

  def threshold_status(count, warning_at, critical_at)
    return Operations::Health::HEALTHY if count.zero?
    return Operations::Health::CRITICAL if critical_at && count >= critical_at
    return Operations::Health::WARNING if count >= warning_at

    Operations::Health::HEALTHY
  end

  def component(key, status, reason: nil, detail: {})
    Operations::Health::Component.build(key: key, status: status, reason: reason, detail: detail,
                                        source_class: 'computed', observed_at: @now)
  end
end
