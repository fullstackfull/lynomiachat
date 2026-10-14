# One page of the official website, in one locale.
#
# THE ROW IS WHAT THE PUBLIC PAGE RENDERS FROM. It is not an override layered on top of a locale file and it
# is not a copy of one: `Marketing::ContentSeeder` writes the 96 rows the site ships once, from the repository,
# and the operator owns them from then on. That is what "the CMS controls the rendered website" has to mean --
# anything less and the editor shows one thing while the visitor reads another.
#
# `kind` + `key` IS THE IDENTITY; `slug` IS THE URL. The controller looks a page up by the identity the route
# handed it, never by operator input, so a renamed slug cannot make a page unreachable by accident. The
# Arabic and English siblings of one page stay paired through `[kind, key]` even when their slugs differ,
# which is what the hreflang pair is built from.
#
# A STANDING PAGE'S SLUG IS ITS KEY, ENFORCED. `/features` is a fixed word in config/routes/marketing.rb; a
# row claiming a different slug for it would describe a URL that does not exist. Detail slugs are free
# because their route segment is dynamic -- and that is exactly the set of URLs SiteRedirect covers.
#
# WHAT AN OPERATOR CANNOT EDIT HERE: a feature's availability state, its prerequisite, the catalogue it
# belongs to, or the related pages. Those are product facts from Marketing::Catalog, carried beside the
# evidence in docs/official-website/02-verified-feature-inventory.md, and an operator editing a conditional
# feature into an available one is the exact failure this whole rebuild exists to remove.
class SitePage < ApplicationRecord
  KINDS = %w[standing feature channel solution integration].freeze

  # The kinds whose route segment is dynamic, and whose slug an operator may therefore change.
  RENAMEABLE_KINDS = (KINDS - %w[standing]).freeze

  # The SEO fields `meta` may carry. An allowlist, because `meta` is jsonb written from a form and read into
  # the document head: an unknown key would be stored forever and never rendered, which is how a jsonb column
  # becomes a junk drawer nobody can safely clear.
  META_KEYS = %w[canonical_url og_title og_description og_image_key noindex].freeze

  enum :status, { draft: 0, published: 1, archived: 2 }, prefix: :status

  # Marketing media, in its own attachment name so the documentation corpus's orphan sweep can never reach it
  # and this page's images can never be swept by it either (D10).
  has_many_attached :marketing_images

  # Rails' own attribute normalisation (7.1+), which runs on assignment: an operator's trailing space or
  # capital letter cannot become a second row, and `sections`/`meta` are coerced to the shapes the renderer
  # understands before any validation looks at them.
  normalizes :locale, :kind, :key, with: ->(value) { value.to_s.strip.downcase.presence }
  normalizes :slug, with: ->(value) { value.to_s.strip.downcase.tr('_', '-').presence }
  normalizes :sections, with: ->(value) { Marketing::SectionSchema.coerce(value) }
  normalizes :meta, with: ->(value) { (value || {}).to_h.stringify_keys.slice(*META_KEYS).compact_blank }

  before_validation :default_slug_from_key
  before_validation :stamp_published_at

  validates :locale, inclusion: { in: MarketingHelper::LOCALES }
  validates :kind, inclusion: { in: KINDS }
  validates :key, presence: true, format: { with: /\A[a-z0-9]+(_[a-z0-9]+)*\z/ },
                  uniqueness: { scope: [:locale, :kind] }
  validates :slug, presence: true, format: { with: /\A[a-z0-9]+(-[a-z0-9]+)*\z/ },
                   uniqueness: { scope: [:locale, :kind] }
  validates :title, presence: true, length: { maximum: 160 }
  validates :description, length: { maximum: 400 }
  validates :heading, length: { maximum: 200 }
  validates :lede, length: { maximum: 1200 }
  validate :validate_standing_slug
  validate :validate_sections
  validate :validate_meta

  scope :live, -> { where(status: :published) }
  scope :ordered, -> { order(:position, :key) }
  scope :for_locale, ->(locale) { where(locale: locale) }

  # The sibling in the other locale, which hreflang and the language switch both need. Found by identity, so
  # it keeps working when the two locales' slugs differ.
  def translation
    self.class.find_by(locale: MarketingHelper::LOCALES.find { |other| other != locale }, kind: kind, key: key)
  end

  def catalogue_entry
    return nil if kind == 'standing'

    Marketing::Catalog.entries(kind.pluralize.to_sym).find { |entry| entry.id.to_s == key }
  end

  def noindex?
    ActiveModel::Type::Boolean.new.cast(meta['noindex']).present?
  end

  # Whether a visitor may see this page. A draft is visible only through the Super Admin preview, which
  # renders it without publishing it.
  def visible?
    status_published?
  end

  # The attachment an `image` section names. Nil when the operator deleted it, so the section renders nothing
  # rather than raising on a public page.
  def image_for(attachment_id)
    return nil if attachment_id.blank?

    marketing_images.find { |attachment| attachment.id.to_s == attachment_id.to_s }
  end

  private

  def default_slug_from_key
    self.slug = key.to_s.tr('_', '-') if slug.blank?
  end

  # The moment a page first went live, which the sitemap publishes as <lastmod>. Set once: a later edit
  # changes `updated_at`, and overwriting this would claim the page is newer than it is.
  def stamp_published_at
    self.published_at ||= Time.current if status_published?
  end

  def validate_standing_slug
    return unless kind == 'standing'
    return if slug == key.to_s.tr('_', '-')

    errors.add(:slug, 'cannot be changed on a standing page: its route is a fixed word in the route table')
  end

  def validate_sections
    Marketing::SectionSchema.errors(sections).each { |message| errors.add(:sections, message) }
  end

  def validate_meta
    canonical = meta['canonical_url']
    return if canonical.blank? || Marketing::LinkTarget.valid?(canonical)

    errors.add(:meta, "canonical_url is not an allowed URL: #{canonical}")
  end
end
