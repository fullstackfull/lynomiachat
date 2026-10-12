# What the queues are doing, in the product's own terms (docs/product-refinement/10-operations-ui.md §jobs).
#
# THIS IS NOT A SECOND SIDEKIQ. Sidekiq's own web UI is mounted on this installation and it is better at every
# job-level question: which job failed, with what backtrace, retry it, kill it. This page does not reproduce any
# of that and links to it instead.
#
# What it adds is the one thing Sidekiq's dashboard cannot know: WHICH PRODUCT CAPABILITY a backed-up queue
# stops. "critical: 4,312 enqueued" means nothing to someone deciding whether to wake a developer; "inbound
# messages and replies are 4,312 deep and 90 seconds behind" is a decision. So each queue carries the sentence
# that says what waits on it, and anything without one is listed as itself rather than given an invented
# meaning.
#
# The durable side of this already exists and is not duplicated: Lynomia::QueueHealthJob records `backlog`,
# `dead_set_grew` and `no_workers` as Operations::Signal rows, which is what the queue and the issue feed show.
# This is the live reading beside them.
class Operations::BackgroundJobs
  # What waits on each queue, for the queues this product actually names (config/sidekiq.yml). A queue not
  # listed here is still shown -- with no sentence, because inventing one would be worse than admitting we have
  # not written it down.
  MEANING = {
    'critical' => 'Inbound messages, replies and webhook deliveries',
    'high' => 'Conversation and contact work agents are waiting on',
    'medium' => 'Campaigns, flows and automation episodes',
    'default' => 'Commerce reads, template sync and most product jobs',
    'mailers' => 'Outgoing email',
    'action_mailbox_routing' => 'Inbound email being routed to a conversation',
    'low' => 'Reporting and rollups',
    'scheduled_jobs' => 'Everything on a schedule: SLA sweeps, reminders, health checks',
    'deferred' => 'Work deliberately pushed behind the rest',
    'purgable' => 'Deletions and data retention',
    'housekeeping' => 'Maintenance this installation runs on itself'
  }.freeze

  # A queue is behind when its oldest job has been waiting this long. The same threshold
  # Lynomia::QueueHealthJob uses to RECORD a backlog, read from it rather than chosen again here, so the live
  # page and the durable signal cannot disagree about what "behind" means.
  LATENCY_WARNING = Lynomia::QueueHealthJob::LATENCY_THRESHOLD

  def call
    require 'sidekiq/api'
    stats = Sidekiq::Stats.new
    { queues: queues, totals: totals(stats), links: links, generated_at: Time.current }
  rescue StandardError => e
    # The same rule the probes follow: we failed to look, which is not the same as having looked and found
    # nothing wrong.
    { queues: nil, totals: nil, links: links, error: e.class.name, generated_at: Time.current }
  end

  private

  # Only the queues with something in them, worst latency first. A list of twenty empty queues is noise, and the
  # totals below already say the whole system is idle.
  def queues
    rows = Sidekiq::Queue.all.filter_map do |queue|
      depth = queue.size
      next if depth.zero?

      { name: queue.name, size: depth, latency: queue.latency.round,
        meaning: MEANING[queue.name], behind: queue.latency >= LATENCY_WARNING }
    end
    rows.sort_by { |queue| -queue[:latency] }
  end

  def totals(stats)
    { enqueued: stats.enqueued, scheduled: stats.scheduled_size, retrying: stats.retry_size,
      dead: stats.dead_size, processed: stats.processed, failed: stats.failed }
  end

  # Links, not embeds: an operator who needs the job level goes to the tool that owns it. Built from the mount
  # point's own route helper, so moving the mount moves these with it.
  def links
    base = Rails.application.routes.url_helpers.sidekiq_web_path
    { sidekiq: base, retries: "#{base}/retries", dead: "#{base}/morgue" }
  end
end
