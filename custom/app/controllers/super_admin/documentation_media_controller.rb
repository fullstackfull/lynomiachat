# frozen_string_literal: true

# Lynomia global documentation: the Super Admin upload path owner correction F1 requires
# (docs/documentation-v2/P2-WORKSTREAM-OWNERSHIP.md section F1, R2-MEDIA-INTERFACE.md section 9.4).
#
# It attaches to the SAME portal.documentation_media namespace, under the SAME `media:` key grammar, resolved by
# the SAME Documentation::MediaResolver as the repository-seeded corpus. Seeded media and operator-uploaded media
# are one abstraction, which is why this controller holds no media logic of its own: it resolves a portal,
# delegates to Documentation::MediaUpload and answers JSON.
#
# The bare ActiveStorage::DirectUploadsController route is NOT relaxed, subclassed around or exempted by this --
# it still answers 403 (config/initializers/active_storage.rb:52-63). These are ordinary Super Admin actions that
# upload server-side, so no anonymous blob creation becomes possible.
#
# SUPER ADMIN ONLY, and there is no tenant counterpart. Authorization is `before_action
# :authenticate_super_admin!` inherited from SuperAdmin::ApplicationController (app/controllers/super_admin/
# application_controller.rb:16) -- the same mechanism as the rest of the documentation Super Admin surface, which
# is why no Pundit policy is involved and why this adds no Portal/Article/Category policy action for the standing
# item-12 rule to need a `false` override against.
#
# Not an Administrate resource controller: what it creates is an ActiveStorage attachment on a portal, not a model
# row an operator browses, so there is no dashboard, no index and no show.
class SuperAdmin::DocumentationMediaController < SuperAdmin::ApplicationController
  rescue_from Documentation::MediaUpload::Error, with: :render_media_error

  before_action :set_portal
  before_action :set_file

  def create
    result = upload.create!(io: @file, filename: @file.original_filename, alt: params[:alt])
    render json: payload(result).merge(markdown: result.markdown), status: :created
  end

  # Same key, new bytes. The reference already in the article keeps working and its alt is untouched, so there is
  # no markdown to return.
  def replace
    result = upload.replace!(key: params[:key].to_s, io: @file, filename: @file.original_filename)
    render json: payload(result), status: :ok
  end

  private

  # Through Documentation::Library.portals (custom/app/services/documentation/library.rb:37-39), so a tenant
  # portal id is a 404 here even for a super admin: the `media:` namespace is per-portal and the two platform
  # portals are the only ones with a documentation corpus.
  def set_portal
    @portal = Documentation::Library.portals.find_by(id: params[:portal_id])
    render json: { error: 'Unknown documentation portal.' }, status: :not_found if @portal.nil?
  end

  # Validated at the request boundary so invalid input is a 422 rather than a NoMethodError in the service
  # (CLAUDE.md). `original_filename` is what distinguishes a real upload from a bare string.
  def set_file
    @file = params[:file]
    return if @file.respond_to?(:original_filename)

    render json: { error: 'A file is required.' }, status: :unprocessable_entity
  end

  def upload
    Documentation::MediaUpload.new(portal: @portal)
  end

  def payload(result)
    { key: result.key, width: result.width, height: result.height, replaced: result.replaced }
  end

  # Every refusal the service raises is a validation failure of the request, so it is a 422 with the service's own
  # message -- which never contains a storage path (contract section 3.2).
  def render_media_error(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end
end
