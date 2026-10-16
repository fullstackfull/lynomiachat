require 'rails_helper'

# ADVERSARIAL suite for the markdown render boundary (docs/documentation-v2/P0-PRODUCTION-HARDENING.md).
#
# WHY THIS FILE EXISTS. commonmarker's Ruby HTML renderer wrote a fenced code block's INFO STRING into a class
# attribute without escaping, while cmark's own C renderer escapes it (ext/commonmarker/html.c). That divergence
# was a live stored XSS on every article and every message: an author-supplied language tag could close the
# <code> and the <pre> and open a <script>. Three separate audits concluded this path was safe because raw HTML is
# omitted -- all three were reasoning about the `html`/`inline_html` node types and none read `code_block`. So
# these are not "tests for a fix"; they are the assertions whose absence let the hole ship.
#
# HOW THEY ASSERT. Through ChatwootMarkdownRenderer, the real public boundary, so each example exercises the same
# extension set and the same html_safe call production uses -- and then through Nokogiri::HTML5, because the only
# question that matters is what a browser's parser builds from the bytes. `fragment.css('*').map(&:name)` is the
# central assertion: it names every element in the document, so an injected one cannot hide inside a passing
# substring match, and an attribute list proves no event handler was created. Earlier drafts of this file matched
# substrings and reported safe output as failures (a percent-encoded quote inside a correctly quoted href still
# contains the characters `onmouseover=`); structural assertions do not have that failure mode.
# Closures rather than constants: RSpec/LeakyConstantDeclaration is right that a spec file should not leave
# breakout on Object, and a `let` cannot be used because the payload table is iterated while the examples are
# being defined.
breakout = 'x"></code></pre><script>alert(1)</script><pre><code'

# [description, info string as authored, the class value a browser must end up with]
fence_payloads = [
  ['closing the code element to open a script', breakout, "language-#{breakout}"],
  # cmark decodes entities in the info string BEFORE the renderer sees it, so a filter that scans the Markdown
  # source for a literal quote never fires. This is the bypass for the obvious wrong fix.
  ['an HTML-entity-encoded info string', 'x&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;',
   'language-x"><script>alert(1)</script>'],
  ['a self-closing event-handler element', %(x"><svg/onload=alert(1)>), %(language-x"><svg/onload=alert(1)>)],
  ['a single-quoted attribute break', "x'><script>alert(1)</script>", "language-x'><script>alert(1)</script>"],
  # Truncated at the space, so only `x"` reaches the attribute -- but that quote alone would still have ended
  # the class value and made `onmouseover` a real attribute.
  ['an added event-handler attribute', 'x" onmouseover="alert(1)', 'language-x"']
]

