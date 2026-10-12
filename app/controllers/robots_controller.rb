# Public crawler rules do not need application authentication or callbacks.
#
# WHAT IS EXCLUDED AND WHY (docs/product-refinement/03-documentation-seo.md). Only the public documentation is
# worth crawling. Everything else on this host either creates data when it loads, needs a session, or is a
# duplicate of a page that is already listed:
#
#   /widget             a widget load CREATES a contact before it renders. Crawling it manufactures contacts.
#   /app, /super_admin  behind a session; a crawler gets a sign-in page and indexes that instead
#   /api                JSON, not a page
#   /hc/*?theme=        the same article again with a query string. The page's own canonical already points at
#                       the clean address, and excluding the parameterised form stops the crawl budget being
#                       spent re-reading it
#
# The Sitemap line names the PLATFORM portal's sitemap by its real slug rather than a guess: a wrong Sitemap
# line is worse than none, because a crawler reports it as an error and stops asking.
class RobotsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  DISALLOWED = ['/widget', '/app/', '/super_admin/', '/api/', '/installation/'].freeze

  def show
    render plain: body, layout: false
  end

  private

  def body
    lines = ['User-agent: *']
    lines += DISALLOWED.map { |path| "Disallow: #{path}" }
    lines << 'Disallow: /hc/*?theme='
    lines += sitemap_lines
    "#{lines.join("\n")}\n"
  end

  # The portals this installation actually serves, read once. A portal with a custom domain has its sitemap on
  # that domain, not this one, so it is listed at its own host.
  def sitemap_lines
    Portal.where(archived: false).map do |portal|
      host = portal.custom_domain.presence || ChatwootApp.help_center_root.to_s
      host = "https://#{host}" unless host.include?('://')
      "Sitemap: #{host.chomp('/')}/hc/#{portal.slug}/sitemap.xml"
    end
  rescue StandardError
    # robots.txt is served before anything else on a cold boot, including a missing or migrating database. A
    # crawler getting the rules without the sitemap hint is fine; a 500 on robots.txt is not.
    []
  end
end
