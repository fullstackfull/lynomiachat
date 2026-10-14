# A quote request from the public pricing page.
#
# `Site*` is the family the official website's own records live in
# (docs/official-website/04-information-architecture.md D10): this is the first of them, and W4's SitePage,
# SiteNavLink, SiteFaqEntry and SiteRedirect join it.
#
# EVERY LENGTH IS CAPPED AND EVERY VALUE IS ALLOWLISTED, because this is the one table in the application an
# anonymous visitor can write to. A cap here is not defensive clutter: without it a single request can store
# an arbitrary amount of text, and `channels` is read back into I18n keys on the Super Admin page, so an
# unconstrained value there would be a lookup for whatever the client sent.
#
# NO CONTACT, NO ACCOUNT, NO CONVERSATION is created from this. A quote request is a lead for a person to
# answer, not a tenant record, and attaching it to the product's own data model would put an unverified
# stranger's input inside a customer's workspace.
class SiteQuoteRequest < ApplicationRecord
  # Buckets rather than a number: a visitor who has to count their agents to ask for a price usually does not
  # send the form, and a precise figure would be guesswork anyway at this stage of a conversation.
  TEAM_SIZES = %w[1-3 4-10 11-25 26-50 50+].freeze

  enum :status, { new_request: 0, contacted: 1, closed: 2 }, prefix: :status

  validates :name, presence: true, length: { maximum: 120 }
  validates :email, presence: true, length: { maximum: 180 },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :company, length: { maximum: 160 }
  validates :phone, length: { maximum: 40 }
  validates :message, length: { maximum: 4000 }
  validates :locale, inclusion: { in: MarketingHelper::LOCALES }
  validates :team_size, inclusion: { in: TEAM_SIZES }, allow_blank: true
  validate :validate_channels

  scope :newest_first, -> { order(created_at: :desc) }

  private

  # The slugs the form offered, and nothing else.
  def validate_channels
    self.channels = Array(channels).map(&:to_s).compact_blank.uniq
    unknown = channels - Marketing::Catalog.channels.map(&:slug)
    errors.add(:channels, :invalid) if unknown.any?
  end
end