# The subject is a boundary shared by two renderer classes and three callers, not one class.
# rubocop:disable RSpec/DescribeClass
describe 'markdown render security' do
  # rubocop:enable RSpec/DescribeClass
  def article(markdown)
    ChatwootMarkdownRenderer.new(markdown).render_article
  end

  def message(markdown)
    ChatwootMarkdownRenderer.new(markdown).render_message
  end

  def fragment(html)
    Nokogiri::HTML5.fragment(html)
  end

  # The central payload closes the attribute, then both elements the renderer opened, then opens a script. It
  # contains NO WHITESPACE, which matters: the renderer keeps only the first whitespace-delimited token of the
  # info string, so a payload with a space in it is truncated and a filter tuned to `<script ` never fires here.

  shared_examples 'an escaped fence info string' do |render|
    fence_payloads.each do |description, info, expected_class|
      it "cannot inject through #{description}" do
        parsed = fragment(public_send(render, "```#{info}\nbody\n```\n"))
        code = parsed.at_css('code')

        # Exactly two elements, in this order: nothing was closed early and nothing new was opened.
        expect(parsed.css('*').map(&:name)).to eq(%w[pre code])
        # The one attribute, with the payload intact as DATA. Round-tripping it through the parser proves the
        # escaping is both sufficient (no breakout) and exact (no mangling).
        expect(code.attributes.keys).to eq(['class'])
        expect(code['class']).to eq(expected_class)
        expect(parsed.text).to eq("body\n\n")
      end
    end

    it 'cannot inject through a tilde-fenced block' do
      # Tilde fences take an info string that may contain backticks, so they are a separate parse path.
      parsed = fragment(public_send(render, "~~~#{breakout}\nbody\n~~~\n"))

      expect(parsed.css('*').map(&:name)).to eq(%w[pre code])
      expect(parsed.at_css('code')['class']).to eq("language-#{breakout}")
    end
  end

  shared_examples 'a working code block' do |render|
    it 'keeps the language class for an ordinary info string' do
      expect(public_send(render, "```ruby\nputs 1\n```\n")).to include('class="language-ruby"')
    end

    it 'keeps only the first token of the info string, as before' do
      expect(public_send(render, "```ruby extra meta\ncode\n```\n")).to include('class="language-ruby"')
    end

    it 'renders a fence with no info string without a class attribute' do
      rendered = public_send(render, "```\ncode\n```\n")

      expect(rendered).to include('<code>')
      expect(rendered).not_to include('class="language-')
    end

    it 'keeps a language tag containing a slash usable' do
      # escape_html here runs with cmark's `secure` flag off, so `/` and `'` stay literal. Pinned because a
      # future switch to CGI.escapeHTML would change these bytes without changing the security property.
      expect(public_send(render, "```text/plain\ncode\n```\n")).to include('class="language-text/plain"')
    end

    it 'still escapes the code body' do
      rendered = public_send(render, "```\n<script>alert(1)</script>\n```\n")

      expect(rendered).not_to include('<script>')
      expect(rendered).to include('&lt;script&gt;')
    end

    it 'does not double-escape an ampersand in the info string' do
      # The fix must escape once. `&amp;amp;` would be a silent corruption of the author's content, which a
      # structural assertion alone would not catch -- hence both the bytes and the parsed value.
      rendered = public_send(render, "```a&b\ncode\n```\n")

      expect(rendered).to include('language-a&amp;b')
      expect(rendered).not_to include('&amp;amp;')
      expect(fragment(rendered).at_css('code')['class']).to eq('language-a&b')
    end

    it 'preserves the code body verbatim apart from HTML escaping' do
      rendered = public_send(render, "```ruby\nx = { a: 1 }\n```\n")

      expect(rendered).to include('x = { a: 1 }')
    end
  end

  describe 'the article path' do
    it_behaves_like 'an escaped fence info string', :article
    it_behaves_like 'a working code block', :article
  end

  describe 'the message path' do
    it_behaves_like 'an escaped fence info string', :message
    it_behaves_like 'a working code block', :message
  end

  # BaseMarkdownRenderer has a third caller: Messages::MarkdownRendererService#render_html, which renders outbound
  # message content for Channel::Email and Channel::WebWidget. Same renderer, same defect, a different entry
  # point -- so it is asserted at its own boundary rather than assumed to be covered by the two above.
  describe 'the channel HTML path' do
    it 'escapes the fence info string for an email channel' do
      rendered = Messages::MarkdownRendererService.new("```#{breakout}\nbody\n```\n", 'Channel::Email').render

      expect(fragment(rendered).css('*').map(&:name)).to eq(%w[pre code])
      expect(fragment(rendered).at_css('code')['class']).to eq("language-#{breakout}")
    end

    it 'escapes the fence info string for a web widget channel' do
      rendered = Messages::MarkdownRendererService.new("```#{breakout}\nbody\n```\n", 'Channel::WebWidget').render

      expect(fragment(rendered).css('*').map(&:name)).to eq(%w[pre code])
    end
  end

  # The owner's requirement was explicit: no XSS through headings, links, images, tables, code blocks or
  # attributes. Code blocks are above; these are the rest, pinned so a future change to the shared boundary
  # cannot quietly regress one of them. Each asserts the mechanism that makes the construct safe, not merely the
  # absence of a string.
  describe 'other constructs on the article path' do
    it 'escapes a quote in heading text' do
      expect(article(%(# A "quoted" heading\n))).to eq("<h1>A &quot;quoted&quot; heading</h1>\n")
    end

    it 'omits raw HTML inside a heading rather than rendering it' do
      rendered = article(%(# A <b>bold</b> heading\n))

      expect(fragment(rendered).css('*').map(&:name)).to eq(['h1'])
      expect(rendered).to include('<!-- raw HTML omitted -->')
    end

    it 'blanks a javascript: link' do
      expect(article('[x](javascript:alert(1))')).to include('href=""')
    end

    it 'blanks a vbscript: link' do
      expect(article('[x](vbscript:alert(1))')).to include('href=""')
    end

    it 'blanks a file: link' do
      expect(article('[x](file:///etc/passwd)')).to include('href=""')
    end

    it 'keeps an ordinary https link' do
      expect(article('[x](https://example.com/a?b=1)')).to include('href="https://example.com/a?b=1"')
    end

    it 'percent-encodes a quote in a link target instead of ending the attribute' do
      link = fragment(article('[x](https://example.com/"onmouseover=alert(1))')).at_css('a')

      # The payload survives as part of the href VALUE -- which is correct and safe. What must not exist is a
      # second attribute, which is what an unescaped quote would have produced.
      expect(link.attributes.keys).to eq(['href'])
      expect(link['href']).to eq('https://example.com/%22onmouseover=alert(1)')
    end

    it 'escapes a quote in a link title instead of ending the attribute' do
      link = fragment(article(%([x](https://example.com "a\\"b")))).at_css('a')

      expect(link.attributes.keys).to eq(%w[href title])
      expect(link['title']).to eq('a"b')
    end

    # DATA: URLs WERE DELIBERATELY PERMITTED FOR FOUR IMAGE SUBTYPES, AND THE ARTICLE PATH NO LONGER PERMITS THEM.
    #
    # The example that stood here pinned the opposite -- that `render_article` emits
    # `src="data:image/png;base64,…"` -- and its own comment said why it was only pinned and not changed: "a
    # data: image bypasses upload validation, type checks, EXIF stripping and review -- recorded for the media
    # contract rather than changed inside a security hotfix". The media contract has now changed it
    # (R2-MEDIA-CONTRACT.md 2.1, arbitrated to R2 at article-renderer scope), so the assertion is inverted here
    # rather than deleted: the old expectation is quoted above so the reversal is legible.
    #
    # Scope is the whole point. The closure is a `permitted_data_image?` seam in the shared module overridden to
    # false in CustomMarkdownRenderer only -- a method on the class wins over one from an included module -- so
    # the conversation and email path keeps the exception the agent composer and the message-signature editor
    # really need. spec/lib/base_markdown_renderer_spec.rb:85-89 pins that and must stay green UNMODIFIED; that
    # is the containment proof, and it is why this is not the universal sanitizer the owner ruled against.
    it 'blanks a data:image/png URL on the article path, which the media contract closed' do
      rendered = article('![a](data:image/png;base64,iVBORw0KGgo=)')

      expect(rendered).not_to include('data:image/png')
      expect(rendered).to include('src=""')
    end

    it 'still permits a data:image/png URL on the message path, which is the containment boundary' do
      expect(message('![a](data:image/png;base64,iVBORw0KGgo=)'))
        .to include('src="data:image/png;base64,iVBORw0KGgo="')
    end

    it 'blanks a data:text/html URL' do
      expect(article('[x](data:text/html,alert)')).to include('href=""')
    end

    it 'blanks a data:image/svg+xml URL' do
      # SVG is not in the permitted subtypes, and it is the one image type that can carry script.
      expect(article('![a](data:image/svg+xml;base64,PHN2Zz4=)')).to include('src=""')
    end

    it 'escapes a quote in an image title instead of ending the attribute' do
      img = fragment(article(%(![a](https://example.com/i.png "t\\"x")))).at_css('img')

      expect(img.attributes.keys).to eq(%w[src alt title])
      expect(img['title']).to eq('t"x')
    end

    it 'drops raw HTML from image alt text' do
      parsed = fragment(article('![<img src=x onerror=alert(1)>](https://example.com/i.png)'))

      expect(parsed.css('*').map(&:name)).to eq(%w[p img])
      expect(parsed.at_css('img')['alt']).to eq('')
    end

    it 'bounds the image width query parameter to a pixel value' do
      img = fragment(article('![a](https://example.com/i.png?cw_image_width=9px;background:url\(x\))')).at_css('img')

      # The injection string stays inside the src, where it is inert; the style it was aiming at is rebuilt from
      # the one bounded integer the sanitizer accepted.
      expect(img['style']).to eq('width: 9px; max-width: 100%; height: auto;')
      expect(img.attributes.keys).to eq(%w[src alt style])
    end

    it 'omits raw HTML inside a table cell' do
      parsed = fragment(article("| a | b |\n| --- | --- |\n| <script>alert(1)</script> | y |\n"))

      expect(parsed.css('script')).to be_empty
      expect(parsed.at_css('td').text).to eq('alert(1)')
    end

    it 'still omits raw HTML, which is the intentional behaviour' do
      rendered = article('<script>alert(1)</script>')

      expect(rendered).to eq("<!-- raw HTML omitted -->\n")
    end
  end

  describe 'other constructs on the message path' do
    it 'omits raw HTML inside a heading' do
      parsed = fragment(message(%(# <b>x</b>\n)))

      expect(parsed.css('*').map(&:name)).to eq(['h1'])
      expect(parsed.text).to eq("x\n")
    end

    it 'blanks a javascript: link' do
      expect(message('[x](javascript:alert(1))')).to include('href=""')
    end

    it 'percent-encodes a quote in an autolinked URL' do
      link = fragment(message('https://example.com/"onmouseover=alert(1)')).at_css('a')

      expect(link.attributes.keys).to eq(['href'])
      expect(link['href']).to eq('https://example.com/%22onmouseover=alert(1)')
    end

    it 'renders strikethrough without injection' do
      parsed = fragment(message('~~<script>alert(1)</script>~~'))

      expect(parsed.css('*').map(&:name)).to eq(%w[p del])
      expect(parsed.css('script')).to be_empty
    end

    it 'still omits raw HTML' do
      expect(message('<script>alert(1)</script>')).not_to include('<script>')
    end
  end

  # R1.3 / R1.4 (docs/documentation-v2/08-orchestrator-rulings.md). The embed providers are the one place in this
  # stack where a TEMPLATE, not an author's text, decides what tags reach a public page -- the author only has to
  # supply a matching URL. Two providers emitted `<script src>` against this product's own origin and were
  # removed; these assertions are what keeps a third from arriving in a config edit that passes review.
  #
  # The link form matters and the first draft of this file got it wrong. `render_article` is built with
  # `extensions: [:table]` and NOT `:autolink`, so a bare URL on its own line is plain text and no embed fires at
  # all -- the examples passed while rendering a single `<p>` and proved nothing. Every example below therefore
  # uses explicit `[text](url)` syntax and asserts the EXACT element set, so an embed that silently stops firing
  # fails the example instead of passing it.
  describe 'markdown embed providers' do
    # [provider key, a URL it matches, the elements a browser must build]
    #
    # The trailing `p` on the iframe providers is real and not noise: the template is block-level, so the HTML
    # parser closes the paragraph the renderer opened at the `<div>` and opens a fresh empty one for what follows.
    # mp4 has no trailing `p` because `<video>` is permitted inside a paragraph and the parser does not split it.
    # Pinning the exact list is the point -- it is what makes a silently-no-longer-matching provider fail.
    provider_cases = [
      ['youtube', 'https://youtube.com/watch?v=dQw4w9WgXcQ', %w[p div iframe p]],
      ['loom', 'https://loom.com/share/abc123', %w[p div iframe p]],
      ['vimeo', 'https://vimeo.com/123456789', %w[p div iframe p]],
      ['mp4', 'https://example.com/video.mp4', %w[p video source]],
      ['arcade_tab', 'https://app.arcade.software/share/abc123?embed_mobile=tab', %w[p div iframe p]],
      ['arcade', 'https://app.arcade.software/share/abc123', %w[p div iframe p]],
      ['bunny', 'https://iframe.mediadelivery.net/embed/12345/abc-def', %w[p div iframe p]],
      ['guidejar', 'https://guidejar.com/guides/abc123', %w[p div iframe p]]
    ].freeze

    def embed(url)
      Nokogiri::HTML5.fragment(ChatwootMarkdownRenderer.new("\n\n[watch](#{url})\n\n").render_article)
    end

    it 'carries exactly the providers this ruling leaves in place' do
      expect(CustomMarkdownRenderer.config.keys).to match_array(provider_cases.map(&:first))
    end

    it 'has no template that emits a script tag' do
      offenders = CustomMarkdownRenderer.config.select { |_key, embed| embed['template'].include?('<script') }

      expect(offenders.keys).to be_empty
    end

    it 'no longer carries the two script-emitting providers' do
      expect(CustomMarkdownRenderer.config.keys).not_to include('wistia', 'github_gist')
    end

    provider_cases.each do |key, url, expected_elements|
      it "renders #{key} as #{expected_elements.join('/')} and nothing executable" do
        parsed = embed(url)

        # Exact set, so a provider that stopped matching fails here rather than passing on an empty <p>.
        expect(parsed.css('*').map(&:name)).to eq(expected_elements)
        expect(parsed.css('script')).to be_empty
      end
    end

    # The capture groups land inside HTML attributes, and the regexes exclude `&`, `/` and `?` from an id but not
    # `"` or `<`. `render_embed_from_match` runs each capture through CGI.escapeHTML; this is what proves it.
    it 'escapes a quote and a tag in a capture group instead of ending the src attribute' do
      parsed = embed(%(https://loom.com/share/abc"><script>alert(1)</script>))
      iframe = parsed.at_css('iframe')

      expect(parsed.css('*').map(&:name)).to eq(%w[p div iframe p])
      expect(iframe.attributes.keys).not_to include('onload', 'onerror')
      # Truncated at the `/` of `</script>`, because the loom regex's id group is `[^&/?]+`. That truncation is
      # incidental; the assertion that matters is the one above -- the payload is DATA in the attribute, and the
      # parser built no script element from it.
      expect(iframe['src']).to eq(%(https://www.loom.com/embed/abc"><script>alert(1)<))
    end

    # R1.4 names an onerror attribute specifically. Author HTML is OMITTED, not escaped, so the handler never
    # becomes an attribute on anything -- asserted structurally rather than by substring.
    it 'omits an author-written img carrying an onerror handler' do
      parsed = Nokogiri::HTML5.fragment(
        ChatwootMarkdownRenderer.new(%(<img src=x onerror="alert(1)">\n)).render_article
      )

      expect(parsed.css('*').map(&:name)).not_to include('img', 'script')
      expect(parsed.css('[onerror]')).to be_empty
    end
  end
end
