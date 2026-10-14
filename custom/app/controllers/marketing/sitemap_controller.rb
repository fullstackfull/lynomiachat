# The marketing site's sitemap.
#
# ONE SITEMAP FOR BOTH LOCALES, with the Arabic and English versions of a page listed as separate <url>
# entries carrying `xhtml:link` alternates to each other -- which is the arrangement the protocol asks for and
# the one the documentation portal already uses (app/views/public/api/v1/portals/sitemap.xml.erb).
#
# PUBLISHED PAGES ONLY, and that is the whole eligibility rule: `SitePage.live`. A draft answers 404 to a
# visitor, so announcing it would earn a soft-404; a page an operator marked `noindex` is asking not to be
# indexed, so listing it in the sitemap would be the site contradicting itself in two files.
#
# It inherits Marketing::BaseController for one filter: `reject_tenant_custom_domain`. Without it, a tenant's
# Help Center domain would serve Lynomia's marketing sitemap, which is the same boundary D3 draws for the
# pages themselves. The layout is off and `marketing_page` is never read, so the base controller's "rendered
# without a Marketing::Page" guard is not reached.
class Marketing::SitemapController < Marketing::BaseController
  def show
    pages = SitePage.live.where.not(kind: nil).order(:locale, :kind, :position, :key).to_a
    # A page an operator asked search engines to skip is skipped here too.
    @pages = pages.reject(&:noindex?)
    # The published siblings of each page, by identity, so each entry's alternates cost no query.
    @published_locales = @pages.group_by { |page| [page.kind, page.key] }
                               .transform_values { |family| family.map(&:locale) }

    render formats: [:xml], layout: false
  end
end
