# == Schema Information
#
# Table name: articles
#
#  id                    :bigint           not null, primary key
#  content               :text
#  description           :text
#  draft_content         :text
#  draft_title           :string
#  locale                :string           default("en"), not null
#  meta                  :jsonb
#  position              :integer
#  slug                  :string           not null
#  status                :integer
#  title                 :string
#  views                 :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :integer          not null
#  associated_article_id :bigint
#  author_id             :bigint
#  category_id           :integer
#  folder_id             :integer
#  portal_id             :integer          not null
#
# Indexes
#
#  index_articles_on_account_id             (account_id)
#  index_articles_on_associated_article_id  (associated_article_id)
#  index_articles_on_author_id              (author_id)
#  index_articles_on_portal_id              (portal_id)
#  index_articles_on_slug                   (slug) UNIQUE
#  index_articles_on_status                 (status)
#  index_articles_on_views                  (views)
#
class Article < ApplicationRecord
  include PgSearch::Model
  include LlmFormattable

  has_many :associated_articles,
           class_name: :Article,
           foreign_key: :associated_article_id,
           dependent: :nullify,
           inverse_of: 'root_article'

  belongs_to :root_article,
             class_name: :Article,
             foreign_key: :associated_article_id,
             inverse_of: :associated_articles,
             optional: true
  # A platform portal has no account, so neither do its articles; `ensure_account_id` already copies
  # `portal&.account_id`, which is nil there (docs/global-documentation/01-global-ownership-design.md).
  belongs_to :account, optional: true
  belongs_to :category, optional: true
  belongs_to :portal
  belongs_to :author, class_name: 'User', inverse_of: :articles

  before_validation :ensure_account_id
  before_validation :ensure_article_slug
  before_validation :ensure_locale_in_article

  # Slugs that collide with help center routes (e.g. /hc/:slug/:locale/search)
  RESERVED_SLUGS = %w[search articles categories].freeze

  validates :account_id, presence: true, unless: :platform_owned?
  validates :author_id, presence: true
  validates :title, presence: true
  validates :content, presence: true, if: :published?
  validates :slug, exclusion: { in: RESERVED_SLUGS }
  validate :category_in_same_portal

  # ensuring that the position is always set correctly
  before_create :add_position_to_article
  after_save :category_id_changed_action, if: :saved_change_to_category_id?

  enum status: { draft: 0, published: 1, archived: 2 }

  scope :search_by_category_slug, ->(category_slug) { where(categories: { slug: category_slug }) if category_slug.present? }
  scope :search_by_category_locale, ->(locale) { where(categories: { locale: locale }) if locale.present? }
  scope :search_by_locale, ->(locale) { where(locale: locale) if locale.present? }
  scope :search_by_author, ->(author_id) { where(author_id: author_id) if author_id.present? }
  scope :search_by_status, ->(status) { where(status: status) if status.present? }
  scope :order_by_updated_at, -> { reorder(updated_at: :desc) }
  scope :order_by_position, -> { reorder(position: :asc) }
  # Newest release first. `meta['release_date']` is an author-entered ISO-8601 date, so it sorts lexically; entries
  # without one fall to the end and keep their hand-set order among themselves.
  scope :order_by_release_date, -> { reorder(Arel.sql("articles.meta->>'release_date' DESC NULLS LAST, articles.position ASC")) }
  scope :order_by_views, -> { reorder(views: :desc) }

  # LEGACY ROWS THAT `category_in_same_portal` NOW REFUSES: an article whose category belongs to a different
  # portal. There is no foreign key on `category_id` and nothing ever tied the two columns, so these were
  # storable before that validation existed.
  #
  # A scope rather than an ad-hoc query because an operator runs this on production to decide whether the
  # read-side guards are load-bearing, and the obvious first attempt is silently wrong:
  # `where.not(portal_id: Category.arel_table[:portal_id])` compiles to `articles.portal_id != NULL`, which is
  # never true in SQL, so it answers "none" on any data at all. (It was written into a report as the check to
  # run before being caught here.) The Arel form below compiles to a real column-to-column comparison, and
  # spec/models/article_spec.rb plants a mismatched row to prove the scope finds one.
  scope :cross_portal_category, lambda {
    joins(:category).where(arel_table[:portal_id].not_eq(Category.arel_table[:portal_id]))
  }

  # TODO: if text search slows down https://www.postgresql.org/docs/current/textsearch-features.html#TEXTSEARCH-UPDATE-TRIGGERS
  # - the A, B and C are for weightage. See: https://github.com/Casecommons/pg_search#weighting
  # - the normalization is for ensuring the long articles that mention the search term too many times are not ranked higher.
  #   it divides rank by log(document_length) to prevent longer articles from ranking higher just due to sizeSee: https://github.com/Casecommons/pg_search#normalization
  # - the ranking is to ensure that articles with higher weightage are ranked higher
  pg_search_scope(
    :text_search,
    against: {
      title: 'A',
      description: 'B',
      content: 'C'
    },
    using: {
      tsearch: {
        prefix: true,
        normalization: 2
      }
    },
    ranked_by: ':tsearch'
  )

  def platform_owned?
    portal&.platform_owned? || false
  end

  # AN ARTICLE'S CATEGORY MUST BELONG TO THE ARTICLE'S OWN PORTAL.
  #
  # Nothing tied the two together: `category_id` and `portal_id` are independent columns with no constraint
  # between them and no foreign key on `category_id`. A row whose category belongs to Lynomia's documentation
  # portal while the article belongs to a tenant portal is therefore storable -- and the public portal lists a
  # category's articles by `category_id` alone (eighteen read sites), so that one row renders on /docs with its
  # title, body excerpt and, until the byline change, its author's name and avatar.
  #
  # Not tenant-reachable: every tenant article write is refused by Custom::ArticlePolicy. It is reachable by
  # Lynomia's own Super Admin, because Administrate builds `Article.new(resource_params)` with both `portal_id`
  # and `category_id` mass-assignable from the form (custom/app/dashboards/article_dashboard.rb) while
  # `scoped_resource` only governs find. So this closes an operator foot-gun that publishes cross-portal
  # content, at the one place both values are known.
  #
  # This is the WRITE half. The READ half is Category#portal_articles and Article#portal_category, which every
  # public read goes through -- NOT a scope on the `Category#articles` association, which was tried, broke the
  # public documentation home page and was reverted (see app/models/category.rb).
  def category_in_same_portal
    return if category.nil? || category.portal_id == portal_id

    errors.add(:category, I18n.t('errors.articles.category_portal_mismatch'))
  end

  # THE CATEGORY THIS ARTICLE MAY BE PUBLISHED UNDER, which is none when the category belongs to a different
  # portal. Public pages render a category's name, icon and URL beside an article; for a legacy cross-portal row
  # that published a foreign category's name and emitted a category URL that 404s under the rendering portal.
  def portal_category
    category if category && category.portal_id == portal_id
  end

  # WHO TO ATTRIBUTE PUBLICLY, which is nobody for Lynomia's own documentation.
  #
  # `author_id` is required on every article and stays required: Super Admin needs to know who wrote a page, and
  # Documentation::ContentSeeder stamps `SuperAdmin.first` on the whole platform corpus
  # (custom/app/services/documentation/content_seeder.rb:22,79). But SuperAdmin is a User
  # (app/models/super_admin.rb:47), so every public documentation page and category page was publishing a named
  # operator's display name and avatar. The product's author is Lynomia.
  #
  # One reader rather than a condition in each view, because there are six render sites and they are not all
  # HTML: both public JSON partials, both portal layouts, and the category author strip. A per-view condition
  # closed the one a reader happened to be looking at and left the JSON API open, which is exactly what the
  # adversarial pass over the first version of this fix found.
  #
  # A tenant Help Center keeps its bylines: there the author is a colleague the reader works with.
  def public_author
    author unless platform_owned?
  end

  def self.search(params)
    records = left_outer_joins(
      :category
    ).search_by_category_slug(
      params[:category_slug]
    ).search_by_locale(params[:locale]).search_by_author(params[:author_id]).search_by_status(params[:status])

    records = records.text_search(params[:query]) if params[:query].present?
    records
  end

  def associate_root_article(associated_article_id)
    article = portal.articles.find(associated_article_id) if associated_article_id.present?

    return if article.nil?

    root_article_id = self.class.find_root_article_id(article)

    update(associated_article_id: root_article_id) if root_article_id.present?
  end

  # Make sure we always associate the parent's associated id to avoid the deeper associations od articles.
  def self.find_root_article_id(article)
    article.associated_article_id || article.id
  end

  def draft!
    update(status: :draft)
  end

  def increment_view_count
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:views, views? ? views + 1 : 1)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def self.update_positions(portal:, positions_hash:)
    return {} if positions_hash.blank?

    moved_ids = positions_hash.keys.map(&:to_i)

    transaction do
      positions_hash.each do |article_id, new_position|
        portal.articles.find(article_id).update!(position: new_position)
      end
      # Re-space touched categories to clean gaps and return the final positions
      rebalance_positions(portal, moved_ids)
    end
  end

  def self.rebalance_positions(portal, moved_ids)
    category_ids = portal.articles.where(id: moved_ids).distinct.pluck(:category_id).compact
    category_ids.each_with_object({}) do |category_id, positions|
      resequence_category(portal, category_id, moved_ids, positions)
    end
  end

  def self.resequence_category(portal, category_id, moved_ids, positions)
    ordered = portal.articles.where(category_id: category_id)
                    .sort_by { |article| [article.position || 0, moved_ids.include?(article.id) ? 1 : 0, article.id] }
    return if ordered.length < 2 # a lone article can't collide, leave it as-is

    ordered.each_with_index do |article, index|
      new_position = (index + 1) * 10
      positions[article.id] = new_position
      next if article.position == new_position

      article.update_column(:position, new_position) # rubocop:disable Rails/SkipsModelValidations
    end
  end
  private_class_method :rebalance_positions, :resequence_category

  private

  def category_id_changed_action
    # We need to update the position of the article in the new category
    return unless persisted?

    # this means the article is just created
    # and the category_id is newly set
    # and the position is already present
    return if created_at_before_last_save.nil? && position.present? && category_id_before_last_save.nil?

    update_article_position_in_category
  end

  def ensure_locale_in_article
    self.locale = if category.present?
                    category.locale
                  else
                    locale.presence || portal.default_locale
                  end
  end

  def add_position_to_article
    # on creation if a position is already present, ignore it
    return if position.present?

    update_article_position_in_category
  end

  def update_article_position_in_category
    max_position = Article.where(category_id: category_id, account_id: account_id).maximum(:position)

    new_position = max_position.present? ? max_position + 10 : 10

    # update column to avoid validations if the article is already persisted
    if persisted?
      # rubocop:disable Rails/SkipsModelValidations
      update_column(:position, new_position)
      # rubocop:enable Rails/SkipsModelValidations
    else
      self.position = new_position
    end
  end

  def ensure_account_id
    self.account_id = portal&.account_id
  end

  def ensure_article_slug
    self.slug ||= "#{Time.now.utc.to_i}-#{title.underscore.parameterize(separator: '-')}" if title.present?
  end
end
Article.include_mod_with('Concerns::Article')
