# The Operations Center's front page, which answers six questions and nothing else
# (docs/product-refinement/10-operations-ui.md §overview).
#
#   1. What is critical right now?
#   2. What needs a human to do something?
#   3. Which accounts are affected?
#   4. Which providers or channels are degraded?
#   5. What recovered recently?
#   6. What is unknown because nothing reports it?
#
# NO DECORATIVE CARDS. The page this replaces opened with five counts -- accounts, inboxes, cases,
# conversations -- which are scale, not operations: nobody decides anything from "11,402 conversations", the
# Super Admin dashboard already shows them, and they pushed the only actionable thing on the page below the
# fold. They are gone, and the page links to the dashboard for scale instead.
#
# QUESTION SIX IS THE ONE THAT MAKES THE REST TRUSTWORTHY. Five of twelve channel types in this fork report
# nothing about their connection, five product areas have no durable source, and a commerce store nobody has
# called has no observation either way. All of that is collected and shown as `unknown`, with the reason, rather
# than being left to read as green by omission.
#
# WHAT IS CACHED AND WHY. The derived blocks -- the computed product areas, the channel matrix, the commerce
# summary -- are cached together for five minutes, and the page states when they were calculated. The probes
# are not: they are a `SELECT 1`, a PING and a process-set read, and a stale "the database is up" is worse than
# no answer. Neither is anything read from `operations_signals`: those are bounded reads over partial indexes,
# and an operator refreshing after a fix must see the queue clear.
class Operations::Overview
  DERIVED_CACHE_KEY = 'operations:overview_derived:v2'.freeze
  DERIVED_TTL = 5.minutes
  # How far back "recovered recently" looks. Long enough to cover a night shift's worth of handover.
  RECOVERED_WINDOW = 24.hours
  # Every list on this page is a few rows with a link to the full one. A front page that tries to be the queue
  # is a front page nobody reads.
  LIST_LIMIT = 10

  def call
    probes = Operations::Probes.new
    platform = probes.call + [probes.migrations]
    derived, derived_at = derived_blocks
    {
      critical: critical(platform, derived),
      attention: attention,
      accounts: affected_accounts,
      degraded: derived[:degraded],
      recovered: recovered,
      unknown: unknown(platform, derived),
      platform: platform,
      release: probes.release,
      computed: derived[:computed],
      commerce: derived[:commerce],
      jobs: Operations::BackgroundJobs.new.call,
      billing: Operations::BillingState.new.call,
      derived_at: derived_at,
      generated_at: Time.current
    }
  end

  private

  # ---- 1. What is critical right now
  #
  # Two kinds of critical, together, because an operator does not care which mechanism found it: a recorded
  # incident at critical severity, and a live or computed component that is critical. Suppressed incidents are
  # excluded -- a human deliberately silenced those, and this is the list that is allowed to interrupt.
  def critical(platform, derived)
    signals = Operations::Signal.open_signals.severity_critical.not_suppressed
    {
      signals: signals.recent_first.includes(:account, :support_ticket).limit(LIST_LIMIT).to_a,
      signal_count: signals.count,
      components: (platform + derived[:computed] + derived[:degraded].pluck(:component))
        .select { |component| component.status == Operations::Health::CRITICAL }
    }
  end

  # ---- 2. What needs a human
  #
  # The queue's own definition (Operations::Signal.attention_queue), so the number here and the list on the
  # queue page cannot disagree. Acknowledged and suppressed are shown beside it, because "0 need action" means
  # something different when 30 are parked.
  def attention
    open_signals = Operations::Signal.open_signals
    {
      needs_action: open_signals.attention_queue.count,
      acknowledged: open_signals.acknowledged.count,
      suppressed: open_signals.suppressed.count,
      unlinked: open_signals.attention_queue.where(support_ticket_id: nil).count
    }
  end

  # ---- 3. Which accounts are affected
  #
  # One grouped query over the attention queue, then one for the names. Worst severity first, then most
  # occurrences: that is the order somebody triaging would pick them up in.
  #
  # Installation-wide signals (account_id NULL) are counted separately rather than dropped or attributed to an
  # account: "the dead set is growing" belongs to nobody's account and must not disappear from this answer.
  def affected_accounts
    rows = Operations::Signal.attention_queue.where.not(account_id: nil)
                             .group(:account_id).pluck(Arel.sql('account_id, MAX(severity), COUNT(*)'))
    ranked = rows.sort_by { |_id, severity, count| [-severity, -count] }.first(LIST_LIMIT)
    names = Account.where(id: ranked.map(&:first)).pluck(:id, :name).to_h
    {
      accounts: ranked.map do |id, severity, count|
        { id: id, name: names[id], severity: Operations::Signal.severities.key(severity), signals: count }
      end,
      affected_total: rows.length,
      installation_wide: Operations::Signal.attention_queue.where(account_id: nil).count
    }
  end

  # ---- 5. What recovered recently
  #
  # Resolved, not quiet. A signal leaves the open set only when something OBSERVED the thing working again
  # (Operations::Signal), so this list is evidence of recovery rather than the absence of evidence of failure.
  def recovered
    scope = Operations::Signal.resolved.where(resolved_at: RECOVERED_WINDOW.ago..)
    { signals: scope.order(resolved_at: :desc).includes(:account).limit(LIST_LIMIT).to_a,
      count: scope.count, window: RECOVERED_WINDOW }
  end

  # ---- 6. What is unknown because nothing reports it
  #
  # Collected from the components already gathered, so this costs no query. `source_class == 'absent'` is the
  # taxonomy's own word for "nothing records this", which is why it can be collected rather than guessed at.
  def unknown(platform, derived)
    components = platform + derived[:computed] + derived[:channels]
    {
      components: components.select { |component| component.status == Operations::Health::UNKNOWN },
      unreported_channels: derived[:unreported_channels],
      unobserved_stores: derived[:commerce][:unobserved].to_i
    }
  end

  # The derived blocks, cached as already-built values plus the moment they were produced, so a stale block
  # cannot claim to be fresh. A cache miss or a cache backend that is not available simply computes.
  def derived_blocks
    cached = Rails.cache.fetch(DERIVED_CACHE_KEY, expires_in: DERIVED_TTL) { { blocks: build_derived, at: Time.current } }
    [cached[:blocks], cached[:at]]
  rescue StandardError
    [build_derived, Time.current]
  end

  def build_derived
    matrix = Operations::ChannelMatrix.new
    { computed: Operations::ComputedSignals.new.call, channels: matrix.rows.pluck(:component),
      degraded: matrix.degraded, unreported_channels: matrix.unreported,
      commerce: Operations::CommerceOperations.new.summary }
  end
end
