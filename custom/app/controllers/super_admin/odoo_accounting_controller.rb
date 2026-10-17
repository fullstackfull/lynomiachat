# Super Admin -> Accounting Integrations -> Odoo (the brief, §2 and §11).
#
# Server-rendered ERB inside the Administrate shell with Tailwind, following SuperAdmin::OperationsController
# and SuperAdmin::MarketingSettingsController: one controller, one action per tab, no Vue island. Nothing on
# these pages needs client state a form and a link cannot express.
#
# AUTHORIZATION is `authenticate_super_admin!`, applied by SuperAdmin::ApplicationController to every action.
# That is the whole boundary on this surface and this controller does not invent a second one. CSRF comes from
# ApplicationController's `protect_from_forgery`, so every write is a POST or PATCH form carrying the Rails
# token -- including Test Connection and the capability probe, because neither is something a pasted link
# should be able to trigger.
#
# NO SECRET IS EVER RENDERED. The views read `masked_api_key`, and `Odoo::DestinationProfile#serializable_hash`
# drops `credentials` outright, so a template that reached for the record wholesale would still not get it.
#
# THE NAV EXCLUSION IS NOT OPTIONAL. `app/views/super_admin/application/_navigation.html.erb` enumerates every
# controller under `super_admin/` and asks each for an index route and a dashboard; one with neither raises,
# and the raise breaks the nav on EVERY Super Admin page. This controller is excluded by name there, in the
# same commit as its route.
class SuperAdmin::OdooAccountingController < SuperAdmin::ApplicationController
  PAGE_SIZE = 50
  # How far back an import preview may reach in one go. Not a policy about accounting history -- it is the
  # window the operator picks -- but a bound on one request, so a mistyped year cannot hold a worker open.
  MAX_IMPORT_WINDOW = 400.days

  before_action :load_profile

  # ---- reads

  def show
    @overview = overview
  end

  def settings; end

  def customers
    @mappings = scoped(from_profile(:customer_mappings) { |r| r.includes(:account).recent_first })
  end

  def invoices
    @mappings = scoped(from_profile(:document_mappings) { |r| r.invoices.recent_first })
  end

  def transactions
    @mappings = scoped(from_profile(:document_mappings) { |r| r.transactions.recent_first })
  end

  def history
    @events = scoped(from_profile(:sync_events) { |r| r.includes(:account).recent_first })
  end

  # The one page that is only ever interested in rows that are not fine, which is why the tables carry a
  # partial index for exactly this predicate.
  def errors
    @events = scoped(from_profile(:sync_events) { |r| r.unhealthy.includes(:account).recent_first })
    @documents = scoped(from_profile(:document_mappings) { |r| r.unhealthy.recent_first })
    @customers = scoped(from_profile(:customer_mappings) { |r| r.unhealthy.recent_first })
  end

  # READ ONLY. It shows what the last connection test and the last capability probe found; running either is a
  # POST below.
  def diagnostics; end

  def import
    @preview = nil
    return if @profile.nil? || params[:from].blank?

    @window = import_window
    @preview = Odoo::HistoricalImport.new(@profile).preview(from: @window.first, to: @window.last)
  rescue Odoo::StripeSource::NotConfigured
    flash.now[:error] = t('super_admin.odoo.flash.stripe_not_configured')
  end

  # ---- writes

  def update_settings
    settings_service.update!(settings_params)
    redirect_to settings_super_admin_odoo_accounting_path, notice: t('super_admin.odoo.flash.saved')
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_super_admin_odoo_accounting_path, alert: e.record.errors.full_messages.to_sentence
  end

  def clear_api_key
    settings_service.clear_api_key!
    redirect_to settings_super_admin_odoo_accounting_path, notice: t('super_admin.odoo.flash.key_cleared')
  end

  # Proves a credential and nothing more, and the page says so. Separate from the capability probe on purpose:
  # the brief's point is that these are different questions with different answers.
  def test_connection
    result = Odoo::Diagnostics.new(@profile).test_connection
    settings_service.record_connection_test(result)
    redirect_to diagnostics_super_admin_odoo_accounting_path, **flash_for(result['ok'], 'connection')
  end

  def run_capability_probe
    result = Odoo::Diagnostics.new(@profile).probe_capability
    settings_service.record_capability_proof(result)
    redirect_to diagnostics_super_admin_odoo_accounting_path, **flash_for(result['ok'], 'capability')
  end

  def enable
    settings_service.enable!
    redirect_to super_admin_odoo_accounting_path, notice: t('super_admin.odoo.flash.enabled')
  rescue Odoo::AdminSettings::Error
    redirect_to diagnostics_super_admin_odoo_accounting_path, alert: t('super_admin.odoo.flash.not_ready')
  end

  def disable
    settings_service.disable!(reason: params[:reason])
    redirect_to super_admin_odoo_accounting_path, notice: t('super_admin.odoo.flash.disabled')
  end

  # Enqueues; it does not import inside the request. The count in the flash is what was newly queued, so
  # pressing it twice reports zero the second time rather than doubling anything.
  def start_import
    window = import_window
    queued = Odoo::HistoricalImport.new(@profile).confirm!(from: window.first, to: window.last)
    redirect_to history_super_admin_odoo_accounting_path, notice: t('super_admin.odoo.flash.import_queued', count: queued)
  rescue Odoo::StripeSource::NotConfigured
    redirect_to import_super_admin_odoo_accounting_path, alert: t('super_admin.odoo.flash.stripe_not_configured')
  end

  # Brings one row's next attempt forward. It does not reset the attempt count: an operator retrying something
  # five times should still be able to see that it has been tried five times.
  def retry_event
    event = @profile&.sync_events&.find_by(id: params[:id])
    return redirect_to(errors_super_admin_odoo_accounting_path, alert: t('super_admin.odoo.flash.event_not_found')) if event.nil?

    event.update!(state: :pending, run_after: nil, claimed_at: nil, blocked_reason: nil)
    Odoo::SyncJob.perform_later(event.id)
    redirect_to errors_super_admin_odoo_accounting_path, notice: t('super_admin.odoo.flash.event_requeued')
  end

  private

  # There is at most one destination, and `find_or_initialize` would make an empty row the moment somebody
  # opened the page. So a missing profile stays missing and every view handles it: `not_configured` is one of
  # the nine states and the most important one to show honestly.
  def load_profile
    @profile = Odoo::DestinationProfile.order(:id).first
  end

  def settings_service
    @profile ||= Odoo::DestinationProfile.new(source_app: Odoo::DestinationProfile::SOURCE_APP, environment: 'test')
    Odoo::AdminSettings.new(@profile, actor: current_super_admin)
  end

  # Explicitly listed, so a parameter nobody declared cannot reach the record. Odoo::AdminSettings slices it
  # again against its own allow-list: the controller boundary and the writer each state what they accept,
  # because either one could acquire a second caller.
  def settings_params
    params.permit(*Odoo::AdminSettings::PERMITTED, :api_key)
  end

  # Every list page asks the profile for a relation, and there may be no profile. Handled ONCE here rather
  # than with `&.` chains per action: no destination means an empty relation, and each view's empty state says
  # why rather than showing a blank table.
  def from_profile(association)
    return nil if @profile.nil?

    yield @profile.public_send(association)
  end

  def scoped(relation)
    (relation || Odoo::SyncEvent.none).page(params[:page]).per(PAGE_SIZE)
  end

  # Clamped at both ends: `to` never in the future, and the window never wider than MAX_IMPORT_WINDOW.
  def import_window
    from = parse_date(params[:from], 30.days.ago.to_date).beginning_of_day
    to = parse_date(params[:to], Date.current).end_of_day
    to = Time.current if to > Time.current
    from = to - MAX_IMPORT_WINDOW if (to - from) > MAX_IMPORT_WINDOW
    [from, to]
  end

  # An unparseable date is an operator typo, not an exception: the form comes back with the default window
  # rather than a 500, and the page shows which window it actually used.
  def parse_date(value, fallback)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    fallback
  end

  def overview
    return { status: Odoo::DestinationProfile.status, queue: {}, documents: {}, customers: {} } if @profile.nil?

    { status: @profile.status,
      queue: @profile.sync_events.group(:state).count,
      documents: @profile.document_mappings.group(:state).count,
      customers: @profile.customer_mappings.group(:state).count,
      last_synchronized_at: @profile.document_mappings.maximum(:last_synced_at) }
  end

  def flash_for(success, kind)
    message = t("super_admin.odoo.flash.#{kind}_#{success ? 'ok' : 'failed'}")
    success ? { notice: message } : { alert: message }
  end
end
