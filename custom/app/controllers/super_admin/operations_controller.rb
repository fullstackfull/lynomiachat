# The Lynomia Operations Center (docs/p9/04-operations-center.md).
#
# One operator console that answers "what in Lynomia Chat needs attention?" without a terminal. It is NOT a
# second Grafana: it does not watch CPU, disk or request latency, which Prometheus and the host already do
# better. It reads the product's own records and the signals the product writes about itself.
#
# Super Admin only, through the `authenticate_super_admin!` that SuperAdmin::ApplicationController applies to
# every action. There is no Pundit layer on this surface and this page does not invent one; what it does instead
# is stay READ-ONLY apart from a single, audited mutation -- opening a support case for a recorded issue.
#
# Server-rendered ERB inside the Administrate shell, with Tailwind, following the shape of
# app/views/super_admin/push_diagnostics/show.html.erb. No Vue island: nothing on this page needs client state
# that a form and a link cannot express.
class SuperAdmin::OperationsController < SuperAdmin::ApplicationController
  ISSUE_PAGE_SIZE = 50

  def show
    @overview = Operations::Overview.new.call
  end

  def accounts
    @health = Operations::AccountHealth.new(page: params[:page]).call
  end

  def issues
    @signals = filtered_signals.recent_first.includes(:account, :support_ticket)
                               .page(params[:page]).per(ISSUE_PAGE_SIZE)
    @status = params[:status].presence || 'open'
  end

  # ---- Control Center V2 (docs/product-refinement/07-operations-control-center-v2.md)

  # The operator work list: what needs a human, worst first.
  def queue
    @queue = Operations::AttentionQueue.new(params: queue_params)
  end

  # One incident, in full: what it is, who it affects, its history, and what an operator may safely do about it.
  def signal
    @signal = Operations::Signal.includes(:account, :support_ticket).find_by(id: params[:id])
    return redirect_to(queue_super_admin_operations_path, alert: t('super_admin.operations.signal_not_found')) if @signal.nil?

    # The whole lifecycle, machine observations and operator acts together
    # (docs/product-refinement/10-operations-ui.md §timeline), not just the stored operator rows.
    @timeline = Operations::IncidentTimeline.new(@signal).call
  end

  # What this installation can say about each KIND of channel, and what it cannot. Its own page because the
  # answer is per channel type, not per account, and because "we report nothing about this channel" is the most
  # important row on it.
  def channels
    @matrix = Operations::ChannelMatrix.new.call
  end

  # Every connected store and whether its provider is actually answering
  # (docs/product-refinement/09-commerce-operations.md).
  def commerce
    @commerce = Operations::CommerceOperations.new(params: commerce_params).call
  end

  # One affected account, in full. Product decision: an operator must understand an account without hunting
  # through many disconnected pages (docs/product-refinement/07-operations-control-center-v2.md §5).
  def account
    account = Account.find_by(id: params[:id])
    return redirect_to(accounts_super_admin_operations_path, alert: t('super_admin.operations.account_not_found')) if account.nil?

    @snapshot = Operations::AccountSnapshot.new(account).call
  end

  def acknowledge_signal
    with_signal { |lifecycle| lifecycle.acknowledge(reason: params[:reason]) }
  end

  def suppress_signal
    with_signal { |lifecycle| lifecycle.suppress(until_time: params[:suppressed_until], reason: params[:reason]) }
  end

  def resume_signal
    with_signal(&:resume)
  end

  # The one mutation this page had before V2. Opening a case for an issue that already has an active one
  # surfaces that case instead of creating a second, which is what stops an operator generating duplicate case
  # spam from a refresh.
  def open_case
    signal = Operations::Signal.find_by(id: params[:signal_id])
    return redirect_to(issues_super_admin_operations_path, alert: t('super_admin.operations.signal_not_found')) if signal.nil?

    ticket, outcome = Operations::CaseBridge.new(signal).open_case!(actor_email: current_super_admin&.email)
    # On the timeline too, with the operator who clicked: a case appearing out of nowhere in an incident's
    # history is exactly the gap this layer exists to close.
    Operations::SignalLifecycle.new(signal: signal, actor: current_super_admin).record_case(ticket) if outcome == :created
    redirect_to issues_super_admin_operations_path, **flash_for(outcome, ticket)
  end

  private

  # Every operator mutation goes through here, so authorization, the actor, the not-found answer and the
  # invalid-input answer are decided once rather than per action.
  #
  # `current_super_admin` is the actor, passed EXPLICITLY into the lifecycle service. Nothing infers it: the
  # `audited` gem's Sweeper resolves an actor through Devise's `:user` scope while this surface authenticates
  # under `:super_admin`, so an inferred actor would be nil or the wrong person
  # (docs/product-refinement/08-security-performance.md §audit).
  #
  # The signal is looked up by id with no account scoping, which is correct and deliberate on this surface:
  # Operations is installation-wide and an operator works across accounts. The boundary that matters here is
  # `authenticate_super_admin!`, applied by SuperAdmin::ApplicationController to every action, and a request
  # spec asserts that a tenant administrator and a tenant agent both bounce off it.
  def with_signal
    signal = Operations::Signal.find_by(id: params[:id])
    return redirect_to(queue_super_admin_operations_path, alert: t('super_admin.operations.signal_not_found')) if signal.nil?

    changed = yield Operations::SignalLifecycle.new(signal: signal, actor: current_super_admin)
    redirect_to signal_super_admin_operations_path(id: signal.id),
                notice: t(changed ? 'super_admin.operations.signal_updated' : 'super_admin.operations.signal_unchanged')
  rescue Operations::SignalLifecycle::InvalidAction => e
    redirect_to signal_super_admin_operations_path(id: signal&.id), alert: e.message
  end

  # Explicitly listed, so a parameter nobody declared cannot reach a query. The queue validates each value
  # against the model's own allow-lists and ignores anything else.
  def queue_params
    params.permit(:view, :severity, :source, :signal, :account_id, :since_days, :q, :page, :per_page)
  end

  def commerce_params
    params.permit(:view, :page)
  end

  def filtered_signals
    case params[:status]
    when 'resolved' then Operations::Signal.resolved
    when 'all' then Operations::Signal.all
    else Operations::Signal.open_signals
    end
  end

  def flash_for(outcome, ticket)
    case outcome
    when :created then { notice: t('super_admin.operations.case_opened', reference: ticket.reference) }
    when :existing then { notice: t('super_admin.operations.case_exists', reference: ticket.reference) }
    else { alert: t('super_admin.operations.case_no_account') }
    end
  end
end
