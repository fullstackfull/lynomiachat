# The operator's work list: which open problems need a human, in what order
# (docs/product-refinement/07-operations-control-center-v2.md §3).
#
# WHAT MAKES THIS A QUEUE RATHER THAN A FEED
#
# The existing Operations issues page lists open signals newest-first, which answers "what has happened" and
# not "what should I do". A queue answers the second question, and the difference is three things:
#
#   * it ranks by SEVERITY first and age second, so a critical problem from this morning outranks a warning
#     from a minute ago;
#   * it respects the operator-handling layer, so an acknowledged or deliberately suppressed signal is not
#     competing for attention with one nobody has looked at;
#   * it has named views an operator actually works from, rather than one list plus a status dropdown.
#
# EVERY VIEW IS BOUNDED AND EVERY READ IS GROUPED. There is no per-row query: `includes` preloads the account
# and the support case, the counts come from one aggregate, and nothing here calls a provider. An operator
# opening this page on an installation with thousands of signals must cost the same as on one with ten.
class Operations::AttentionQueue
  PER_PAGE = 50
  MAX_PER_PAGE = 200

  # The named views, in the order an operator works them. Each is a predicate over OPEN signals except
  # `resolved`, which is history.
  #
  # `recurring` is a judgement about noise rather than severity: a problem seen many times is either important
  # or badly tuned, and either way it wants a human decision rather than another row.
  RECURRENCE_THRESHOLD = 10

  VIEWS = {
    'critical' => ->(scope) { scope.open_signals.severity_critical.not_suppressed },
    'needs_action' => ->(scope) { scope.attention_queue },
    'recent' => ->(scope) { scope.open_signals.where(first_seen_at: 24.hours.ago..) },
    'recurring' => ->(scope) { scope.open_signals.where(occurrences: RECURRENCE_THRESHOLD..) },
    'acknowledged' => ->(scope) { scope.open_signals.acknowledged.not_suppressed },
    'suppressed' => ->(scope) { scope.open_signals.suppressed },
    'resolved' => ->(scope) { scope.resolved },
    'all_open' => ->(scope) { scope.open_signals }
  }.freeze

  DEFAULT_VIEW = 'needs_action'.freeze

  def initialize(params: {})
    @params = (params || {}).to_h.symbolize_keys
  end

  def view = VIEWS.key?(@params[:view].to_s) ? @params[:view].to_s : DEFAULT_VIEW

  def signals
    @signals ||= ordered(filtered(VIEWS.fetch(view).call(Operations::Signal.all)))
                 .includes(:account, :support_ticket)
                 .page(@params[:page]).per(per_page)
  end

  # Every view's count in ONE query, so the tab bar costs one round trip rather than eight.
  #
  # `FILTER (WHERE …)` rather than eight `COUNT` queries or eight scope calls: the predicates are the same ones
  # the views use, expressed once in SQL. They are written here rather than derived from VIEWS because a lambda
  # over a relation cannot be turned into a filter clause, and a wrong count is worse than a duplicated
  # predicate -- so the two are kept adjacent and a spec asserts they agree.
  def counts
    @counts ||= begin
      now = Time.current
      row = Operations::Signal.connection.select_one(<<~SQL.squish)
        SELECT
          COUNT(*) FILTER (WHERE resolved_at IS NULL AND severity = 2 AND #{not_suppressed_sql(now)}) AS critical,
          COUNT(*) FILTER (WHERE resolved_at IS NULL AND severity IN (1, 2) AND acknowledged_at IS NULL
                                 AND #{not_suppressed_sql(now)}) AS needs_action,
          COUNT(*) FILTER (WHERE resolved_at IS NULL AND first_seen_at >= #{quote(24.hours.before(now))}) AS recent,
          COUNT(*) FILTER (WHERE resolved_at IS NULL AND occurrences >= #{RECURRENCE_THRESHOLD}) AS recurring,
          COUNT(*) FILTER (WHERE resolved_at IS NULL AND acknowledged_at IS NOT NULL
                                 AND #{not_suppressed_sql(now)}) AS acknowledged,
          COUNT(*) FILTER (WHERE resolved_at IS NULL AND suppressed_until > #{quote(now)}) AS suppressed,
          COUNT(*) FILTER (WHERE resolved_at IS NOT NULL) AS resolved,
          COUNT(*) FILTER (WHERE resolved_at IS NULL) AS all_open
        FROM operations_signals
      SQL
      row.transform_values(&:to_i)
    end
  end

  # The filter values an operator may pick from, for the form. Read from the model's own allow-lists rather
  # than from the data, so a filter does not silently disappear because nothing has gone wrong with it yet.
  def filter_options
    {
      views: VIEWS.keys,
      severities: Operations::Signal.severities.keys,
      sources: Operations::Signal::SOURCES,
      signals: Operations::Signal::SIGNALS
    }
  end

  private

  def per_page
    requested = @params[:per_page].to_i
    return PER_PAGE unless requested.positive?

    [requested, MAX_PER_PAGE].min
  end

  def filtered(scope)
    scope = scope.where(severity: @params[:severity]) if valid?(:severity, Operations::Signal.severities.keys)
    scope = scope.where(source: @params[:source]) if valid?(:source, Operations::Signal::SOURCES)
    scope = scope.where(signal: @params[:signal]) if valid?(:signal, Operations::Signal::SIGNALS)
    scope = scope.where(account_id: @params[:account_id].to_i) if @params[:account_id].to_s.match?(/\A\d+\z/)
    scope = scope.where(first_seen_at: since..) if since
    search(scope)
  end

  # Worst first, then stalest first inside a severity. Stalest rather than newest on purpose: within equally
  # severe problems the one that has been waiting longest is the one being neglected.
  def ordered(scope)
    scope.order(severity: :desc, last_seen_at: :asc, id: :asc)
  end

  def since
    days = @params[:since_days].to_i
    days.positive? ? days.days.ago : nil
  end

  # One search box, matched against the handful of things an operator actually has in front of them: an account
  # id or name, a signal or source name, a subject id out of a support case, or a provider error code.
  #
  # The error code lives in the signal's `detail` jsonb, written by Operations::SignalRecorder under the keys
  # `code` and `error_code`. Matched with `->>` on those two keys only -- not a jsonb-wide search -- so the
  # predicate stays something the planner can reason about, and so a value under some other key cannot be
  # matched by accident.
  def search(scope)
    term = @params[:q].to_s.strip
    return scope if term.blank?

    like = "%#{Operations::Signal.sanitize_sql_like(term)}%"
    scoped = scope.left_joins(:account)
    matches = scoped.where('operations_signals.signal ILIKE :like', like: like)
                    .or(scoped.where('operations_signals.source ILIKE :like', like: like))
                    .or(scoped.where('operations_signals.detail ->> :code_key = :term', code_key: 'code', term: term))
                    .or(scoped.where('operations_signals.detail ->> :code_key = :term', code_key: 'error_code', term: term))
                    .or(scoped.where('accounts.name ILIKE :like', like: like))
    return matches unless term.match?(/\A\d+\z/)

    matches.or(scoped.where(account_id: term.to_i)).or(scoped.where(subject_id: term.to_i))
  end

  def not_suppressed_sql(now)
    "(suppressed_until IS NULL OR suppressed_until <= #{quote(now)})"
  end

  def quote(value)
    Operations::Signal.connection.quote(value)
  end

  def valid?(key, allowed)
    allowed.include?(@params[key].to_s)
  end
end
