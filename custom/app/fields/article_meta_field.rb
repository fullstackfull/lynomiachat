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

  # Every key this field's form posts. `meta` is one jsonb column shared by two writers, and the other writer's
  # keys are not on this form: Documentation::ContentSeeder#meta_for also writes `doc_key`
  # (custom/app/services/documentation/content_seeder.rb:107), which is the key every contextual-help link
  # resolves through (custom/app/services/documentation/library.rb:55).
  MANAGED_KEYS = (STRING_KEYS + %w[tags]).freeze

  def self.permitted_attribute(attr, _options = nil)
    { attr => STRING_KEYS + [{ tags: [] }, :tags] }
  end

  # The guarantee that a save cannot destroy a key this form does not offer, placed on the field rather than in
  # a controller because the field is what decides which keys the form has. A controller that forgets to merge
  # can no longer replace the column, since the only keys this returns from the submission are MANAGED_KEYS.
  #
  # Clearing an input still removes its key -- that is the behaviour the form already had and operators rely on
  # to drop an SEO override -- so the managed keys are taken from the submission wholesale after `compact_blank`
  # rather than merged over the stored ones. Only the unmanaged keys are carried through from storage.
  def self.merge_submitted(stored, submitted)
    unmanaged = stored.to_h.except(*MANAGED_KEYS)
    return unmanaged if submitted.blank?

    unmanaged.merge(normalize(submitted))
  end

  # The form posts tags as one comma separated string because that is what a text input gives; the model, the
  # serializer and the public <meta> tag all expect an array.
  def self.normalize(submitted)
    managed = submitted.to_h.with_indifferent_access.slice(*MANAGED_KEYS)
    managed['tags'] = managed['tags'].split(',').map(&:strip) if managed['tags'].is_a?(String)
    managed.to_h.compact_blank
  end

  def meta
    (data || {}).to_h
  end

  def value_for(key) = meta[key].to_s

  def tags = Array(meta['tags']).join(', ')

  # Shown, never editable. It is the corpus file's basename and the identity every contextual-help link resolves
  # through, so an operator needs to see which article they are editing is wired to the product -- and must not be
  # able to change it, because an editable doc_key is a second way to break every help link
  # (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md D3, D5).
  def doc_key = meta['doc_key'].to_s

  def label(key) = LABELS.fetch(key)

  def hint(key) = HINTS.fetch(key)

  def to_s
    present = LABELS.keys.select { |key| key == 'tags' ? tags.present? : value_for(key).present? }
    described = present.map { |key| "#{label(key)}: #{key == 'tags' ? tags : value_for(key)}" }
    described.unshift("Documentation key: #{doc_key}") if doc_key.present?
    return '—' if described.empty?

    described.join(' · ')
  end
end
