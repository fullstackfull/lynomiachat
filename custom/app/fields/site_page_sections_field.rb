# frozen_string_literal: true

require 'administrate/field/base'

# The ordered sections of a marketing page, edited as a server-rendered form.
#
# WHY NOT A VUE WIDGET. Super Admin renders at most ONE Vue island per page: `render_vue_component` hardcodes
# `id: 'app'` and the entrypoint mounts `#app` (app/controllers/super_admin/application_controller.rb:35-43,
# app/javascript/entrypoints/superadmin_pages.js). A page editor needs the rest of Administrate's form on the
# same screen, and there is no existing pattern in this repository for editing an ordered list of structured
# items -- Administrate's own SerializedField renders every input in its array branch `disabled: true`. So the
# editor is plain ERB and plain form fields, which is also what the owner asked for where it integrates more
# safely than a new widget.
#
# WHAT THE FORM POSTS is an index-keyed hash whose section type travels as `kind`; Marketing::SectionsInput
# explains why both of those are forced rather than chosen, and turns the submission back into an array.
#
# THE SHAPES COME FROM Marketing::SectionSchema and nowhere else. The form offers exactly the types it defines
# and exactly the fields each type carries, so an operator cannot author a section the renderer has no partial
# for, and a type gaining a field does not need this class edited.
class SitePageSectionsField < Administrate::Field::Base
  # An arbitrary nested hash, which is what `permit(sections: {})` means. The structure is then narrowed twice:
  # by Marketing::SectionsInput, which keeps only the controls and fields it knows, and by
  # Marketing::SectionSchema.coerce, which drops every key no type declares.
  def self.permitted_attribute(attr, _options = nil)
    { attr => {} }
  end

  # The fields rendered as a textarea rather than a single line, by the limit the schema gives them.
  LONG_FIELDS = %w[body lede description].freeze

  # Field names whose value is chosen from a list rather than typed.
  CHOICES = {
    'source' => Marketing::SectionSchema::SOURCES,
    'style' => Marketing::SectionSchema::STYLES,
    'metric' => Marketing::SectionSchema::METRICS
  }.freeze

  NUMERIC_FIELDS = %w[columns limit].freeze

  HINTS = {
    'kicker' => 'The small line above the headline.',
    'primary_target' => 'A page (page:standing:pricing), a path (/app/register), an absolute https URL, or mailto:/tel:.',
    'secondary_target' => 'Same shapes as the primary target.',
    'link_target' => 'Same shapes as the primary target. Leave empty for a card with no link.',
    'columns' => '1, 2 or 3. Anything else is clamped.',
    'limit' => 'How many catalogue entries to show. Empty shows all of them.',
    'source' => 'Which verified catalogue this block reads. The entries, their availability and their ' \
                'links come from the catalogue, never from here.',
    'style' => 'cards is the index grid; chips is the inline strip.',
    'metric' => 'Computed at render time, so it cannot go stale. Leave empty and type a value instead for a figure that is not one of these.',
    'value' => 'A literal figure. Ignored when a metric is chosen.',
    'attachment_id' => 'One of this page\'s uploaded images. Upload them on the page itself.',
    'alt' => 'Required when an image is chosen: it is the accessible name and the search snippet.'
  }.freeze

  def sections
    Array(data)
  end

  def types
    Marketing::SectionSchema::TYPES.keys
  end

  def fields_for(type) = Marketing::SectionSchema.fields_for(type)

  def item_fields_for(type) = Marketing::SectionSchema.item_fields_for(type)

  def itemised?(type) = Marketing::SectionSchema.itemised?(type)

  def max_sections = Marketing::SectionSchema::MAX_SECTIONS

  # How one field is rendered: :choice, :number, :image, :long or :line.
  def input_kind(name)
    return :choice if CHOICES.key?(name)
    return :number if NUMERIC_FIELDS.include?(name)
    return :image if name == 'attachment_id'
    return :long if LONG_FIELDS.include?(name)

    :line
  end

  def choices_for(name) = CHOICES.fetch(name, [])

  def hint_for(name) = HINTS[name]

  def limit_for(name)
    Marketing::SectionSchema::LIMITS[name] || Marketing::SectionSchema::LIMITS['default']
  end

  # The page's own uploaded images, as select options. A page with none renders an empty select and the note
  # that images are uploaded on the record, which is where the upload form lives.
  def image_options
    return [] unless resource.persisted?

    resource.marketing_images.includes(:blob).map do |attachment|
      [attachment.blob.filename.to_s, attachment.id]
    end
  end

  # The one-line summary the index and show pages print.
  def to_s
    return '—' if sections.empty?

    sections.map { |section| describe(section) }.join(' · ')
  end

  def describe(section)
    label = section['type'].to_s
    detail = section['heading'].presence || section['kicker'].presence
    count = Array(section['items']).size
    [label, detail, count.positive? ? "#{count} items" : nil].compact_blank.join(': ')
  end
end
