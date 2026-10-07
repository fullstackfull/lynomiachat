# frozen_string_literal: true

require 'pathname'

module ChatwootApp
  def self.root
    Pathname.new(File.expand_path('..', __dir__))
  end

  def self.max_limit
    100_000
  end

  # Chatwoot Enterprise is not part of this codebase. The predicate is kept, rather than deleted, because it is
  # the single point that keeps every upstream enterprise? guard inert: roughly forty callers read it, six of them
  # already-applied migrations in db/migrate whose bodies name Captain:: constants that no longer exist, and
  # app/helpers/super_admin/features.yml interpolates it through ERB. One `false` here is what makes all of them
  # safe; deleting the method would mean rewriting applied migration history.
  def self.enterprise?
    false
  end

  def self.chatwoot_cloud?
    enterprise? && GlobalConfig.get_value('DEPLOYMENT_ENV') == 'cloud'
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

  # The extensions asked for at every prepend_mod_with / include_mod_with site. Lynomia is the only overlay, so
  # this is ['custom'] on any install that has the directory, and a `super` from Custom:: reaches the OSS
  # implementation directly.
  def self.extensions
    custom? ? ['custom'] : []
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
