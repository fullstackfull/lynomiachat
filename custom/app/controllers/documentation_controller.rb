# Lynomia global documentation: the stable public entry points, /docs and /changelog.
#
# They redirect into the Help Center's own public renderer rather than duplicating it, so the documentation gets the
# existing layouts, locale handling, search and SEO for free, and the address survives a slug change. The locale is
# left to the portal's own redirect (public/api/v1/portals_controller.rb#redirect_to_portal_with_locale), which is
# already the one place that decides it.
class DocumentationController < ApplicationController
  def show
    redirect_to_portal(Documentation::Library.docs_portal)
  end

  def changelog
    redirect_to_portal(Documentation::Library.changelog_portal)
  end

  private

  def redirect_to_portal(portal)
    return render_not_set_up if portal.blank?

    redirect_to "/hc/#{portal.slug}", allow_other_host: false
  end

  def render_not_set_up
    render plain: I18n.t('documentation.not_set_up'), status: :not_found
  end
end
