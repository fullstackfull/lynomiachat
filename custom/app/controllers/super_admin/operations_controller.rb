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

  # The one mutation on this page. Opening a case for an issue that already has an active one surfaces that case
  # instead of creating a second, which is what stops an operator generating duplicate case spam from a refresh.
  def open_case
    signal = Operations::Signal.find_by(id: params[:signal_id])
    return redirect_to(issues_super_admin_operations_path, alert: t('super_admin.operations.signal_not_found')) if signal.nil?

    ticket, outcome = Operations::CaseBridge.new(signal).open_case!(actor_email: current_super_admin&.email)
    redirect_to issues_super_admin_operations_path, **flash_for(outcome, ticket)
  end

  private

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
