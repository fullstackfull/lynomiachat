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
    # The home page's opening block, which OWNS the page's heading and standfirst rather than repeating
    # them: `custom/app/views/marketing/shared/_page.html.erb` hands `page.heading` and `page.lede` to a
    # leading hero instead of printing them above it, so there is still one H1 stored in one place.
    #
    # `highlight` is a phrase OUT OF THAT HEADING. The renderer finds its first literal occurrence and sets
    # it on the one coloured block the page is allowed, which is how the headline gets a focal point without
    # the operator writing markup -- and the heading stays one plain, escaped string.
    'hero' => {
      fields: %w[kicker highlight primary_label primary_target secondary_label secondary_target]
    },
    # A heading and a paragraph -- the plainest section there is, and the one the About page opens with.
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
    # A product walkthrough: ONE GENUINE SCREENSHOT of the running application, and the numbered steps
    # the markers drawn on it point at.
    #
    # THE STEPS ARE ROWS, NOT PIXELS, and that is the whole reason this is a type of its own rather than an
    # `image` with a `cards` block under it. A number burnt into a PNG is not text: a screen reader cannot
    # read it, a translator cannot translate it, a search engine cannot index it, and a reader who enlarges
    # their type gets a bigger blurry number rather than a bigger sentence. So the picture carries the
    # markers and the markup carries the words, the two are numbered in step, and the explanation survives
    # with the image switched off.
    #
    # `media_position` is what lets consecutive walkthroughs alternate the screenshot left and right down a
    # page instead of stacking into a column of identical slabs. It is presentation only -- the step list is
    # always the same markup in the same order, so the reading order never depends on it.
    'walkthrough' => {
      fields: %w[heading lede attachment_id alt media_position],
      items: %w[title body]
    },
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
    'faq' => { fields: %w[heading] },
    # THE MOVING CHANNEL STRIP. Operator copy only: the marks themselves come from
    # Marketing::ChannelBrand, keyed by the Marketing::Catalog channel ids, for the same reason the
    # catalogue's states are not editable -- a logo is a product fact, and an operator should not be able
    # to edit WhatsApp's mark onto the LINE entry.
    'channel_strip' => { fields: %w[heading lede] },
    # ONE GENUINE PRODUCT SCREENSHOT BESIDE THE CLAIM IT EVIDENCES, alternating down the page.
    #
    # It is not `walkthrough`: a walkthrough's picture carries numbered markers and its items ARE those
    # markers, so the two must agree. A showcase's picture carries nothing, its items are the capability's
    # own points, and its job is to show the reader the screen they will actually be working in. Trying to
    # serve both from one type meant either numbering points that nothing on the image pointed at, or
    # shipping a figure with no explanation beside it.
    'showcase' => {
      fields: %w[kicker heading lede attachment_id alt media_position link_label link_target],
      items: %w[title body]
    },
    # How the channels converge: sources on one side, the one inbox on the other, drawn rather than
    # described. The operator owns the labels; which channels appear comes from the catalogue. The three
    # `items` are what the inbox does to a conversation once it arrives -- they fall back to the locale
    # file, so a flow block added with no items still reads.
    'flow' => { fields: %w[heading lede inbox_label outbox_label], items: %w[title] }
  }.freeze

  # The only values `catalogue.source` may take: the catalogue's own collections.
  SOURCES = %w[features channels solutions integrations].freeze

  # How a catalogue block is drawn. `cards` is the index grid, `chips` an inline strip, `list` a
  # rule-separated two-column list. All three read the same entries, so an operator choosing between them
  # changes presentation and never content -- which is what lets the home page's two consecutive catalogue
  # blocks look like two sections rather than one long field of identical cards.
  STYLES = %w[cards chips list].freeze

  # Where a walkthrough's screenshot sits. `start`/`end` rather than left/right because the page is rendered
  # in both directions and a walkthrough whose image is pinned to the physical left would sit on the wrong
  # side of the Arabic page; `top` puts it across the content width above the steps, which is the only one of
  # the three a screenshot of a WHOLE SCREEN stays readable in.
  MEDIA_POSITIONS = %w[start end top].freeze

  # The only metrics a stat may read. A metric nobody implemented would render blank.
  METRICS = %w[channel_count feature_count locale_count].freeze

  # THE FIELD EACH SECTION IS DRAWN ON, which is a property of the SEQUENCE and so cannot live in a partial.
  # Every block used to sit in one measured column on one colour, separated from its neighbour by a hairline:
  # nine sections, one scale, one surface, and nothing to tell a reader where a subject ended. Each section is
  # now a full-bleed band, and consecutive bands alternate between paper and mist, so the boundary is a change
  # of field rather than a 1px rule.
  #
  # `stats` is the exception and keeps the ink field: on the home page it follows the hero and is that hero's
  # evidence. Keying that off the TYPE rather than off the position means a page that opens some other way
  # still gets a coherent band.
  INK_TYPES = %w[stats].freeze

  BANDS = { ink: 'bg-lyn-ink', paper: 'bg-lyn-paper', mist: 'bg-lyn-mist' }.freeze

  MAX_SECTIONS = 24
  MAX_ITEMS = 24
  LIMITS = { 'body' => 4000, 'lede' => 1200, 'default' => 300 }.freeze

  class << self
    def type?(type) = TYPES.key?(type.to_s)

    def fields_for(type) = TYPES.fetch(type.to_s, {})[:fields] || []

    def item_fields_for(type) = TYPES.fetch(type.to_s, {})[:items] || []

    def itemised?(type) = item_fields_for(type).any?

    # Each section paired with the background its band is drawn on. The alternation restarts per call, which
    # is what a page wants: shared/_page.html.erb renders a leading hero itself and hands the REST here, so
    # the first band below the hero is always paper.
    def banded(sections)
      step = -1

      Array(sections).map do |section|
        next [section, BANDS[:ink]] if INK_TYPES.include?(section['type'].to_s)

        step += 1
        [section, BANDS[step.even? ? :paper : :mist]]
      end
    end

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
      # THE ENRICHMENT MARKER, allowed on every type rather than listed per type.
      #
      # `Marketing::PageEnrichment` adds a section to a page that ALREADY EXISTS -- which the content seeder
      # deliberately will not do, because it never overwrites an operator's row. Being able to run that
      # safely, twice, on a live site needs one thing: a way to recognise a section this repository added, so
      # a second run can leave it alone instead of adding it again. That is this key, and it survives `coerce`
      # for the same reason `type` does.
      #
      # It is NOT operator copy and nothing renders it. An operator who removes an enriched section removes
      # its key with it, which is the correct outcome: the enrichment is declared applied only while the
      # section is on the page, and a deliberate deletion is not something to undo on the next deploy -- see
      # the `--readd` flag, which is how an operator asks for it back on purpose.
      key = section['key'].to_s.strip
      base['key'] = key if key.present? && key.length <= 120
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
        link_errors(section, type, label) + media_position_errors(section, type, label)
    end

    def media_position_errors(section, type, label)
      return [] unless type == 'walkthrough'

      position = section['media_position'].to_s
      return [] if position.blank? || MEDIA_POSITIONS.include?(position)

      ["#{label} puts its screenshot on an unknown side #{position}"]
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
