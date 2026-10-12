# What this installation can actually tell you about each kind of channel, and what it cannot
# (docs/product-refinement/10-operations-ui.md §channels).
#
# THE RULE THIS PAGE EXISTS TO ENFORCE: no recent error is not health. Five of the twelve channel types in this
# fork have NO health source at all -- nothing in the repository reports whether a LINE, Telegram, Twilio,
# Bandwidth SMS or X connection still works (Channels::Capability). For those, silence means silence, and the
# row reads `unknown` with the reason spelled out, however long it has been quiet. Only a channel type with real
# evidence -- the reauthorization latch, a stored token expiry, or the provider's own health reading -- can read
# healthy, and the row names which of those three it has.
#
# EVIDENCE, PER CHANNEL TYPE, IN TWO QUERIES. The per-inbox live answer already exists
# (Channels::ConnectionState) and its own documentation says not to call it per inbox across accounts, so this
# does not: the aggregate reads the durable `operations_signals` rows, which is one grouped query however many
# inboxes exist. The inboxes listed underneath are only the ones with a recorded problem, which is the bounded
# set an operator is going to click.
class Operations::ChannelMatrix
  PROBLEM_LIMIT = 50

  def call
    { rows: rows, unreported: unreported, problem_inboxes: problem_inboxes, generated_at: Time.current }
  end

  # One row per channel type, worst first. Memoized so the Overview can ask for the degraded ones without
  # paying for the whole matrix twice.
  def rows
    @rows ||= begin
      counts = Inbox.group(:channel_type).count
      problems = problems_by_channel_type
      Channels::Capability::ENTRIES.map { |entry| row(entry, counts, problems) }.sort_by { |row| row[:component].rank }
    end
  end

  # Just the channel types something is recorded against -- what the Overview asks for when answering "which
  # providers are degraded". Two queries, not the matrix's three.
  def degraded = rows.select { |row| row[:component].needs_attention? }

  # The channel types this installation can say NOTHING about. Not a derived state: it is the capability table's
  # own `health_sources` being empty (Channels::Capability), which is a repository fact.
  def unreported = Channels::Capability::ENTRIES.reject(&:health_reported?).map(&:key)

  private

  def row(entry, counts, problems)
    inboxes = counts[entry.channel_type].to_i
    affected = problems[entry.channel_type] || {}
    {
      entry: entry,
      inboxes: inboxes,
      affected: affected[:inboxes].to_i,
      component: component(entry, inboxes, affected)
    }
  end

  # The four states, in the order that makes them honest:
  #
  #   not in use    no inbox of this type exists, so there is nothing to say
  #   unknown       there is no provider to be connected to, or this fork records nothing about the connection
  #   critical      something latched or expired, recorded against at least one inbox
  #   warning       something milder was recorded
  #   healthy       there IS evidence for this channel type and none of it is reporting a problem
  #
  # The two `unknown` reasons are asked in the same order Channels::ConnectionState asks them -- no provider
  # first, then no health source -- so the per-type row and the per-inbox row never give a reader two different
  # explanations for the same channel.
  def component(entry, inboxes, affected)
    return absent(entry, 'No inbox of this type exists') if inboxes.zero?
    return absent(entry, 'This channel has no external provider to stay connected to') unless entry.provider_backed?
    return absent(entry, 'Nothing in this installation reports whether this connection still works') unless entry.health_reported?

    Operations::Health::Component.build(
      key: entry.key, status: status_for(affected[:severity]), source_class: 'recorded', observed_at: affected[:last_seen_at],
      reason: affected[:inboxes].to_i.positive? ? "#{affected[:inboxes]} of #{inboxes} inboxes reported a problem" : nil,
      detail: { inboxes: inboxes, evidence: entry.health_sources.join(',') },
      investigate: affected[:inboxes].to_i.positive? ? Rails.application.routes.url_helpers.queue_super_admin_operations_path(source: 'channel') : nil
    )
  end

  def status_for(severity)
    case severity
    when 'critical' then Operations::Health::CRITICAL
    when 'warning' then Operations::Health::WARNING
    else Operations::Health::HEALTHY
    end
  end

  def absent(entry, reason)
    Operations::Health.absent(entry.key, reason)
  end

  # One grouped query over the open signals recorded against an inbox, joined to that inbox's channel type: how
  # many inboxes of each type have a problem, the worst severity among them, and when it was last seen.
  def problems_by_channel_type
    Operations::Signal.open_signals
                      .where(subject_type: 'Inbox')
                      .joins('INNER JOIN inboxes ON inboxes.id = operations_signals.subject_id')
                      .group('inboxes.channel_type')
                      .pluck(Arel.sql('inboxes.channel_type, COUNT(DISTINCT operations_signals.subject_id), ' \
                                      'MAX(operations_signals.severity), MAX(operations_signals.last_seen_at)'))
                      .to_h do |channel_type, inboxes, severity, last_seen_at|
                        [channel_type, { inboxes: inboxes, severity: Operations::Signal.severities.key(severity), last_seen_at: last_seen_at }]
                      end
  end

  # The inboxes an operator is going to click, and only those: the ones with a recorded problem. Bounded, with
  # the account and the inbox loaded in one go.
  def problem_inboxes
    Operations::Signal.open_signals.needing_attention
                      .where(subject_type: 'Inbox')
                      .recent_first
                      .includes(:account, :subject)
                      .limit(PROBLEM_LIMIT)
                      .to_a
  end
end
