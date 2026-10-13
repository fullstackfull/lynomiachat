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
    content = params.require(:article).permit(:content).fetch(:content, '').to_s
    render partial: 'super_admin/articles/markdown_preview',
           locals: { parsed_content: ChatwootMarkdownRenderer.new(content).render_article }
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
