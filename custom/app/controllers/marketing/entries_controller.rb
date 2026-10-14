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
    'channels' => { collection: :channels, route: :channel }
  }.freeze

  def show
    scope = SCOPES[params[:scope]]
    return render_marketing_404 if scope.nil?

    @collection = scope[:collection]
    @entry = Marketing::Catalog.find(@collection, params[:slug])
    return render_marketing_404 if @entry.nil?

    @marketing_page = Marketing::Page.new(
      route: scope[:route],
      slug: @entry.slug,
      title: t("marketing.#{@collection}.#{@entry.id}.name"),
      description: t("marketing.#{@collection}.#{@entry.id}.summary")
    )
    render :show
  end
end
