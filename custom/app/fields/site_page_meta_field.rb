# frozen_string_literal: true

require 'administrate/field/base'

# A marketing page's SEO fields, edited as named inputs rather than as raw JSON.
#
# `meta` IS AN ALLOWLISTED JSONB COLUMN (SitePage::META_KEYS) and this form offers exactly those keys, so a
# save cannot leave a key behind that nothing renders. Unlike the documentation article's `meta`, this column
# has only one writer -- there is no seeder key hiding in it -- so the submission replaces it wholesale and
# there is no merge to get wrong.
#
# EVERY FIELD HERE IS AN OVERRIDE, and empty is the normal state. The canonical defaults to the page's own
# address, og:title to its title, og:description to its description and the social image to the first image
# section, all built in marketing/shared/_head.html.erb -- so a blank panel is a correctly configured page,
# not an unfinished one.
class SitePageMetaField < Administrate::Field::Base
  STRING_KEYS = %w[canonical_url og_title og_description og_image_id].freeze
  BOOLEAN_KEYS = %w[noindex].freeze

  LABELS = {
    'canonical_url' => 'Canonical URL',
    'og_title' => 'Social title',
    'og_description' => 'Social description',
    'og_image_id' => 'Social image',
    'noindex' => 'Ask search engines not to index this page'
  }.freeze

  HINTS = {
    'canonical_url' => 'Overrides the canonical link. A path or an absolute https URL; anything else is ' \
                       'refused. Leave empty to use this page\'s own address, which is almost always right.',
    'og_title' => 'Overrides og:title and twitter:title. Leave empty to use the page title.',
    'og_description' => 'Overrides og:description. Leave empty to use the page description.',
    'og_image_id' => 'One of this page\'s uploaded images, used as the social card. Leave empty to use the first image section on the page.',
    'noindex' => 'A draft is already excluded from search and from the sitemap. Tick this to exclude a PUBLISHED page as well.'
  }.freeze

  def self.permitted_attribute(attr, _options = nil)
    { attr => STRING_KEYS + BOOLEAN_KEYS }
  end

  def meta
    (data || {}).to_h
  end

  def value_for(key) = meta[key].to_s

  def noindex? = ActiveModel::Type::Boolean.new.cast(meta['noindex']).present?

  def label(key) = LABELS.fetch(key)

  def hint(key) = HINTS.fetch(key)

  def image_options
    return [] unless resource.persisted?

    resource.marketing_images.includes(:blob).map { |attachment| [attachment.blob.filename.to_s, attachment.id] }
  end

  def to_s
    described = STRING_KEYS.select { |key| value_for(key).present? }
                           .map { |key| "#{label(key)}: #{value_for(key)}" }
    described << 'Not indexed' if noindex?
    described.presence&.join(' · ') || 'Defaults'
  end
end
