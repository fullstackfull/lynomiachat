# Marketing images, served from an app-owned same-origin route.
#
# WHY NOT `/rails/active_storage/...`. Two reasons, and both are recorded in the repository already.
# robots.txt disallows `/rails/` (app/controllers/robots_controller.rb:52, with the reasoning in its header),
# so an ActiveStorage URL is invisible to a crawler -- fatal for `og:image` and for image search. And an
# ActiveStorage signed id is a permanent verifier on this installation, so a blob URL a crawler indexed would
# stay fetchable forever. The documentation side froze an app-owned route for exactly this; this is its
# marketing counterpart.
#
# IT DOES NOT INHERIT Marketing::BaseController, on purpose. That base sets `layout 'marketing'`, resolves a
# locale, exposes a `marketing_page` that RAISES when an action renders without one, and 404s on a tenant
# custom domain -- four behaviours that are all wrong for a binary response. `PublicController` is what
# Public::Api::V1::Portals::MediaController inherits for the same reason.
#
# ONLY AN IMAGE ON A PUBLISHED PAGE. A draft's image is not public, which is the same predicate the page
# itself answers; the lookup joins through site_pages rather than trusting an id.
class Marketing::MediaController < PublicController
  include ActiveStorage::Streaming

  def show
    attachment = published_attachment(params[:id])
    return head :not_found if attachment.nil?

    # A published marketing image is immutable for its id, so it may be cached hard and revalidated by etag.
    fresh_when(etag: attachment.blob.checksum, last_modified: attachment.blob.created_at, public: true)
    return if request.fresh?(response)

    expires_in 1.week, public: true
    # `send_blob_stream` is this repository's hardened path: it carries the range cap installed in
    # config/initializers/active_storage.rb and forces a non-inline disposition for SVG.
    send_blob_stream(attachment.blob, disposition: :inline)
  end

  private

  # `head :not_found` for every miss -- a wrong id, a draft's image, a deleted attachment -- so the response
  # never distinguishes "does not exist" from "not yours to see".
  def published_attachment(id)
    return nil if id.blank? || id.to_s !~ /\A\d+\z/

    ActiveStorage::Attachment
      .where(record_type: 'SitePage', name: 'marketing_images', id: id)
      .where(record_id: SitePage.live.select(:id))
      .includes(:blob)
      .first
  end
end
