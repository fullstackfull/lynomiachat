# What a page section may be, and nothing else.
#
# THIS IS THE SECURITY BOUNDARY OF THE CMS. `site_pages.sections` is jsonb written from a Super Admin form
# and rendered into a public page, so without an allowlist it is an arbitrary-structure sink: a section type
# nobody wrote a partial for, a field nobody escapes, a link scheme nobody checked. Every section is
# normalised through `coerce` on save -- unknown types rejected, unknown keys dropped, strings truncated,
# link targets validated -- so the renderer only ever sees shapes it has a partial for.
#
# BODIES ARE PLAIN TEXT, NOT MARKDOWN, and that is deliberate rather than lazy. Three reasons, in order of
# weight: this repository has already shipped a stored XSS through a Markdown path (the fence info string,
# docs/documentation-v2/P0-PRODUCTION-HARDENING.md), so Markdown here would be re-opening a vector that cost
# a security fix; the 96 pages the site ships contain no markup at all, so nothing is lost by escaping; and
# the one piece of markup marketing copy genuinely needs -- a link -- is a first-class field on a card item
# with its scheme checked, which is both safer and easier for an operator than remembering link syntax.
#
# WHY A SERVICE AND NOT THE MODEL. SitePage validates, Administrate's field class renders a form, and the
# public partials render the output. All three need the same answer to "what is a section", and a constant
# they share is the only way they cannot disagree.
module Marketing::SectionSchema
  # A section type is a partial name under custom/app/views/marketing/sections/ plus the fields it carries.
  # `items` names the per-item fields where a type repeats; `limits` caps every string so one section cannot
  # store an unbounded page.
  TYPES = {
    # The home page's opening block. The headline and standfirst are the page's own `heading` and `lede`
    # columns, so they are not repeated here -- one page, one H1, stored once. `secondary_target` is a link
    # target and is validated like any other.
    'hero' => { fields: %w[kicker primary_label primary_target secondary_label secondary_target] },
    # A heading and a paragraph. The About page is four of these.
    'prose' => { fields: %w[heading body] },
    # The workhorse: a grid of title/body cards, each optionally linking somewhere. Detail-page points,
    # pricing dimensions, the support bands and the contact cards are all this one type.
    'cards' => {
      fields: %w[heading lede columns],
      items: %w[title body link_label link_target]
    },
    # The honesty paragraph -- what the page is NOT claiming. Rendered in its own quiet box.
    'note' => { fields: %w[body] },
    # An operator-uploaded image, named by the id of the attachment on this page.
    #
    # AN ID, NOT A FILENAME OR A SIGNED ID. A filename is not unique (two uploads called hero.png) and a
    # signed id is a bearer token that changes; an attachment id is indexable and stable. The documentation
    # corpus keys its media by blob metadata instead, but only because those keys had to survive inside
    # corpus Markdown and metadata is an unqueryable text column -- neither constraint applies to a row an
    # operator edits in a form (custom/app/services/documentation/media_resolver.rb:30-34).
    'image' => { fields: %w[attachment_id alt caption] },
    # A block the CODE fills from the verified catalogue: the channel strip, the feature grid, an index's
    # cards. The operator owns its copy and nothing else -- a feature's availability state and its
    # prerequisite are product facts and are not editable here, which is the rule doc 02 exists to protect.
    'catalogue' => { fields: %w[heading lede source limit link_label style] },
    # Figures. A `metric` is read from the catalogue at render time; a `value` is a literal the operator
    # typed. Offering both is what keeps "nine channels" correct when a tenth is added.
    'stats' => { fields: %w[heading], items: %w[value metric label] },
    # The question list, filled from site_faq_entries. Like `catalogue`, the operator owns the block's own
    # copy and the rows are edited where they live -- which is also what lets the FAQPage structured data in
    # W5 be generated from the same rows the reader sees.
    'faq' => { fields: %w[heading] }
  }.freeze

  # The only values `catalogue.source` may take: the catalogue's own collections.
  SOURCES = %w[features channels solutions integrations].freeze

  # How a catalogue block is drawn. `cards` is the index grid; `chips` is the home page's inline strip. Both
  # read the same entries, so an operator choosing between them changes presentation and never content.
  STYLES = %w[cards chips].freeze

  # The only metrics a stat may read. A metric nobody implemented would render blank.
  METRICS = %w[channel_count feature_count locale_count].freeze

  MAX_SECTIONS = 24
  MAX_ITEMS = 24
  LIMITS = { 'body' => 4000, 'lede' => 1200, 'default' => 300 }.freeze

  class << self
    def type?(type) = TYPES.key?(type.to_s)

    def fields_for(type) = TYPES.fetch(type.to_s, {})[:fields] || []

    def item_fields_for(type) = TYPES.fetch(type.to_s, {})[:items] || []

    def itemised?(type) = item_fields_for(type).any?

    # Normalise what an operator submitted into exactly what the renderer understands.
    #
    # It drops rather than raises, because a form that silently loses an unknown key is recoverable while a
    # 500 on save is not -- and the model's own validation is what tells the operator a section was wrong.
    def coerce(sections)
      Array(sections).first(MAX_SECTIONS).filter_map { |section| coerce_section(section) }
    end

    # The errors a page should refuse to save with. Separate from `coerce` because coercion cannot report:
    # once an unknown type is dropped the operator would see their section vanish with no explanation.
    def errors(sections)
      Array(sections).each_with_index.flat_map { |section, index| section_errors(section, index) }
    end

    private

    def coerce_section(section)
      section = section.to_h.stringify_keys if section.respond_to?(:to_h)
      return nil unless section.is_a?(Hash)

      type = section['type'].to_s
      return nil unless type?(type)

      base = { 'type' => type }
      fields_for(type).each do |field|
        value = clamp(section[field], field)
        base[field] = value if value.present?
      end
      base['items'] = coerce_items(section['items'], type) if itemised?(type)
      base
    end

    def coerce_items(items, type)
      Array(items).first(MAX_ITEMS).filter_map do |item|
        item = item.to_h.stringify_keys if item.respond_to?(:to_h)
        next unless item.is_a?(Hash)

        coerced = item_fields_for(type).each_with_object({}) do |field, acc|
          value = clamp(item[field], field)
          acc[field] = value if value.present?
        end
        coerced.presence
      end
    end

    # Every string is squeezed of control characters and truncated. The control-character strip matters
    # because a bidirectional override character in an Arabic page can reverse the visible order of a
    # sentence without changing a byte an operator can see.
    def clamp(value, field)
      return nil if value.nil?

      text = value.to_s.delete("\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f‪-‮⁦-⁩")
      text = text.strip
      text.truncate(LIMITS[field] || LIMITS['default'], omission: '')
    end

    def section_errors(section, index)
      section = section.to_h.stringify_keys if section.respond_to?(:to_h)
      label = "section #{index + 1}"
      return ["#{label} is not a section"] unless section.is_a?(Hash)

      type = section['type'].to_s
      return ["#{label} has an unknown type #{type.presence || '(blank)'}"] unless type?(type)

      source_errors(section, type, label) + metric_errors(section, type, label) +
        link_errors(section, type, label)
    end

    def source_errors(section, type, label)
      return [] unless type == 'catalogue'

      errors = []
      source = section['source'].to_s
      errors << "#{label} reads an unknown catalogue source #{source}" if source.present? && SOURCES.exclude?(source)
      style = section['style'].to_s
      errors << "#{label} uses an unknown style #{style}" if style.present? && STYLES.exclude?(style)
      errors
    end

    def metric_errors(section, type, label)
      return [] unless type == 'stats'

      Array(section['items']).filter_map do |item|
        metric = item_value(item, 'metric')
        next if metric.blank? || METRICS.include?(metric)

        "#{label} reads an unknown metric #{metric}"
      end
    end

    # A link an operator typed reaches a public `href`. `javascript:` and `data:` in an href are script
    # execution, so the scheme is allowlisted here rather than hoped about in the view.
    #
    # EVERY FIELD WHOSE NAME ENDS IN `_target` IS A LINK TARGET, on the section itself as well as on its
    # items -- which is how `hero.primary_target` and `hero.secondary_target` are covered. They were not
    # while nothing could edit a section; W4's page editor is what makes an operator-typed hero target
    # reachable, so the rule is matched on the field name rather than on a list somebody has to remember to
    # extend when a type gains a link.
    def link_errors(section, type, label)
      targets = target_fields(fields_for(type)).map { |field| section[field] }
      targets += Array(section['items']).flat_map do |item|
        target_fields(item_fields_for(type)).map { |field| item_value(item, field) }
      end

      targets.filter_map do |target|
        text = target.to_s
        next if text.blank? || Marketing::LinkTarget.valid?(text)

        "#{label} has a link target that is not allowed: #{text}"
      end
    end

    def target_fields(names) = names.grep(/_target\z/)

    # An item arrives as a Hash from jsonb or as ActionController::Parameters from the form, and the two
    # disagree about string and symbol keys. One reader, so neither caller has to care.
    def item_value(item, field)
      return nil unless item.respond_to?(:[])

      (item[field] || item[field.to_sym]).to_s
    end
  end
end
