module SuperAdmin::BrandingHelper
  # Administrate derives the page title from the Rails application module name, which is the upstream brand and
  # cannot be renamed without renaming the application itself. Super Admin is an operator surface but still a
  # product surface, so it reads the installation's own name like every other title does.
  #
  # The fallback is Administrate's own answer, written out rather than reached with `super`: this helper is also used
  # by the installation onboarding page and the Super Admin sign-in page, neither of which is an Administrate
  # controller, so there is no superclass method there to call. An installation whose INSTALLATION_NAME has not been
  # seeded yet is exactly when those two pages are read.
  def application_title
    GlobalConfig.get_value('INSTALLATION_NAME').presence || Rails.application.class.module_parent_name.titlecase
  end

  # Mirrors `globalConfig/isACustomBrandedInstance` on the dashboard side, which is the same literal test.
  def custom_branded_instance?
    GlobalConfig.get_value('INSTALLATION_NAME') != 'Chatwoot'
  end

  # Upstream's own support channel is the right destination only on an upstream installation. A branded one gets
  # whatever it configured as SUPPORT_URL, and nil when it configured none, so the caller renders no link.
  def brand_support_url(upstream_url)
    return upstream_url unless custom_branded_instance?

    GlobalConfig.get_value('SUPPORT_URL').presence
  end
end
