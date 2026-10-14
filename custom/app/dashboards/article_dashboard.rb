# frozen_string_literal: true

require 'administrate/base_dashboard'

# Lynomia global documentation (docs/global-documentation/07-super-admin-management.md): Super Admin authors the
# platform's documentation and changelog on the Help Center's own Article, so there is no second content model.
#
# `content` is CommonMark, the format ChatwootMarkdownRenderer#render_article CONSUMES. It does not produce it: the
# producer is the operator, through the Markdown source editor in app/javascript/super_admin/documentation, and the
# corpus under custom/db/documentation. The correction matters because the two differ -- a parse-and-serialize round
# trip through the installed ProseMirror pair rewrites all 126 corpus files today
# (app/javascript/super_admin/documentation/corpusRoundTrip.spec.js), which is why the editor edits the source and
# never re-serializes it (orchestrator ruling R3 points 2, 7).
class ArticleDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    portal: Field::BelongsTo.with_options(scope: -> { Documentation::Library.portals }),
    category: Field::BelongsTo.with_options(scope: -> { Category.where(portal: Documentation::Library.portals) }),
    title: Field::String.with_options(searchable: true),
    slug: Field::String.with_options(searchable: true),
    description: Field::Text,
    # No `rows:`: administrate's text partial calls `f.text_area field.attribute` with no options
    # (administrate-0.20.1/app/views/fields/text/_form.html.erb:21), so the option never reached the element.
    # The editor sizes itself (ruling R3 point 8).
    content: Field::Text,
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

  # `slug` is deliberately absent: it is the article's public address, derived from the corpus file name by
  # Documentation::ContentSeeder::Corpus#read_file -- the basename for the default locale, basename-<locale> for
  # the others (custom/app/services/documentation/content_seeder.rb:256-261). Editing it
  # here 404s a previously indexed URL and leaves the next seed to create a duplicate row
  # (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md D4). It stays on SHOW_PAGE_ATTRIBUTES and stays
  # searchable.
  FORM_ATTRIBUTES = %i[portal category title description content locale status position meta].freeze

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
