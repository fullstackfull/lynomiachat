# One entry in the header or the footer.
#
# AN INTERNAL LINK IS STORED AS A TARGET, NOT A URL. `page:feature:unified_inbox` resolves at render time, so
# when an operator renames that page's slug the navigation follows it. A stored URL would point at where the
# page used to be, and a managed navigation that quietly fills up with 404s is worse than a hard-coded one --
# which is what W2 shipped and what this replaces.
#
# EXACTLY ONE OF `href` AND the page reference, enforced. Both set is an ambiguity with no correct answer;
# neither set is a link to nowhere, and a link to nowhere in the footer is the specific defect
# docs/official-website/01-current-state-audit.md found four of on the old site.
class SiteNavLink < ApplicationRecord
  # Where a link appears. The footer's four columns are separate placements rather than one list with a
  # column number, so an operator moving a link between columns changes one field.
  PLACEMENTS = %w[header footer_product footer_resources footer_support footer_company].freeze

  normalizes :locale, :placement, :page_kind, :page_key, with: ->(value) { value.to_s.strip.downcase.presence }
  normalizes :label, :href, with: ->(value) { value.to_s.strip.presence }

  validates :locale, inclusion: { in: MarketingHelper::LOCALES }
  validates :placement, inclusion: { in: PLACEMENTS }
  validates :label, presence: true, length: { maximum: 80 }
  validate :validate_exactly_one_target
  validate :validate_target_values

  scope :visible, -> { where(visible: true) }
  scope :ordered, -> { order(:position, :id) }
  scope :placed, ->(locale, placement) { visible.for_locale(locale).where(placement: placement).ordered }
  scope :for_locale, ->(locale) { where(locale: locale) }

  def target
    return href if href.present?

    "page:#{page_kind}:#{page_key}"
  end

  def internal?
    page_kind.present? && page_key.present?
  end

  private

  def validate_exactly_one_target
    return if internal? ^ href.present?

    errors.add(:base, internal? ? 'set either a page or an external link, not both' : 'needs a page or an external link')
  end

  def validate_target_values
    errors.add(:href, "is not an allowed link: #{href}") if href.present? && !Marketing::LinkTarget.valid?(href)
    errors.add(:page_kind, 'is not a page kind') if page_kind.present? && SitePage::KINDS.exclude?(page_kind)
  end
end
