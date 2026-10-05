# frozen_string_literal: true

# Lynomia global documentation (docs/global-documentation/07-super-admin-management.md): Super Admin's authoring
# surface for platform documentation and changelog articles.
#
# Scoped to platform portals at `scoped_resource`, which is the single place Administrate resolves records from for
# index, show, edit, update and destroy alike. A tenant's help-center article is therefore not reachable here at all,
# which is the counterpart of tenants not being able to reach these.
class SuperAdmin::ArticlesController < SuperAdmin::ApplicationController
  def publish
    requested_resource.update!(status: :published)
    redirect_to [:super_admin, requested_resource], notice: I18n.t('documentation.super_admin.published')
  end

  def unpublish
    requested_resource.update!(status: :draft)
    redirect_to [:super_admin, requested_resource], notice: I18n.t('documentation.super_admin.unpublished')
  end

  # The real public article, in the real layout, before it is published. `show_plain_layout` is the Help Center's own
  # chrome-less variant, already used by the dashboard's preview iframe.
  def preview
    article = requested_resource
    redirect_to "/hc/#{article.portal.slug}/articles/#{article.slug}?show_plain_layout=true"
  end

  private

  def scoped_resource
    Article.where(portal: Documentation::Library.portals)
  end

  # Author is the super admin doing the writing, never a tenant user. Article requires one, and Super Admin is an STI
  # subclass of User, so the acting super admin's own row is the truthful answer.
  def new_resource(params = {})
    Article.new(params.reverse_merge(author: current_super_admin))
  end

  def resource_params
    super.tap do |permitted|
      permitted[:meta] = normalized_meta(permitted[:meta]) if permitted.key?(:meta)
    end
  end

  # The form posts tags as one comma separated string because that is what a text input gives; the model, the
  # serializer and the public <meta> tag all expect an array.
  def normalized_meta(meta)
    return meta if meta.blank?

    meta = meta.to_h.compact_blank
    meta['tags'] = meta['tags'].split(',').map(&:strip).compact_blank if meta['tags'].is_a?(String)
    meta
  end
end
