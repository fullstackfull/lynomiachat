# Public crawler rules do not need application authentication or callbacks.
#
# WHAT IS EXCLUDED AND WHY (docs/product-refinement/03-documentation-seo.md). Only the public documentation is
# worth crawling. Everything else on this host either creates data when it loads, needs a session, or is a
# duplicate of a page that is already listed:
#
#   /widget             a widget load CREATES a contact before it renders. Crawling it manufactures contacts.
#   /app, /super_admin  behind a session; a crawler gets a sign-in page and indexes that instead
#   /api                JSON, not a page
#   /rails              every path Rails mounts here is framework internal, not a page. ActiveStorage's own
#                       controllers are the live ones (`/rails/active_storage/blobs/redirect/...`,
#                       `/representations/...`, `/disk/...`) and they stream bytes. Documentation media is
#                       NOT served from here -- R2-MEDIA-CONTRACT.md item 3 freezes an app-owned, same-origin
#                       route and forbids a `rails_blob_*` redirect -- so excluding this costs the
#                       documentation nothing. What it saves: an ActiveStorage signed id is a permanent
#                       verifier (`urls_expire_in` is nil, R2-MEDIA-CONTRACT.md §3), so a blob URL a crawler
#                       indexes stays fetchable forever, and the one representation these pages can produce is
#                       an author avatar -- a colleague's face on a tenant Help Center. This is a crawl rule,
#                       not an access control: authorization for media is the delivery predicate on the
#                       app-owned route, which is where it belongs.
#   /hc/*?theme=        the same article again with a query string. The page's own canonical already points at
#                       the clean address, and excluding the parameterised form stops the crawl budget being
#                       spent re-reading it
#   /hc/*?show_plain_layout=
#                       the same again, and worse: `Public::Api::V1::Portals::BaseController` switches to the
#                       `plain` variant for any portal when this is `true`, and that variant's head
#                       (`articles/_meta_head.html.erb`) emits NO canonical, no hreflang and no structured
#                       data. So it is a canonical-less mirror of the whole portal rather than a styled
#                       duplicate -- and `portal/portalHelpers.js#appendPlainParamToURLs` rewrites every
#                       in-page `/hc/` link to carry the parameter, so one crawlable plain URL yields a
#                       complete second copy of the portal in one hop
#                       (discovery/098-attack-seo-indexability.md R7)
#   /hc/*/search        a search results page. It carries no canonical, its content is another page's content,
#                       and `?query=` is unbounded -- infinite crawl space whose best outcome is an indexed
#                       "No results found for ..."
#   /hc/*/articles/*.png
#                       the view-count tracking pixel (`articles#tracking_pixel`), which calls
#                       `Article#increment_view_count` before it answers. Crawling it manufactures view counts
#                       for the same reason crawling `/widget` manufactures contacts
#
# NOT EXCLUDED, deliberately: `/hc/:slug/articles/:slug.md` (`articles#show_markdown`). It is a near-duplicate
# of the HTML page and it carries no canonical, so the SEO instinct is to block it -- but it exists to be read
# by machines, and `robots.txt` cannot exclude a search crawler without also excluding those. The duplicate is
# better answered by a `Link: <canonical>; rel="canonical"` header on that response, which belongs to
# `articles_controller.rb`. Recorded in the Agent 4 wave-2 report rather than solved here.
#
# The Sitemap line names the PLATFORM portal's sitemap by its real slug rather than a guess: a wrong Sitemap
# line is worse than none, because a crawler reports it as an error and stops asking.
class RobotsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  include DocumentationHelper

  DISALLOWED = ['/widget', '/app/', '/super_admin/', '/api/', '/installation/', '/rails/'].freeze
  DISALLOWED_PATTERNS = ['/hc/*?theme=', '/hc/*?show_plain_layout=', '/hc/*/search', '/hc/*/articles/*.png'].freeze

  def show
    render plain: body, layout: false
  end

  private

  def body
    lines = ['User-agent: *']
    lines += DISALLOWED.map { |path| "Disallow: #{path}" }
    lines += DISALLOWED_PATTERNS.map { |pattern| "Disallow: #{pattern}" }
    lines += sitemap_lines
    "#{lines.join("\n")}\n"
  end

  # The portals this installation actually serves, read once. A portal with a custom domain has its sitemap on
  # that domain, not this one, so it is listed at its own host.
  #
  # The host comes from `DocumentationHelper#portal_public_host`, which is the same method the canonical, the
  # hreflang set and the sitemap's own `<loc>` use. It used to be a second copy of that arithmetic here, and
  # it carried the same blank-host bug -- `Sitemap: https://hc/hc/lynomia-docs/sitemap.xml`, advertising a
  # hostname that does not exist (discovery/098-attack-seo-indexability.md R4). A portal whose host cannot be
  # resolved is now left out: a `Sitemap:` line must be absolute, and a wrong one is worse than none.
  def sitemap_lines
    Portal.where(archived: false).filter_map do |portal|
      host = portal_public_host(portal)
      next if host.blank?

      "Sitemap: #{host}/hc/#{portal.slug}/sitemap.xml"
    end
  rescue StandardError
    # robots.txt is served before anything else on a cold boot, including a missing or migrating database. A
    # crawler getting the rules without the sitemap hint is fine; a 500 on robots.txt is not.
    []
  end
end
