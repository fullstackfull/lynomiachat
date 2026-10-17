# == Schema Information
#
# Table name: odoo_destination_profiles
#
# One configured Odoo destination: where Lynomia Chat's own accounting documents are written, and under whose
# company, journal and analytic account (docs/odoo/02-architecture.md §2).
#
# THE ISOLATION ANCHOR. The owner's Odoo holds the books of several unrelated businesses. Every record this
# integration writes names this profile's `source_app`, `environment`, `company_id`, `journal_id` and (when
# configured) `analytic_account_id`, and every lookup is scoped by them. That is what makes it impossible for a
# search to find, adopt or overwrite a record belonging to another project -- see Odoo::SourceStamp.
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

  # What `scope_complete?` requires. The analytic account is deliberately absent: Odoo Community does not ship
  # analytic accounting in every version, so requiring it would make the integration unusable on installations
  # that have no such record to choose.
  REQUIRED_SCOPE = %i[company_id journal_id payment_journal_id].freeze

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

  def connected?
    last_connection_test_at.present? && last_connection_result['ok'] == true
  end

  # A real write was attempted against this destination and Odoo accepted it. A successful login is NOT this:
  # the brief is explicit that 'Test Connection' proves only that credentials authenticate, while creating a
  # draft invoice in the configured journal is the only evidence that invoice creation works.
  def capability_proven?
    last_capability_proof_at.present? && last_capability_proof['ok'] == true
  end

  # The configuration and activation states (the brief, §12). DERIVED, never stored: a stored status is a
  # second source of truth that drifts from the columns it summarises, and every input here is already a
  # column.
  #
  # A TABLE RATHER THAN A CHAIN OF GUARDS, so the order is visible as data and adding a state is one row. It
  # is a FUNNEL: the first check that fails names what an operator has to do next, which is exactly what the
  # Settings screen needs to tell them. Passing every check leaves `:active`; a ninth state, `:not_configured`,
  # has no row to ask and is answered by the class method below.
  CONFIGURATION_FUNNEL = [
    [:credentials_missing, :credentials_present?],
    [:connection_untested, :connection_tested?],
    [:connection_failed, :connected?],
    [:scope_incomplete, :scope_complete?],
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

  # The ninth state has no row: an installation with no profile at all. Asked of the class because there is
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
