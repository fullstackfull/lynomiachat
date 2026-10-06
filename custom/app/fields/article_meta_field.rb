# frozen_string_literal: true

require 'administrate/field/base'

# Lynomia global documentation: the article `meta` jsonb, edited as named fields rather than as raw JSON.
#
# Three keys are the Help Center's own and are already rendered into the public <head> (_meta_head.html.erb): the SEO
# title, the SEO description and the tags. Three more carry a changelog release, which the Article model has no
# columns for and does not need any (docs/global-documentation/08-changelog-design.md).
class ArticleMetaField < Administrate::Field::Base
  SEO_KEYS = %w[title description].freeze
  RELEASE_KEYS = %w[version release_date].freeze
  STRING_KEYS = (SEO_KEYS + RELEASE_KEYS + %w[feature_image]).freeze

  LABELS = {
    'title' => 'SEO title',
    'description' => 'SEO description',
    'tags' => 'Tags',
    'version' => 'Release version',
    'release_date' => 'Release date',
    'feature_image' => 'Feature image URL'
  }.freeze

  HINTS = {
    'title' => 'Overrides the <title> and og:title. Leave blank to use the article title.',
    'description' => 'The meta description and og:description. Around 150 characters reads best in search results.',
    'tags' => 'Comma separated. Rendered as <meta name="tags"> and used to label a changelog entry by module.',
    'version' => 'Changelog only, e.g. 2026.10. Left blank on a documentation article.',
    'release_date' => 'Changelog only. ISO-8601 (YYYY-MM-DD); this is the date the release shipped, not when the note was edited.',
    'feature_image' => 'Changelog only. Absolute URL of the image shown with the release.'
  }.freeze

  def self.permitted_attribute(attr, _options = nil)
    { attr => STRING_KEYS + [{ tags: [] }, :tags] }
  end

  def meta
    (data || {}).to_h
  end

  def value_for(key) = meta[key].to_s

  def tags = Array(meta['tags']).join(', ')

  def label(key) = LABELS.fetch(key)

  def hint(key) = HINTS.fetch(key)

  def to_s
    present = LABELS.keys.select { |key| key == 'tags' ? tags.present? : value_for(key).present? }
    return '—' if present.empty?

    present.map { |key| "#{label(key)}: #{key == 'tags' ? tags : value_for(key)}" }.join(' · ')
  end
end
