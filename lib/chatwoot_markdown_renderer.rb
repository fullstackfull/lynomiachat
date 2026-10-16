class ChatwootMarkdownRenderer
  def initialize(content)
    @content = content
  end

  def render_message(hardbreaks: false)
    markdown_renderer = BaseMarkdownRenderer.new(options: hardbreaks ? [:HARDBREAKS] : :DEFAULT)
    doc = CommonMarker.render_doc(@content, :DEFAULT, [:strikethrough, :autolink])
    html = markdown_renderer.render(doc)
    render_as_html_safe(html)
  end

  # `media:` keeps every existing caller and spec working unchanged; only the article controller passes a
  # resolver, because only a documentation portal has media to resolve.
  def render_article(media: nil)
    markdown_renderer = CustomMarkdownRenderer.new(media: media)
    doc = CommonMarker.render_doc(@content, :DEFAULT, [:table])
    html = markdown_renderer.render(doc)

    render_as_html_safe(html)
  end

  def render_markdown_to_plain_text
    CommonMarker.render_doc(@content, :DEFAULT).to_plaintext
  end

  private

  def render_as_html_safe(html)
    # rubocop:disable Rails/OutputSafety
    html.html_safe
    # rubocop:enable Rails/OutputSafety
  end
end
