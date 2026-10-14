# One question and its answer, per locale.
#
# STRUCTURED ROWS RATHER THAN A BLOB, because the FAQPage structured data has to be generated from the same
# question and the same answer the reader sees. A blob would let the two drift, and structured data that does
# not match the visible page is a violation of Google's own rule as well as a lie.
#
# THE ANSWER IS PLAIN TEXT and the one link it may carry is a validated target, for the reason
# Marketing::SectionSchema gives at length: this repository has already shipped a stored XSS through a
# Markdown path, and an answer needs no markup beyond the link that is a field here.
class SiteFaqEntry < ApplicationRecord
  normalizes :locale, :link_page_kind, :link_page_key, with: ->(value) { value.to_s.strip.downcase.presence }
  normalizes :question, :answer, :link_label, with: ->(value) { value.to_s.strip.presence }

  validates :locale, inclusion: { in: MarketingHelper::LOCALES }
  validates :question, presence: true, length: { maximum: 300 }
  validates :answer, presence: true, length: { maximum: 2000 }
  validates :link_label, length: { maximum: 120 }
  validate :validate_link

  scope :visible, -> { where(visible: true) }
  scope :ordered, -> { order(:position, :id) }
  scope :for_locale, ->(locale) { where(locale: locale) }
  scope :published_for, ->(locale) { visible.for_locale(locale).ordered }

  def link?
    link_page_kind.present? && link_page_key.present? && link_label.present?
  end

  def target
    "page:#{link_page_kind}:#{link_page_key}"
  end

  private

  def validate_link
    errors.add(:link_page_kind, 'is not a page kind') if link_page_kind.present? && SitePage::KINDS.exclude?(link_page_kind)

    return if link_page_kind.blank? && link_page_key.blank?
    return if link_page_kind.present? && link_page_key.present?

    errors.add(:base, 'a linked page needs both a kind and a key')
  end
end
