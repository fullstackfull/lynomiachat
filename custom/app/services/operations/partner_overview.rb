# EVERY PARTNER INTEGRATION ON THIS INSTALLATION, FOR A LYNOMIA OPERATOR.
#
# WHAT WAS MISSING. Lynomia's Super Admin already administers PlatformApp through Administrate
# -- its name, its token, create and destroy -- and nothing else about it. An operator could
# see that an integration EXISTED and not what it was permitted, which workspaces it held,
# whether any of them was failing, or what it had done lately. The partner's own operators
# could see some of that on their side; Lynomia's could not see it at all, which is the same
# one-sided blindness P6A fixed in the other direction.
#
# AN AGGREGATION OVER WHAT EXISTS, NOT A NEW MODEL. PlatformApp and platform_app_permissibles
# are the authorization model and are read, never widened. The per-installation view is
# Operations::IntegrationHealth -- the very projection the partner reads through the platform
# API -- so an operator here and an operator there are looking at the same facts rather than
# at two renderings that can disagree about the same store.
#
# BOUNDED, because an installation can hold many workspaces. The list is one query plus one
# grouped count; the detail is capped at ACCOUNT_LIMIT accounts and says so when it truncates,
# rather than quietly showing a prefix and letting an operator believe it is the whole set.
class Operations::PartnerOverview
  # How many workspaces one app's detail page reads in full. Each one costs the queries
  # IntegrationHealth makes, so this is the page's real budget rather than a display choice.
  ACCOUNT_LIMIT = 25

  # ---- the list: every integration, and whether any of them needs attention.
  def self.apps
    grants = PlatformAppPermissible.where(permissible_type: 'Account').group(:platform_app_id).count

    PlatformApp.order(:name).map do |app|
      { app: app, accounts: grants.fetch(app.id, 0), open_signals: open_signal_count(app) }
    end
  end

  # Signals are recorded against an ACCOUNT, not against an app, so an app's open count is the
  # count across the accounts it holds. An app holding nothing has nothing to answer for.
  def self.open_signal_count(app)
    account_ids = app.platform_app_permissibles.where(permissible_type: 'Account').pluck(:permissible_id)
    return 0 if account_ids.empty?

    Operations::Signal.open_signals
                      .where(account_id: account_ids, source: Operations::IntegrationHealth::SOURCES)
                      .count
  end

  def initialize(app)
    @app = app
  end

  # ---- the detail: one integration, in full.
  def call
    held = accounts

    {
      app: @app,
      permissions: permissions,
      accounts: held.map { |account| workspace(account) },
      truncated: account_ids.size > ACCOUNT_LIMIT,
      total_accounts: account_ids.size,
      recent_activity: recent_activity
    }
  end

  private

  def account_ids
    @account_ids ||= @app.platform_app_permissibles.where(permissible_type: 'Account').pluck(:permissible_id)
  end

  def accounts
    Account.where(id: account_ids.first(ACCOUNT_LIMIT)).order(:id).to_a
  end

  # WHAT THE APP IS PERMITTED, which is the question the existing screen could not answer.
  # Counted by type rather than listed: a listing of every user an app may sign in as is a
  # roster of people, and an operator asking "what does this integration hold" is not asking
  # for that.
  def permissions
    @app.platform_app_permissibles.group(:permissible_type).count
  end

  # The same projection the partner reads, so the two consoles cannot drift.
  def workspace(account)
    { account: account, health: Operations::IntegrationHealth.new(account, @app).call,
      entitlements: entitlements(account) }
  end

  def entitlements(account)
    PlatformAppEntitlementGrant.where(platform_app_id: @app.id, account_id: account.id)
                               .pluck(:resource, :limit_value).to_h
  end

  # WHAT THE INTEGRATION HAS DONE LATELY. Read from the audit trail rather than from a log,
  # because the audit trail is the record that survives and the one an operator can be held
  # to. Lifecycle transitions a partner asked for carry their own entry
  # (commerce.installation_lifecycle), which is why they appear here at all.
  def recent_activity
    Custom::AuditLog.where(associated_type: 'Account', associated_id: account_ids)
                    .where(comment: ACTIVITY_EVENTS)
                    .order(created_at: :desc)
                    .limit(ACCOUNT_LIMIT)
  end

  ACTIVITY_EVENTS = %w[
    commerce.installation_lifecycle commerce.store_connected commerce.store_disconnected
    commerce.store_disabled commerce.store_enabled commerce.store_needs_reauth
    commerce.credentials_rotated
  ].freeze
end
