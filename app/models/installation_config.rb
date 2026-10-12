# == Schema Information
#
# Table name: installation_configs
#
#  id               :bigint           not null, primary key
#  locked           :boolean          default(TRUE), not null
#  name             :string           not null
#  serialized_value :jsonb            not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_installation_configs_on_name                 (name) UNIQUE
#  index_installation_configs_on_name_and_created_at  (name,created_at) UNIQUE
#
class InstallationConfig < ApplicationRecord
  CAPTAIN_LLM_CONFIG_KEYS = %w[
    CAPTAIN_OPEN_AI_API_KEY
    CAPTAIN_OPEN_AI_ENDPOINT
    CAPTAIN_OPEN_AI_MODEL
  ].freeze

  RESTART_REQUIRED_CONFIG_KEYS = (CAPTAIN_LLM_CONFIG_KEYS + %w[
    LANGFUSE_BASE_URL
    LANGFUSE_PUBLIC_KEY
    LANGFUSE_SECRET_KEY
    OTEL_PROVIDER
  ]).freeze

  # A key that ONCE held a secret still holds one. ConfigLoader never deletes a row (lib/config_loader.rb:40-55),
  # so retiring a feature removes its declaration from config/installation_config.yml while the stored value stays
  # in the database -- and the declaration was the only reason this installation had to treat that value as a
  # secret. Without this list the generic Installation Configs page lists the stale row like any other config,
  # with its value, which is how the retired Shopify partner credentials became readable (merge gate §V1).
  #
  # DELIBERATELY NOT A TOMBSTONE DECLARATION back in the YAML: ConfigLoader CREATES a row for every declaration it
  # reads, and with `reconcile_only_new: false` it overwrites an existing value with the declaration's default, so
  # a tombstone would either resurrect the key as configuration or destroy the value it was meant to protect.
  #
  # Nothing is added here to re-enable a feature; a name only ever moves INTO this list, when its declaration goes.
  RETIRED_SECRET_NAMES = %w[
    SHOPIFY_CLIENT_ID
    SHOPIFY_CLIENT_SECRET
    SHOPIFY_PARTNER_ACCESS_TOKEN
  ].freeze

  # https://stackoverflow.com/questions/72970170/upgrading-to-rails-6-1-6-1-causes-psychdisallowedclass-tried-to-load-unspecif
  # https://discuss.rubyonrails.org/t/cve-2022-32224-possible-rce-escalation-bug-with-serialized-columns-in-active-record/81017
  # FIX ME : fixes breakage of installation config. we need to migrate.
  # Fix configuration in application.rb
  serialize :serialized_value, coder: YAML, type: ActiveSupport::HashWithIndifferentAccess, default: {}.with_indifferent_access

  before_validation :set_lock
  validates :name, presence: true
  validate :saml_sso_users_check, if: -> { name == 'ENABLE_SAML_SSO_LOGIN' }

  # TODO: Get rid of default scope
  # https://stackoverflow.com/a/1834250/939299
  default_scope { order(created_at: :desc) }
  scope :editable, -> { where(locked: false) }

  after_commit :clear_cache

  # Lynomia: configs typed `secret` in config/installation_config.yml are write-only in Super Admin, plus the
  # keys whose declaration a retired feature took with it (RETIRED_SECRET_NAMES). This is the one place secret
  # classification is decided, so every reader of it -- the Installation Configs listing, which uses it to
  # exclude rows from `index`, `show`, `edit` and `update` alike, and App configs' keep-stored-secrets filter --
  # inherits the historical names without a redaction check of its own.
  def self.secret_names
    declared = ConfigLoader.new.general_configs.filter_map { |config| config['name'] if config['type'] == 'secret' }
    declared | RETIRED_SECRET_NAMES
  end

  def value
    serialized_value[:value]
  end

  def value=(value_to_assigned)
    self.serialized_value = {
      value: value_to_assigned
    }.with_indifferent_access
  end

  private

  def set_lock
    self.locked = true if locked.nil?
  end

  def clear_cache
    GlobalConfig.clear_cache
  end

  def saml_sso_users_check
    return unless value == false || value == 'false'
    return unless User.exists?(provider: 'saml')

    errors.add(:base, 'Cannot disable SAML SSO login while users are using SAML authentication')
  end
end
