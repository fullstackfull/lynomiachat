module MarkdownRendererUrlSanitizer
  # Match CommonMarker's native safe renderer while retaining application protocols such as mention://.
  DANGEROUS_URL_PATTERN = /\A(?:javascript:|vbscript:|file:|data:)/i
  SAFE_DATA_IMAGE_PATTERN = %r{\Adata:image/(?:png|gif|jpeg|webp)}i

  def link(node)
    out('<a href="', sanitized_href(node.url), '"')
    out(' title="', escape_html(node.title), '"') if node.title.present?
    out('>', :children, '</a>')
  end

  private

  def sanitized_href(url)
    url = url.to_s
    return '' if url.match?(DANGEROUS_URL_PATTERN) && !permitted_data_image?(url)

    escape_href(url)
  end

  # The reply composer and the message-signature editor can both produce an inline base64 image, so the message
  # and email path keeps this exception -- spec/lib/base_markdown_renderer_spec.rb:85-89 pins it, and it must stay
  # green and unmodified, which is what proves this narrowing did not leak into the shared module.
  #
  # The ARTICLE path overrides this to false (CustomMarkdownRenderer#permitted_data_image?). A method defined on
  # the class wins over one from an included module, so the closure is scoped to the one renderer instead of being
  # the universal sanitizer the owner ruled against. Editing SAFE_DATA_IMAGE_PATTERN or the condition above would
  # change the conversation and email path too, which is exactly why this seam exists rather than that edit.
  def permitted_data_image?(url)
    url.match?(SAFE_DATA_IMAGE_PATTERN)
  end
end
