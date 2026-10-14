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

  # The preview of UNSAVED source, rendered by the renderer that will publish it. A Markdown implementation in the
  # browser would be a second renderer showing something the published page does not, which is the class of defect
  # orchestrator ruling R3 point 6 names; so the editor posts its source here and gets back the same fragment, in
  # the same wrapper, that app/views/public/api/v1/portals/articles/_content.html.erb renders publicly.
  #
  # A collection action, not a member one: rendering Markdown needs the Markdown and nothing else, so `new` and
  # `edit` share one endpoint and neither needs a saved row.
  def preview_markdown
    permitted = params.require(:article).permit(:content, :id)
    content = permitted.fetch(:content, '').to_s
    render partial: 'super_admin/articles/markdown_preview',
           locals: { parsed_content: ChatwootMarkdownRenderer.new(content).render_article(media: preview_resolver(permitted[:id])) }
  end

  private

  # Without this the preview pane rendered every `media:` reference as an inert comment, so an operator uploaded
  # an image, the editor inserted the server's own Markdown, and the preview showed nothing -- while the
  # published page and the `preview` member action were both correct. That is ruling R3 point 6's defect class
  # inverted: a preview showing LESS than the published page.
  #
  # Same resolver the public page builds (public/api/v1/portals/articles_controller.rb:112), per request and per
  # portal, and the portal comes from the found article rather than from the posted form, so a posted id cannot
  # point the resolver at a portal the operator is not editing. `scoped_resource` keeps it to platform portals,
  # and the action is Super Admin only. A draft's media is served to a signed-in super admin by contract section
  # 0.1, so the <img> in the preview actually loads.
  #
  # nil for an UNSAVED article, which is a real limitation rather than an oversight: `MediaResolver#image_for`
  # mints `public_portal_article_media_path(portal.slug, article.slug, key)` and an unsaved article has no slug,
  # so there is no address its media could be served at yet. A new article's preview shows the inert comment
  # until its first save; after that it resolves. Widening the resolver to an article-less form is Agent 1's
  # interface call (R2-MEDIA-INTERFACE.md section 2.1), not a thing to improvise here.
  def preview_resolver(article_id)
    return if article_id.blank?

    article = scoped_resource.find_by(id: article_id)
    return if article.nil?

    Documentation::MediaResolver.new(portal: article.portal, article: article)
  end

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
      permitted[:meta] = ArticleMetaField.merge_submitted(stored_meta, permitted[:meta]) if permitted.key?(:meta)
    end
  end

  # `meta` is one jsonb column with two writers and the form offers only its own keys, so assigning the submission
  # as a whole value replaced the column and dropped `doc_key` -- silently breaking every contextual-help link for
  # that article, including on a save that only fixed a typo
  # (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md D3). ArticleMetaField owns the merge because it owns the
  # list of keys the form posts.
  #
  # On create there is no stored row: `requested_resource` reads `params[:id]`
  # (administrate-0.20.1/app/controllers/administrate/application_controller.rb:183-191), which `create` does not
  # have.
  def stored_meta
    action_name == 'update' ? requested_resource.meta : {}
  end
end
