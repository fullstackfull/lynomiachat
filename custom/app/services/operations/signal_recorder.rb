# The only thing that writes an Operations::Signal (docs/p9/04-operations-center.md §recording).
#
# One writer for two reasons. First, dedup: a signal is one row per distinct open problem, so recording is an
# upsert on the open identity and not an insert, and four callers getting that right independently is four
# chances to get it wrong. Second, and more important, this is where the no-secrets rule is actually enforced --
# `reason` is bounded and whitespace-collapsed, and `detail` accepts only allow-listed keys holding scalar
# values. A caller cannot put a provider response body, a webhook payload or a URL with a token into this table
# even by accident, because there is nowhere for it to go.
#
# Constructed with WHERE the observation is about and then told WHAT was observed, because the first part is
# fixed for the length of a job and the second changes per call:
#
#   recorder = Operations::SignalRecorder.new(source: :email_channel, account: inbox.account, subject: inbox)
#   recorder.record(:authentication_failed, severity: :critical, reason: error.message)
#   recorder.resolve_all   # the next successful fetch
#
# Recording never raises into its caller. These writers sit inside OSS jobs that fetch email and deliver
# webhooks for every account; a validation bug here must not stop email arriving. Same reasoning, and the same
# shape, as Custom::Account#start_billing_trial.
class Operations::SignalRecorder
  # The only keys `detail` may carry. Ids, codes, counts, thresholds and names of safe things. Anything not here
  # is dropped rather than stored, because a key nobody listed is a key nobody checked.
  DETAIL_KEYS = %w[
    code error_code status_code provider channel_type template_name
    queue size latency_seconds depth_threshold latency_threshold
    previous current added processes enqueued scheduled retrying dead
    inbox_id store_id endpoint_host attempts strikes
  ].freeze

  MAX_REASON = 500

  # A detail value must be a scalar a reader can act on. A token-shaped string has no whitespace, which is what
  # keeps provider prose out: prose belongs in `reason`, where it is bounded and collapsed.
  SAFE_TOKEN = %r{\A[\w.:+@/-]{0,100}\z}

  def initialize(source:, account: nil, subject: nil)
    @source = source.to_s
    @account_id = account&.id
    @subject = subject
  end

  # Returns the signal, or nil if recording failed (which is logged and never raised).
  def record(signal, severity: :warning, reason: nil, detail: {}, at: Time.current)
    existing = open_signal(signal)
    return increment(existing, severity, reason, detail, at) if existing

    create_signal(signal, severity, reason, detail, at)
  rescue ActiveRecord::RecordNotUnique
    retry_increment(signal, severity, reason, detail, at)
  rescue StandardError => e
    Rails.logger.error("[Operations] could not record #{@source}/#{signal}: #{e.class}")
    nil
  end

  # Something observed the thing working again. Clears EVERY open signal for this source and subject rather than
  # one, because a recovered inbox should clear both its authentication and its connection signal without the
  # caller having to know which one is open.
  def resolve_all(at: Time.current)
    resolve_scope.update_all(resolved_at: at, updated_at: at) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.error("[Operations] could not resolve #{@source}: #{e.class}")
    0
  end

  def resolve(signal, at: Time.current)
    resolve_scope.where(signal: signal.to_s).update_all(resolved_at: at, updated_at: at) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.error("[Operations] could not resolve #{@source}/#{signal}: #{e.class}")
    0
  end

  private

  def resolve_scope
    scope = Operations::Signal.open_signals.where(source: @source, account_id: @account_id)
    return scope if @subject.nil?

    scope.where(subject_type: @subject.class.name, subject_id: @subject.id)
  end

  def open_signal(signal)
    Operations::Signal.open_signals.find_by(
      source: @source, signal: signal.to_s, account_id: @account_id,
      subject_type: @subject&.class&.name, subject_id: @subject&.id
    )
  end

  # The partial unique index is what makes concurrent recording safe: two workers reporting the same failure at
  # the same moment race on the insert, the loser gets RecordNotUnique, and this finds the row the winner created.
  def retry_increment(signal, severity, reason, detail, at)
    existing = open_signal(signal)
    existing && increment(existing, severity, reason, detail, at)
  end

  def create_signal(signal, severity, reason, detail, at)
    Operations::Signal.create!(
      source: @source, signal: signal.to_s, severity: severity.to_s, account_id: @account_id, subject: @subject,
      reason: sanitized_reason(reason), detail: sanitized_detail(detail),
      first_seen_at: at, last_seen_at: at, occurrences: 1
    )
  end

  # Severity only ever rises while a signal is open: a problem that was critical once does not become a warning
  # because the latest observation was milder, and an operator who saw `critical` must not find it quietly
  # downgraded.
  def increment(signal, severity, reason, detail, at)
    signal.update!(
      last_seen_at: at, occurrences: signal.occurrences + 1,
      severity: highest_severity(signal.severity, severity),
      reason: sanitized_reason(reason) || signal.reason,
      detail: signal.detail.merge(sanitized_detail(detail))
    )
    signal
  end

  def highest_severity(current, observed)
    levels = Operations::Signal.severities
    levels.key([levels.fetch(current.to_s), levels.fetch(observed.to_s)].max)
  end

  # One grep-able line. Whitespace collapsed so a multi-line provider error becomes one line, and truncated so
  # its prose cannot fill a column.
  def sanitized_reason(raw)
    return nil if raw.blank?

    raw.to_s.gsub(/\s+/, ' ').strip.truncate(MAX_REASON)
  end

  def sanitized_detail(raw)
    (raw || {}).to_h.each_with_object({}) do |(key, value), safe|
      name = key.to_s
      next unless DETAIL_KEYS.include?(name)

      sanitized = sanitized_value(value)
      safe[name] = sanitized unless sanitized.nil?
    end
  end

  def sanitized_value(value)
    case value
    when Numeric, TrueClass, FalseClass then value
    when String, Symbol then value.to_s.match?(SAFE_TOKEN) ? value.to_s : nil
    end
  end
end
