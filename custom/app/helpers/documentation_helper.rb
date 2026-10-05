# frozen_string_literal: true

# Lynomia global documentation (docs/global-documentation/11-search-and-locales.md): the view-level pieces the
# documentation portal needs beyond what the shared portal helpers already give it.
module DocumentationHelper
  # The one address an article should be indexed under, whatever query string or layout variant the reader arrived
  # with. Built the same way the sitemap builds its entries -- the portal's own custom domain if it has one, else the
  # installation's help-centre root -- so the canonical and the sitemap can never disagree. Each locale's article has
  # its own slug, so each is its own canonical rather than one pointing at the other.
  def portal_canonical_url(portal, article)
    host = portal.custom_domain.presence || ChatwootApp.help_center_root.to_s
    host = "https://#{host}" unless host.include?('://')
    "#{host.chomp('/')}#{generate_article_link(portal.slug, article.slug, false, false)}"
  end
end
