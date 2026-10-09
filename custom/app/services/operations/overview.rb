# Everything the Operations Center shows at the top (docs/p9/04-operations-center.md §overview).
#
# Three classes of information, each labelled with how it was established, because a reader acts differently on
# each: `probed` was read live this request, `recorded` is a durable row something wrote when it observed a
# problem, and `computed` is derived from records the product already keeps.
#
# The computed block is cached for five minutes and the page states when it was calculated. The probes are not
# cached -- they are a `SELECT 1`, a PING and a process-set read, and a stale "the database is up" is worse than
# no answer. The recorded feed is not cached either: it is a bounded read over a partial index, and an operator
# refreshing after a fix must see it clear.
class Operations::Overview
  COMPUTED_CACHE_KEY = 'operations:computed_signals'.freeze
  COMPUTED_TTL = 5.minutes
  FEED_LIMIT = 50

  def call
    probes = Operations::Probes.new
    computed, computed_at = computed_signals
    {
      probes: probes.call + [probes.migrations],
      release: probes.release,
      computed: computed,
      computed_at: computed_at,
      signals: signal_summary,
      totals: totals,
      generated_at: Time.current
    }
  end

  private

  # Cached as the already-serialized components plus the moment they were produced, so a stale block cannot
  # claim to be fresh. A cache miss or a cache backend that is not available simply computes.
  def computed_signals
    cached = Rails.cache.fetch(COMPUTED_CACHE_KEY, expires_in: COMPUTED_TTL) do
      { components: Operations::ComputedSignals.new.call, at: Time.current }
    end
    [cached[:components], cached[:at]]
  rescue StandardError
    [Operations::ComputedSignals.new.call, Time.current]
  end

  def signal_summary
    open_signals = Operations::Signal.open_signals
    {
      open: open_signals.count,
      critical: open_signals.severity_critical.count,
      unlinked: open_signals.needing_attention.where(support_ticket_id: nil).count,
      recent: open_signals.recent_first.includes(:account, :support_ticket).limit(FEED_LIMIT)
    }
  end

  # Four flat counts. `conversations` uses the planner estimate for the same reason the existing Super Admin
  # dashboard does (app/controllers/super_admin/dashboard_controller.rb:25-32): an exact COUNT(*) scans the
  # whole table and the number is a scale indicator, not an accounting figure.
  def totals
    {
      accounts: Account.count,
      inboxes: Inbox.count,
      active_cases: Support::Ticket.active.count,
      overdue_cases: Support::Ticket.overdue.count,
      conversations: conversation_estimate
    }
  end

  def conversation_estimate
    estimate = ActiveRecord::Base.connection.select_value(
      "SELECT reltuples::bigint FROM pg_class WHERE relname = 'conversations'"
    ).to_i
    estimate.negative? ? Conversation.count : estimate
  end
end
