# Turns a recorded operational issue into a support case, or finds the one that already exists
# (docs/p9/04-operations-center.md §bridge).
#
# DEDUP IS THE POINT. An operator looking at a failing inbox must not be able to open a tenth case for it, and
# must not have to search to find out. Two things make that cheap: a signal is already one row per distinct open
# problem, and the row carries `support_ticket_id`. So "is there already a case for this?" is a column read, and
# opening one on a signal that already has an active case returns that case instead of creating another.
#
# WHAT GOES INTO THE CASE is only what the signal holds, and the signal already holds only what
# Operations::SignalRecorder let through: a bounded one-line reason and allow-listed scalar detail keys. No
# provider body, no payload, no URL, no credential -- there is nowhere in the signal for them to have been, so
# there is nothing here to strip.
#
# AN INSTALLATION-WIDE SIGNAL CANNOT BECOME A CASE. `support_tickets.account_id` is NOT NULL because a support
# case belongs to an account, and a queue backlog belongs to the installation. Rather than invent a synthetic
# operations account to satisfy the column, the console says so and links to the Sidekiq dashboard instead.
class Operations::CaseBridge
  # The operator-facing severity of the case follows the severity of the signal, so a critical signal does not
  # become a medium-priority case nobody looks at.
  PRIORITY_FOR_SEVERITY = { 'critical' => :urgent, 'warning' => :high, 'info' => :medium }.freeze
  CATEGORY = 'operational'.freeze

  def initialize(signal)
    @signal = signal
  end

  # The case already covering this issue, if it is still worth pointing at. A resolved or closed case is not:
  # the issue is open again, so a new case is the honest record.
  def existing_case
    linked = @signal.support_ticket
    linked if linked&.active?
  end

  def can_open_case?
    @signal.account_id.present?
  end

  # Returns [case, :existing] or [case, :created], so a caller can say which happened rather than guessing.
  def open_case!(actor_email: nil)
    return [nil, :no_account] unless can_open_case?

    found = existing_case
    return [found, :existing] if found

    ticket = create_case
    @signal.update!(support_ticket: ticket)
    log_operator_action(ticket, actor_email)
    [ticket, :created]
  end

  private

  def create_case
    Support::Tickets::Create.new(
      account: @signal.account, user: nil,
      attributes: {
        title: title, description: description, category: CATEGORY, priority: priority,
        inbox: inbox_subject, source_type: @signal.class.name, source_id: @signal.id
      }
    ).perform
  end

  def title
    I18n.t('super_admin.operations.case_title', source: @signal.source.humanize, signal: @signal.signal.humanize)
  end

  # Plain, bounded, and assembled only from fields the recorder already sanitized.
  def description
    lines = [
      I18n.t('super_admin.operations.case_intro', source: @signal.source, signal: @signal.signal,
                                                  severity: @signal.severity),
      I18n.t('super_admin.operations.case_seen', first: @signal.first_seen_at.utc.iso8601,
                                                 last: @signal.last_seen_at.utc.iso8601,
                                                 count: @signal.occurrences)
    ]
    lines << I18n.t('super_admin.operations.case_reason', reason: @signal.reason) if @signal.reason.present?
    lines << detail_line if @signal.detail.present?
    lines.compact.join("\n")
  end

  def detail_line
    pairs = @signal.detail.map { |key, value| "#{key}=#{value}" }.join(' ')
    I18n.t('super_admin.operations.case_detail', detail: pairs)
  end

  def priority
    PRIORITY_FOR_SEVERITY.fetch(@signal.severity, :medium)
  end

  # The inbox when the signal is about one, so the case opens with the channel already attached and an agent
  # does not have to work out which inbox "authentication failed" meant.
  def inbox_subject
    @signal.subject if @signal.subject_type == 'Inbox'
  end

  # Super Admin has no Pundit layer and no per-operator audit trail of its own, so an operator mutation is
  # recorded the way the existing push diagnostics page records one
  # (app/controllers/super_admin/push_diagnostics_controller.rb#log_super_admin_action): a greppable line naming
  # the actor and what they did. The case itself is also audited, through `audited` on Support::Ticket.
  def log_operator_action(ticket, actor_email)
    Lynomia::OperatorLog.info(
      'OPERATIONS_CASE_OPENED', signal: @signal.id, source: @signal.source, signal_name: @signal.signal,
                                account: @signal.account_id, ticket: ticket.id, reference: ticket.reference,
                                actor: actor_email
    )
  end
end
