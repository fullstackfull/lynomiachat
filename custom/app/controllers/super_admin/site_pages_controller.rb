# The pages of the official website.
#
# THE CMS TRULY CONTROLS THE RENDERED WEBSITE, which is the owner's requirement and is a property of the
# architecture rather than of this controller: Marketing::PagesController and Marketing::EntriesController
# read `site_pages` and nothing else, with no fallback to a locale file. So an edit saved here is what the
# next visitor reads, and a page with no published row is a 404 rather than a stale template -- which is why
# `rake marketing:verify` exists and belongs in the deploy.
#
# WHAT THIS CONTROLLER ADDS to Administrate's defaults:
#   * `scoped_resource` orders by locale, kind and the operator's position, which is the order the public
#     index pages render in;
#   * `publish` and `unpublish`, because a status transition is a decision and deserves a button rather than
#     a dropdown buried in a form;
#   * `preview`, which sends the operator to the REAL public page in the REAL layout before it is published;
#   * `upload_image` and `destroy_image`, which are separate from the edit form on purpose -- an upload that
#     fails must not take an operator's unsaved prose with it;
#   * an audit entry on every successful save, publish and unpublish.
#
# AUTHORIZATION is `authenticate_super_admin!`, applied by SuperAdmin::ApplicationController to every action
# including the four added here. Each mutation is a POST or a DELETE, so none of them is reachable by a link.
class SuperAdmin::SitePagesController < SuperAdmin::ApplicationController
  rescue_from Marketing::ImageUpload::Error, with: :redirect_with_upload_error

  def publish
    transition(:published, 'published')
  end

  def unpublish
    transition(:draft, 'unpublished')
  end

  # The real page, in the real layout, before it is published. `?preview=1` is honoured for a signed-in super
  # admin only (Marketing::BaseController#find_site_page), and the head of a page that is not published
  # already carries `noindex`, so a preview URL that leaks is not an indexable draft.
  def preview
    path = requested_resource.public_path(preview: true)
    if path.nil?
      return redirect_to([:super_admin, requested_resource],
                         alert: t('super_admin.site_pages.no_public_address'))
    end

    redirect_to path, allow_other_host: false
  end

  # `try` on the filename rather than a presence check on the parameter: a POST with no file, or with a bare
  # string where a file was expected, is a malformed request and the upload service refuses it with the
  # message an operator can act on. One refusal path, in the service that owns the rule.
  def upload_image
    page = requested_resource
    file = params[:file]
    attachment = Marketing::ImageUpload.new(page: page).attach!(io: file, filename: file.try(:original_filename))
    redirect_to [:super_admin, page], notice: t('super_admin.site_pages.image_uploaded', id: attachment.id)
  end

  def destroy_image
    page = requested_resource
    attachment = page.marketing_images.find_by(id: params[:attachment_id])
    return redirect_to([:super_admin, page], alert: t('super_admin.site_pages.image_missing')) if attachment.nil?

    attachment.purge_later
    redirect_to [:super_admin, page], notice: t('super_admin.site_pages.image_removed')
  end

  private

  def scoped_resource
    super.order(:locale, :kind, :position, :key)
  end

  # The form posts an index-keyed hash whose rows carry the editor's own controls; Marketing::SectionsInput
  # turns it back into the ordered array the model stores, and the model's `normalizes` then runs it through
  # Marketing::SectionSchema.coerce. Three narrowings, each with its own reason.
  def resource_params
    super.tap do |permitted|
      permitted[:sections] = Marketing::SectionsInput.new(permitted[:sections]).sections if permitted.key?(:sections)
    end
  end

  # Administrate's post-save hooks. They fire only on a successful save and `previous_changes` is still
  # populated, which is exactly what an audit writer needs -- and they are the only hook the gem offers, so
  # the alternative would be overriding `create` and `update` wholesale.
  def after_resource_created_path(resource)
    Marketing::PageAudit.record(resource, actor: current_super_admin)
    super
  end

  def after_resource_updated_path(resource)
    Marketing::PageAudit.record(resource, actor: current_super_admin)
    super
  end

  def transition(status, verb)
    page = requested_resource
    if page.update(status: status)
      Marketing::PageAudit.record(page, actor: current_super_admin)
      redirect_to [:super_admin, page], notice: t("super_admin.site_pages.#{verb}")
    else
      redirect_to [:super_admin, page], alert: page.errors.full_messages.to_sentence
    end
  end

  # Every refusal the upload service raises is a validation failure of the request, answered where the
  # operator is rather than as a 500.
  def redirect_with_upload_error(exception)
    redirect_to [:super_admin, requested_resource], alert: exception.message
  end
end
