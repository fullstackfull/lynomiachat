# frozen_string_literal: true

require 'pathname'

module ChatwootApp
  def self.root
    Pathname.new(File.expand_path('..', __dir__))
  end

  def self.max_limit
    100_000
  end

  def self.enterprise?
    return if ENV.fetch('DISABLE_ENTERPRISE', false)

    @enterprise ||= root.join('enterprise').exist?
  end

  def self.chatwoot_cloud?
    enterprise? && GlobalConfig.get_value('DEPLOYMENT_ENV') == 'cloud'
  end

  def self.self_hosted_enterprise?
    enterprise? && !chatwoot_cloud? && GlobalConfig.get_value('INSTALLATION_PRICING_PLAN') == 'enterprise'
  end

  def self.self_hosted_paid?
    enterprise? && !chatwoot_cloud? && %w[premium enterprise].include?(ChatwootHub.pricing_plan)
  end

  def self.custom?
    @custom ||= root.join('custom').exist?
  end

  def self.help_center_root
    ENV.fetch('HELPCENTER_URL', nil) || ENV.fetch('FRONTEND_URL', nil)
  end

  # Derived from what is actually on disk, in injection order: an extension listed here is asked for at every
  # prepend_mod_with / include_mod_with site, so listing one that is absent made every site rely on
  # const_get_maybe_false returning false (config/initializers/01_inject_enterprise_edition_module.rb:78).
  # Order matters and is preserved: `custom` is applied last, so Custom:: sits ahead of Enterprise:: in the
  # ancestor chain and a `super` from Custom:: reaches Enterprise:: while it is installed.
  def self.extensions
    extensions = []
    extensions << 'enterprise' if enterprise?
    extensions << 'custom' if custom?
    extensions
  end

  def self.advanced_search_allowed?
    enterprise? && ENV.fetch('OPENSEARCH_URL', nil).present?
  end

  def self.otel_enabled?
    otel_provider = InstallationConfig.find_by(name: 'OTEL_PROVIDER')&.value
    secret_key = InstallationConfig.find_by(name: 'LANGFUSE_SECRET_KEY')&.value

    otel_provider.present? && secret_key.present? && otel_provider == 'langfuse'
  end
end
