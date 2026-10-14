# One detail page per catalogue entry: a feature, a channel, an integration or a solution.
#
# ONE CONTROLLER FOR ALL FOUR SCOPES, because the four differ only in which list they look in and which I18n
# branch their copy lives under. Four near-identical controllers would be four places to fix the next time the
# head tags or the 404 behaviour change.
#
# `scope` ARRIVES AS A ROUTE DEFAULT AND IS STILL ALLOWLISTED. It reaches an I18n key and a catalogue lookup,
# and a route default shares the `params` namespace with the query string, so a request for
# `/features/x?scope=anything` must not be able to decide which branch is read. SCOPES is the allowlist, and
# anything outside it 404s before a lookup happens.
#
# AN UNKNOWN SLUG IS A 404, NOT AN EMPTY PAGE. A template that renders with missing translations would put the
# slug in the title and nothing in the body -- a thin page indexed for a term the product does not have, which
# is the opposite of what this site is being rebuilt to do.
class Marketing::EntriesController < Marketing::BaseController
  SCOPES = {
    'features' => { collection: :features, route: :feature },
    'channels' => { collection: :channels, route: :channel },
    'solutions' => { collection: :solutions, route: :solution },
    'integrations' => { collection: :integrations, route: :integration }
  }.freeze

  def show
    scope = SCOPES[params[:scope]]
    return render_marketing_404 if scope.nil?

    @collection = scope[:collection]
    @site_page = SitePage.live.find_by(locale: marketing_locale, kind: @collection.to_s.singularize,
                                       slug: params[:slug])
    return redirect_or_404 if @site_page.nil?

    # The catalogue entry is OPTIONAL. A seeded page has one, and it contributes the availability badge, the
    # prerequisite, the documentation link and the neighbours. A page an operator created at a new slug has
    # none, and renders its own content without inventing a state for it.
    @entry = Marketing::Catalog.find(@collection, params[:slug])

    @marketing_page = Marketing::Page.new(
      route: scope[:route], slug: @site_page.slug,
      title: @site_page.title, description: @site_page.description
    )
    render :show
  end

  private

  # A slug that no longer exists may have been renamed, which is the one thing the CMS can change about a URL
  # -- so this is where SiteRedirect is consulted, and why no catch-all route is needed for it. The redirect
  # is looked up on the request path, so the Arabic and English forms of a renamed page are separate rows and
  # each sends a visitor to its own locale.
  def redirect_or_404
    redirect = SiteRedirect.for_path(request.path)
    return render_marketing_404 if redirect.nil?

    redirect_to redirect.to_path, status: redirect.status, allow_other_host: false
  end
end
