class CustomMarkdownRenderer < CommonMarker::HtmlRenderer
  include MarkdownRendererUrlSanitizer
  include MarkdownRendererFenceInfoEscaping

  CONFIG_PATH = Rails.root.join('config/markdown_embeds.yml')

  # Documentation media (docs/documentation-v2/R2-MEDIA-CONTRACT.md item 10): an article references an image by
  # a stable corpus key, never a URL, a blob id or an ActiveStorage signed id -- a signed id is a verifier over
  # the blob primary key keyed from secret_key_base, so a committed URL would be valid in exactly one database.
  MEDIA_SCHEME = 'media:'.freeze

  # The resolver is passed in rather than reached for, and it lives for exactly one article render, which is what
  # makes an article with twenty images two queries instead of twenty (R2-MEDIA-INTERFACE.md section 2.4). A
  # thread-local or a Current attribute would let a render path resolve a portal with no visible dependency.
  # Defaults to nil so every existing caller -- the message path, the specs -- keeps working untouched.
  def initialize(media: nil, **)
    @media = media
    super(**)
  end

  def self.config
    @config ||= YAML.load_file(CONFIG_PATH)
  end

  def self.embed_regexes
    @embed_regexes ||= config.transform_values { |embed_config| Regexp.new(embed_config['regex']) }
  end

  # Matches columnResizing({ cellMinWidth: 50 }) in @chatwoot/prosemirror-schema
  # so cells without an explicit colwidth render the same minimum here as in the editor.
  TABLE_CELL_MIN_WIDTH_PX = 50
  COLWIDTHS_COMMENT = /<!--cw-colwidths:([\d,]+)-->/

  # The article editor serializes column widths as a `<!--cw-colwidths:...-->` HTML
  # comment immediately before each resized table. Capture it (emitting nothing) so the
  # next `table` can size itself; any other raw HTML keeps its default rendering.
  def html(node)
    match = node.string_content.match(COLWIDTHS_COMMENT)
    return super unless match

    @pending_colwidths = match[1].split(',').map(&:to_i)
  end

  def table(node)
    widths = @pending_colwidths
    @pending_colwidths = nil

    if sized_widths?(widths)
      out(table_wrapper_open(widths))
      out(inject_table_sizing(capture_html { super(node) }, widths))
    else
      out('<div class="tableWrapper">')
      super
    end
    out('</div>')
  end

  def text(node)
    content = node.string_content

    if content.include?('^')
      split_content = parse_sup(content)
      out(split_content.join)
    else
      out(escape_html(content))
    end
  end

  def link(node)
    return if surrounded_by_empty_lines?(node) && render_embedded_content(node)

    # If it's not a supported embed link, render normally
    super
  end

  def image(node)
    url = node.url.to_s
    return media_image(node, url.delete_prefix(MEDIA_SCHEME)) if url.start_with?(MEDIA_SCHEME)

    src = sanitized_href(node.url)
    width = extract_image_width(src)
    plain do
      out(%(<img src="#{src}"))
      out(' alt="', :children, '"')
      out(%( title="#{escape_html(node.title)}")) if node.title.present?
      out(%( style="width: #{width}; max-width: 100%; height: auto;")) if width
      out(' />')
    end
  end

  private

  # R2: a documentation image is a `media:` key resolved to the app-owned, same-origin delivery route, so a data
  # URI has no use in an article and would bypass every control the seed boundary enforces -- content type, byte
  # cap, raster-only, required alt -- while being permanent once committed to git. With no img-src in the
  # enforcing CSP (config/initializers/content_security_policy.rb:15-18) the renderer's own URL handling is the
  # only thing constraining where an article image loads from.
  #
  # ARTICLE SCOPE ONLY. The message and email renderer keeps the exception, because the agent composer and the
  # message-signature editor really do produce inline base64 images; BaseMarkdownRenderer does not override this.
  def permitted_data_image?(_url)
    false
  end

  # width/height are the blob's INTRINSIC pixel dimensions, so the browser can derive the aspect ratio and
  # reserve the right box before the bytes arrive. The displayed width is then Tailwind preflight's
  # `img { max-width: 100%; height: auto; }` (app/javascript/portal/application.scss:2). There is deliberately no
  # author-chosen width: `?cw_image_width=` cannot ride on a `media:` key, because URI.parse puts the whole
  # remainder in `opaque` and leaves `query` nil (R2-MEDIA-INTERFACE.md sections 0.4 and 2.5).
  #
  # They may be nil when libvips is absent on the host: ActiveStorage swallows the LoadError with one info log
  # (activestorage-7.2.3.2/lib/active_storage/analyzer/image_analyzer/vips.rb:14-20), which is a measured
  # framework behaviour and not a speculative guard. MediaSeeder reports the count so it is visible at seed time.
  def media_image(node, key)
    image = @media&.resolve(key)
    # An unresolved key is a corpus defect the seed boundary should already have refused, so the runtime only has
    # to be inert and diagnosable. No `src=""` -- an empty src re-requests the current page in several browsers.
    # escape_html turns the key's `>` into `&gt;`, so a key cannot close the comment it is reported in.
    return out("<!-- media: unresolved key #{escape_html(key)} -->") if image.nil?

    plain do
      out(%(<img src="#{escape_href(image.path)}"))
      out(' alt="', :children, '"')
      out(%( title="#{escape_html(node.title)}")) if node.title.present?
      out(%( width="#{image.width}" height="#{image.height}")) if image.width.present? && image.height.present?
      out(' loading="lazy" decoding="async" />')
    end
  end

  def sized_widths?(widths)
    widths.is_a?(Array) && widths.any? { |w| w.to_i.positive? }
  end

  def fully_sized?(widths)
    widths.all? { |w| w.to_i.positive? }
  end

  # Fully-sized tables hug their exact width so the card doesn't trail empty space;
  # partial tables stay a plain full-width card so flexible columns can expand.
  def table_wrapper_open(widths)
    return '<div class="tableWrapper">' unless fully_sized?(widths)

    %(<div class="tableWrapper" style="width: #{total_width(widths)}px; max-width: 100%;">)
  end

  # Let the gem render the whole table, then splice a <colgroup> and sizing style
  # into the opening <table> tag. Delegating the row/cell/tbody/alignment markup to
  # super keeps this working across commonmarker upgrades.
  # `!important` overrides the portal's `[&_table]:!min-w-full` Tailwind rule.
  def inject_table_sizing(html, widths)
    opening = %(<table style="#{table_sizing_style(widths)}">\n#{colgroup_html(widths)})
    html.sub(/<table[^>]*>\n?/, opening)
  end

  # Capture everything `super` writes by swapping the renderer's output buffer.
  def capture_html
    original = @stream
    @stream = StringIO.new(+'')
    yield
    @stream.string
  ensure
    @stream = original
  end

  # Total table width: each column's saved width, or the cell min for unsized ones.
  def total_width(widths)
    widths.sum { |w| w.to_i.positive? ? w.to_i : TABLE_CELL_MIN_WIDTH_PX }
  end

  # Fully sized → lock to the exact total (min-width too, so a narrow saved width
  # beats the portal's `[&_table]:!min-w-full`). Partial → `max(100%, total)` fills
  # the container (flexible columns) yet scrolls when the sized columns exceed it.
  def table_sizing_style(widths)
    total = total_width(widths)
    return "table-layout: fixed; min-width: max(100%, #{total}px) !important;" unless fully_sized?(widths)

    "table-layout: fixed; width: #{total}px !important; min-width: #{total}px !important;"
  end

  def colgroup_html(widths)
    cols = widths.map { |w| w.to_i.positive? ? %(<col style="width: #{w.to_i}px;">) : '<col>' }
    "<colgroup>#{cols.join}</colgroup>\n"
  end

  def extract_image_width(src)
    extract_px_param(src, 'cw_image_width')
  end

  def query_param(src, key)
    query = URI.parse(src).query
    query && CGI.parse(query)[key]&.first
  rescue URI::InvalidURIError
    nil
  end

  def extract_px_param(src, key)
    return unless query_param(src, key) =~ /\A(\d+)px\z/

    px = Regexp.last_match(1).to_i
    "#{px}px" if px.between?(1, 2000)
  end

  def surrounded_by_empty_lines?(node)
    prev_node_empty?(node.previous) && next_node_empty?(node.next)
  end

  def prev_node_empty?(prev_node)
    prev_node.nil? || node_empty?(prev_node)
  end

  def next_node_empty?(next_node)
    next_node.nil? || node_empty?(next_node)
  end

  def node_empty?(node)
    (node.type == :text && node.string_content.strip.empty?) || (node.type != :text)
  end

  def render_embedded_content(node)
    link_url = node.url
    embed_html = find_matching_embed(link_url)

    return false unless embed_html

    out(apply_embed_width(embed_html, link_url))
    true
  end

  # The editor stores a resized embed's width (cw_video_width) on the link.
  # Percentage padding (aspect-ratio boxes) resolves against the containing
  # block, so the saved width goes on a wrapper and the root fills it.
  def apply_embed_width(html, link_url)
    width = extract_px_param(link_url, 'cw_video_width')
    return html unless width

    fragment = Nokogiri::HTML5.fragment(html)
    root = fragment.elements.first
    root['style'] = [root['style'], 'width: 100%; height: auto;'].compact.join(' ')
    %(<div style="width: #{width}; max-width: 100%;">#{fragment.to_html}</div>)
  end

  def find_matching_embed(link_url)
    self.class.embed_regexes.each do |embed_key, regex|
      match = link_url.match(regex)
      next unless match

      return render_embed_from_match(embed_key, match)
    end

    nil
  end

  def render_embed_from_match(embed_key, match_data)
    embed_config = self.class.config[embed_key]
    return nil unless embed_config

    template = embed_config['template']
    # Use gsub (not format) so CSS `%` values in templates don't need escaping.
    # Captured values are HTML-escaped since they land inside HTML attribute contexts.
    match_data.named_captures.each do |var_name, value|
      template = template.gsub("%{#{var_name}}", CGI.escapeHTML(value))
    end
    template
  end

  def parse_sup(content)
    content.split(/(\^[^\^]+\^)/).map do |segment|
      if segment.start_with?('^') && segment.end_with?('^')
        "<sup>#{escape_html(segment[1..-2])}</sup>"
      else
        escape_html(segment)
      end
    end
  end
end
