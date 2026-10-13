# == Schema Information
#
# Table name: categories
#
#  id                     :bigint           not null, primary key
#  description            :text
#  icon                   :string           default("")
#  locale                 :string           default("en")
#  name                   :string
#  position               :integer
#  slug                   :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :integer          not null
#  associated_category_id :bigint
#  parent_category_id     :bigint
#  portal_id              :integer          not null
#
# Indexes
#
#  index_categories_on_associated_category_id         (associated_category_id)
#  index_categories_on_locale                         (locale)
#  index_categories_on_locale_and_account_id          (locale,account_id)
#  index_categories_on_parent_category_id             (parent_category_id)
#  index_categories_on_slug_and_locale_and_portal_id  (slug,locale,portal_id) UNIQUE
#
class Category < ApplicationRecord
  paginates_per Limits::CATEGORIES_PER_PAGE
  # See Article: a platform portal's categories have no account either.
  belongs_to :account, optional: true
  belongs_to :portal
  has_many :folders, dependent: :destroy_async
  # SCOPED TO THIS CATEGORY'S OWN PORTAL, which is the READ half of the rule Article#category_in_same_portal
  # enforces on write. The public portal lists a category's articles by `category_id` alone in eighteen places
  # (category pages, category blocks, article counts, the author strip, the category JSON), so scoping the
  # association closes all of them at once instead of asking eighteen call sites to remember.
  #
  # `dependent: :nullify` now nullifies only the in-portal articles. For rows created after the validation
  # above that is the same set; a pre-existing mismatched row would keep a `category_id` pointing at a destroyed
  # category, which is harmless -- `Article#category` is optional, there is no foreign key on the column, and
  # every read path goes through this association, so such a row simply stops appearing anywhere.
  has_many :articles, ->(category) { where(portal_id: category.portal_id) }, dependent: :nullify, inverse_of: :category
  has_many :category_related_categories,
           class_name: :RelatedCategory,
           dependent: :destroy_async
  has_many :related_categories,
           through: :category_related_categories,
           class_name: :Category,
           dependent: :nullify
  has_many :sub_categories,
           class_name: :Category,
           foreign_key: :parent_category_id,
           dependent: :nullify,
           inverse_of: 'parent_category'
  has_many :associated_categories,
           class_name: :Category,
           foreign_key: :associated_category_id,
           dependent: :nullify,
           inverse_of: 'root_category'
  belongs_to :parent_category, class_name: :Category, optional: true
  belongs_to :root_category,
             class_name: :Category,
             foreign_key: :associated_category_id,
             inverse_of: :associated_categories,
             optional: true

  before_validation :ensure_account_id
  validates :account_id, presence: true, unless: :platform_owned?
  validates :slug, presence: true
  validates :name, presence: true
  validate :allowed_locales
  validates :locale, uniqueness: { scope: %i[slug portal_id],
                                   message: I18n.t('errors.categories.locale.unique') }
  accepts_nested_attributes_for :related_categories

  scope :search_by_locale, ->(locale) { where(locale: locale) if locale.present? }

  def self.search(params)
    search_by_locale(params[:locale]).page(current_page(params)).order(position: :asc)
  end

  def self.current_page(params)
    params[:page] || 1
  end

  def self.update_positions(portal:, positions_hash:)
    return if positions_hash.blank?

    transaction do
      positions_hash.each do |category_id, new_position|
        portal.categories.find(category_id).update!(position: new_position)
      end
    end
  end

  def platform_owned?
    portal&.platform_owned? || false
  end

  private

  def ensure_account_id
    self.account_id = portal&.account_id
  end

  def allowed_locales
    return if portal.blank?

    allowed_locales = portal.allowed_locale_codes

    return true if allowed_locales.include?(locale)

    errors.add(:locale, "#{locale} of category is not part of portal's #{allowed_locales}.")
  end
end
