# == Schema Information
#
# Table name: odoo_destination_profiles
#
# One configured Odoo destination: where Lynomia Chat's own accounting documents are written, and under whose
# company, journal and analytic account (docs/odoo/02-architecture.md §2).
#
# ONE COMPANY, SEVERAL PROJECTS. The owner's Odoo holds ONE legal company, inside which several unrelated
# business projects operate. So this profile carries two different kinds of setting and they must not be
# confused:
#
#   WHERE documents are written -- `company_id`, `journal_id`, `payment_journal_id`. A sibling project writes
#     into the same company and may use the same journal, so these identify a destination and nothing else.
#   WHOSE they are, and whose revenue   -- `source_app` + `environment` (the stamp in Odoo's `ref`, which is
#     what makes a record ours) and the attribution columns below (`attribution_mode` with
#     `analytic_account_id` or `income_account_id`, which is what segregates this project's revenue in Odoo's
#     own reports). See Odoo::SourceStamp and Odoo::Attribution.
#
# An earlier version of this file said the company was the isolation anchor. It is not, and could not be, for
# this installation.
#
# CREDENTIALS ARE ENCRYPTED AT REST, following Commerce::Store rather than Billing::Settings. Billing's Stripe
# keys live in `installation_configs` rows marked `locked`, which hides them from the generic config page but
# does not encrypt them. The brief requires encryption, so the API key lives in an Active Record encrypted
# column and the record refuses to save without encryption keys configured.
class Odoo::DestinationProfile < ApplicationRecord
  # The `Odoo` module carries no table_name_prefix, so Rails would look for `destination_profiles`. Named
  # explicitly, the same way Commerce::Store and Operations::Signal do.
  self.table_name = 'odoo_destination_profiles'

  # The only app this installation exports as. A column rather than a constant inlined at every write, because
  # it is half of the isolation stamp and a stamp that is not stored cannot be searched on.
  SOURCE_APP = 'LYNOMIA_CHAT'.freeze
  ENVIRONMENTS = %w[live test].freeze

  # Odoo's JSON transports. `json2` is the newer External API; `jsonrpc` is the long-standing `/jsonrpc`
  # endpoint. There is no XML-RPC option: `xmlrpc` is not in this bundle (docs/odoo/00-discovery.md §9).
  TRANSPORTS = %w[json2 jsonrpc].freeze

  # Where documents go. Required before anything can be written, because an export with no journal has nowhere
  # to land.
  REQUIRED_SCOPE = %i[company_id journal_id payment_journal_id].freeze

  # The probe that proves this project's revenue can actually be attributed on this server. Named here because
  # `capability_proven?` requires it BY NAME: a stored proof that predates the attribution probe, or one in
  # which that probe was skipped, is not proof that attribution works, and treating it as proof is how
  # unattributed revenue would reach a shared company's books.
  ATTRIBUTION_PROBE = 'attribution'.freeze

  has_many :customer_mappings, class_name: 'Odoo::CustomerMapping', dependent: :destroy,
                               foreign_key: :odoo_destination_profile_id, inverse_of: :destination_profile
  has_many :document_mappings, class_name: 'Odoo::DocumentMapping', dependent: :destroy,
                               foreign_key: :odoo_destination_profile_id, inverse_of: :destination_profile
  has_many :sync_events, class_name: 'Odoo::SyncEvent', dependent: :destroy,
                         foreign_key: :odoo_destination_profile_id, inverse_of: :destination_profile

  serialize :credentials, coder: JSON
  encrypts :credentials

  validates :name, :base_url, :database, :username, presence: true
  validates :name, uniqueness: true
  validates :environment, inclusion: { in: ENVIRONMENTS }
  validates :source_app, inclusion: { in: [SOURCE_APP] }
  validates :transport, inclusion: { in: TRANSPORTS }, allow_nil: true
  validates :attribution_mode, inclusion: { in: Odoo::Attribution::MODES }
  validate :base_url_usable
  validate :credentials_encryptable, if: -> { credentials.present? }

  scope :enabled, -> { where(sync_enabled: true) }

  # The destination a sync runs against. There is at most one by construction:
  # `uniq_enabled_odoo_destination_per_environment` is a partial unique index on (source_app, environment)
  # where sync_enabled, so two enabled profiles cannot exist to post an invoice twice.
  def self.active(environment: Rails.env.production? ? 'live' : 'test')
    enabled.find_by(source_app: SOURCE_APP, environment: environment)
  end

  def api_key
    credentials.is_a?(Hash) ? credentials['api_key'].presence : nil
  end

  # BLANK PRESERVES THE STORED VALUE, the same rule as Billing::Settings#update!: an operator editing the
  # journal must not have to re-paste the API key, and a form that submits an empty password field must not
  # erase one. Clearing the key is a separate, deliberate act (#clear_api_key!).
  def api_key=(value)
    return if value.blank?

    self.credentials = (credentials.presence || {}).merge('api_key' => value.to_s.strip)
  end

  def clear_api_key!
    update!(credentials: (credentials.presence || {}).except('api_key'))
  end

  # Never the key, and never its length either -- see Billing::Settings.mask.
  def masked_api_key
    Billing::Settings.mask(api_key)
  end

  # Belt and braces for every serializer, API response and `render json:` on this surface. The credential has
  # no caller outside the adapter, so the cheapest guarantee is that it is not in the hash at all.
  def serializable_hash(options = nil)
    super.except('credentials')
  end

  def credentials_present?
    api_key.present?
  end

  def scope_complete?
    REQUIRED_SCOPE.all? { |attribute| self[attribute].present? }
  end

  def attribution
    @attribution ||= Odoo::Attribution.new(self)
  end

  # Is the chosen attribution mechanism configured at all? A separate funnel state from `scope_incomplete`
  # because it is a different thing to fix and a different screen section to go to -- and because attribution
  # is the requirement a shared company adds, so an operator who has only ever configured a journal needs to
  # be told about it by name.
  def attribution_configured?
    attribution.configured?
  end

  # What the Settings and Overview screens say about attribution. Derived from the stored proof, so it reports
  # what was established against the real server rather than what was typed into a form.
  def attribution_state
    return :not_configured unless attribution_configured?
    return :unproven if last_capability_proof_at.blank?

    last_capability_proof.dig('probes', ATTRIBUTION_PROBE, 'ok') == true ? :proven : :unsupported
  end

  def connected?
    last_connection_test_at.present? && last_connection_result['ok'] == true
  end

  # A real write was attempted against this destination and Odoo accepted it. A successful login is NOT this:
  # 'Test Connection' proves only that credentials authenticate, while creating a draft invoice in the
  # configured journal is the only evidence that invoice creation works.
  #
  # THE ATTRIBUTION PROBE IS REQUIRED BY NAME, not merely counted in the proof's own `ok`. `probe_capability`
  # computes that flag as "every probe passed or was skipped", so a skipped attribution probe would leave a
  # destination that writes revenue nobody can attribute looking fully proven. Naming it here means the only
  # way to be proven is for attribution to have been established on this server.
  def capability_proven?
    last_capability_proof_at.present? && last_capability_proof['ok'] == true &&
      last_capability_proof.dig('probes', ATTRIBUTION_PROBE, 'ok') == true
  end

  # The configuration and activation states (the brief, §12). DERIVED, never stored: a stored status is a
  # second source of truth that drifts from the columns it summarises, and every input here is already a
  # column.
  #
  # A TABLE RATHER THAN A CHAIN OF GUARDS, so the order is visible as data and adding a state is one row. It
  # is a FUNNEL: the first check that fails names what an operator has to do next, which is exactly what the
  # Settings screen needs to tell them. Passing every check leaves `:active`; a tenth state, `:not_configured`,
  # has no row to ask and is answered by the class method below.
  CONFIGURATION_FUNNEL = [
    [:credentials_missing, :credentials_present?],
    [:connection_untested, :connection_tested?],
    [:connection_failed, :connected?],
    [:scope_incomplete, :scope_complete?],
    [:attribution_incomplete, :attribution_configured?],
    [:capability_unproven, :capability_proven?],
    [:error, :unblocked?],
    [:ready_disabled, :sync_enabled?]
  ].freeze

  def status
    CONFIGURATION_FUNNEL.each { |state, check| return state unless public_send(check) }

    :active
  end

  def connection_tested?
    last_connection_test_at.present?
  end

  def unblocked?
    blocked_reason.blank?
  end

  # The tenth state has no row: an installation with no profile at all. Asked of the class because there is
  # nothing to ask it of.
  def self.status
    exists? ? :configured : :not_configured
  end

  # What a document write is allowed to do, over and above creating a draft. Both default to false and both
  # require the capability proof, so enabling posting on a destination that has never accepted a write is not
  # a thing an operator can do by ticking a box.
  def may_post?
    post_invoices? && capability_proven?
  end

  def may_register_payments?
    register_payments? && may_post?
  end

  private

  # Format only. The connection is separately SSRF-checked at the moment it is opened
  # (Odoo::Transport::Client), because a hostname that resolves to a public address at validation time can
  # resolve to 169.254.169.254 by the time anybody connects to it.
  def base_url_usable
    return if base_url.blank?

    uri = URI.parse(base_url)
    errors.add(:base_url, :must_be_https) unless uri.scheme == 'https'
    errors.add(:base_url, :must_have_host) if uri.host.blank?
    # Userinfo in the URL would put a credential into a column that is not encrypted, and into every log line
    # that prints the base URL.
    errors.add(:base_url, :must_not_carry_credentials) if uri.userinfo.present?
  rescue URI::InvalidURIError
    errors.add(:base_url, :invalid)
  end

  # Credentials are never stored in plaintext: without Active Record encryption keys the profile cannot be
  # saved. The same guarantee, and the same wording, as Commerce::Store.
  def credentials_encryptable
    errors.add(:credentials, :encryption_not_configured) unless Chatwoot.encryption_configured?
  end
end
