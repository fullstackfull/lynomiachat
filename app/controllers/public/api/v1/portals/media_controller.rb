# Public delivery for Lynomia documentation media (docs/documentation-v2/R2-MEDIA-CONTRACT.md item 3): an
# app-owned, SAME-ORIGIN route that resolves a `media:` key for a portal and an article, applies the article's own
# visibility predicate and streams the blob.
#
# Never a rails_blob_* redirect and never a signed id in a public page: a signed id is a verifier over the blob
# primary key keyed from secret_key_base, so a committed URL would be valid in exactly one database. Delivery is
# app-owned because every ActiveStorage controller inherits ActiveStorage::BaseController, whose only concerns are
# SetCurrent and protect_from_forgery -- no authentication, no policy call, and no application override adds any.
#
# It inherits PublicController rather than Public::Api::V1::Portals::BaseController, and that is measured rather
# than stylistic. BaseController installs `around_action :set_locale` (base_controller.rb:7,38-43) which, because
# params[:article_slug] is present, runs switch_locale_with_article (`:53-65`) -- an UNSCOPED Article.find_by across
# every portal, plus an unconditional "Article: not found" log line at `:55` that fires even when the article is
# found. On a page with twenty images that is twenty extra cross-portal queries and twenty misleading log lines,
# for a binary endpoint that needs no locale at all. BaseController also adds a four-key GlobalConfig.get per
# request (`:78-80`) and a render_404 that renders the portal's HTML error template (`:71-76`) -- the wrong body
# for an <img> request.
class Public::Api::V1::Portals::MediaController < PublicController
  include Public::PortalArticleVisibility

  # The framework's own streamer, which is what keeps the stored-XSS defence rather than re-deriving it:
  # send_blob_stream sets type from blob.content_type_for_serving and disposition from
  # blob.forced_disposition_for_serving (blob/servable.rb:4-21), the pair that forces image/svg+xml to
  # ActiveStorage.binary_content_type + attachment. Including the concern also inherits this repo's own range
  # hardening, prepended onto ActiveStorage::Streaming at config/initializers/active_storage.rb:27-45,75.
  include ActiveStorage::Streaming

  PUBLISHED_MAX_AGE = 1.hour

  # ensure_custom_domain_request is here for parity of refusal, not for resolution: the article page applies it
  # (articles_controller.rb:2), so an unregistered custom domain gets 401 on the page and must not get 200 on its
  # images. ensure_portal_feature_enabled likewise; on a platform portal it passes, because Portal#feature_enabled?
  # answers from PLATFORM_FEATURES (app/models/portal.rb:193-199 as it was before documentation_media).
  before_action :ensure_custom_domain_request
  before_action :set_portal
  before_action :ensure_portal_feature_enabled
  before_action :set_article

  def show
    image = resolver.resolve(params[:media_key])
    return head :not_found if image.nil?

    apply_cache_headers(image)
    # fresh_when answers 304 and halts for a conditional request, so there is nothing left to stream.
    return if performed?

    send_blob_stream(image.blob, disposition: :inline)
  end

  private

  # find_by plus an explicit 404 rather than find_by!: PublicController does not rescue
  # ActiveRecord::RecordNotFound (app/controllers/concerns/request_exception_handler.rb rescues RecordInvalid and
  # two custom exceptions only), so a raise would make Rails' HTML error page the body of an image request.
  # `||=` and not `=`: ensure_custom_domain_request has already resolved the portal from a REGISTERED custom
  # domain, and the article page keeps that resolution (`@portal ||=`, base_controller.rb:35). Overwriting it
  # from the URL slug made the two routes disagree -- measured on a tenant's custom domain, the page 404s a
  # documentation article while this route served its media. Same public bytes either way, so it was a
  # consistency defect rather than a disclosure, but one evaluation of "which portal" is the point of the
  # shared predicate.
  def set_portal
    @portal ||= Portal.find_by(slug: params[:slug], archived: false)
    head :not_found if @portal.nil?
  end

  # 404 and never 403, for every refusal. A 403 would distinguish "exists but hidden" from "does not exist" --
  # an existence oracle for unpublished content on an unauthenticated endpoint, which is the exact defect the
  # tracking pixel fix closed (articles_controller.rb:35-37).
  def set_article
    @article = visible_articles.find_by(slug: params[:article_slug])
    head :not_found if @article.nil?
  end

  def resolver
    Documentation::MediaResolver.new(portal: @portal, article: @article)
  end

  # A long immutable max-age would be wrong: the URL is not content-addressed, and contract item 8 lets the same
  # key take new bytes, so a year-long cache would serve a replaced screenshot indefinitely. One hour bounds
  # post-deploy staleness and the checksum ETag makes revalidation a 304 with no body.
  def apply_cache_headers(image)
    unless @article.published?
      response.headers['Cache-Control'] = 'private, no-store'
      return
    end

    fresh_when(etag: image.blob.checksum, last_modified: image.blob.created_at, public: true)
    expires_in PUBLISHED_MAX_AGE, public: true
  end
end
