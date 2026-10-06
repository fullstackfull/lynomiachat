# frozen_string_literal: true

require 'administrate/base_dashboard'

# Lynomia global documentation (docs/global-documentation/07-super-admin-management.md): Super Admin authors the
# platform's documentation and changelog on the Help Center's own Article, so there is no second content model.
#
# `content` is CommonMark, the same source format the dashboard's editor produces and the same the public renderer
# consumes (ChatwootMarkdownRenderer#render_article) -- a textarea here is the same content, not a lesser one, and the
# Preview action renders it through the real public layout before anything is published.
class ArticleDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    portal: Field::BelongsTo.with_options(scope: -> { Documentation::Library.portals }),
    category: Field::BelongsTo.with_options(scope: -> { Category.where(portal: Documentation::Library.portals) }),
    title: Field::String.with_options(searchable: true),
    slug: Field::String.with_options(searchable: true),
    description: Field::Text,
    content: Field::Text.with_options(rows: 28),
    locale: Field::Select.with_options(collection: Documentation::Library::LOCALES),
    status: Field::Select.with_options(collection: Article.statuses.keys),
    position: Field::Number,
    meta: ArticleMetaField,
    author: ArticleAuthorField,
    views: Field::Number,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[title portal category locale status position updated_at].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id title slug portal category locale status description content meta position author views created_at updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[portal category title slug description content locale status position meta].freeze

  COLLECTION_FILTERS = {
    published: ->(resources) { resources.published },
    draft: ->(resources) { resources.draft },
    changelog: ->(resources) { resources.where(portal: Documentation::Library.changelog_portal) }
  }.freeze

  def display_resource(article)
    article.title
  end

  def self.resource_name(opts = {})
    opts[:count].to_i == 1 ? 'Documentation article' : 'Documentation articles'
  end
end
