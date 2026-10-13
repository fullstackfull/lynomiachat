# The fenced-code-block language tag, escaped before it becomes an HTML attribute value.
#
# WHY THIS EXISTS. commonmarker renders the same AST with two renderers. The C one escapes a code block's info
# string before writing it into the opening tag (ext/commonmarker/html.c, `escape_html(html,
# node->as.code.info.data, first_tag)`). The Ruby one -- the only one this application uses -- writes it raw:
#
#   out(' class="language-', node.fence_info.split(/\s+/)[0], '">')
#     vendor/bundle/ruby/3.4.0/gems/commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb:100
#
# `Renderer#out` writes each argument straight to the output buffer, so an author who opens a fence with
# ```x"></code></pre><script>alert(1)</script> closes the attribute, closes both elements the renderer has just
# opened, and runs script. Raw HTML is already omitted on these paths and every other attribute they emit is
# escaped or sanitized; the code block's class attribute was the one that was not. This restores that parity --
# it introduces no new policy and changes no other node type.
#
# WHY IT LIVES HERE. vendor/bundle is a build artefact that the next `bundle install` rewrites, so a patch there
# would be both invisible and temporary. This sits beside MarkdownRendererUrlSanitizer, which already owns the
# same kind of boundary for href and src, and is included by the same two classes -- the only two renderers in
# the application that emit HTML.
#
# WHY NOT A SAFELIST SANITIZER AT ChatwootMarkdownRenderer#render_as_html_safe. That boundary also carries the
# config/markdown_embeds.yml templates, which deliberately emit <iframe> and <script> for video embeds, and it is
# shared with #render_message, which renders every conversation message and every reply email. A safelist there
# would silently drop working product features for a defect confined to one node type.
#
# The body of a code block was always escaped and still is. Only the attribute changes.
module MarkdownRendererFenceInfoEscaping
  # Mirrors CommonMarker::HtmlRenderer#code_block byte for byte apart from the escaping. `present?` stands in for
  # the gem's `fence_info && !fence_info.empty?`: cmark strips the info string while parsing, so the only values
  # that reach here are '' and a non-blank token list, for which the two tests agree.
  def code_block(node)
    block do
      if option_enabled?(:GITHUB_PRE_LANG)
        out("<pre#{sourcepos(node)}")
        out(' lang="', escaped_fence_language(node), '"') if node.fence_info.present?
        out('><code>')
      elsif node.fence_info.present?
        out("<pre#{sourcepos(node)}><code", ' class="language-', escaped_fence_language(node), '">')
      else
        out("<pre#{sourcepos(node)}><code>")
      end
      out(escape_html(node.string_content), '</code></pre>')
    end
  end

  private

  # One token, as before: a language tag is a single word and the gem has always discarded the rest of the line.
  def escaped_fence_language(node)
    escape_html(node.fence_info.split(/\s+/).first)
  end
end
