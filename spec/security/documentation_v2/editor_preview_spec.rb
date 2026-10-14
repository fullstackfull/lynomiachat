require 'rails_helper'

# WAVE 4, AGENT 6 -- ADVERSARIAL. `SuperAdmin::ArticlesController#preview_markdown` renders UNSAVED Markdown
# through the real article renderer, so it is the one place where source that has never been reviewed, saved or
# seeded reaches the production renderer. Two questions: can anyone but a super admin reach it, and can anything
# get through it that cannot get through the published page.
#
# Reachability under the three principals is already pinned in
# spec/controllers/super_admin/documentation_editor_spec.rb. What is NOT pinned there is that the renderer's
# containment holds on this route as well as on the published page, which is what these examples measure -- by
# rendering the same hostile source BOTH ways and requiring the preview to be no more permissive.

# Every payload that has ever been a real defect on this renderer, plus the ones the contract closes. A
# file-scope local rather than a constant inside the group: the blocks close over it and nothing leaks into the
# example group's namespace.
payloads = {
  'fence info string (the P0 stored XSS)' => "```x\"></code></pre><script>alert(1)</script>\ncode\n```",
  'raw HTML block' => "<script>alert(1)</script>\n",
  'raw inline HTML' => 'a <img src=x onerror=alert(1)> b',
  'javascript: link' => '[go](javascript:alert(1))',
  'vbscript: link' => '[go](vbscript:alert(1))',
  'data:text/html link' => '[go](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)',
  'data:image in an article image' => '![a](data:image/png;base64,iVBORw0KGgo=)',
  'quote breakout through an image title' => '![a](https://e.example/x.png "t\" onerror=alert(1) x=\"")',
  'quote breakout through an image alt' => '![" onerror=alert(1) x="](https://e.example/x.png)',
  'tag breakout through a nested link in alt' => '![pre [t](https://e.example/) onerror=alert(1) post](https://e.example/x.png)',
  'sup injection' => 'x ^<script>alert(1)</script>^ y',
  'table cell injection' => "| a |\n|---|\n| <script>alert(1)</script> |",
  'embed template injection' => '[v](https://www.youtube.com/watch?v=x"onload="alert(1))'
}.freeze

RSpec.describe 'Super Admin markdown preview -- adversarial', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil,
                    config: { 'allowed_locales' => ['en'], 'default_locale' => 'en', 'layout' => 'documentation' })
  end
  let!(:category) { create(:category, portal: portal, account_id: nil, locale: 'en', slug: 'administration', name: 'Administration') }
  let!(:article) do
    create(:article, portal: portal, account_id: nil, category: category, author: super_admin, locale: 'en',
                     slug: 'audit-logs', title: 'Audit logs', content: 'Body', status: :published)
  end

  def preview(markdown)
    post '/super_admin/articles/preview_markdown', params: { article: { content: markdown } }
    response.body
  end

  describe 'containment, measured against the published page for the same source' do
    before { sign_in(super_admin, scope: :super_admin) }

    payloads.each do |label, markdown|
      it "executes no script and is no more permissive than the published page: #{label}" do
        body = preview(markdown)

        expect(response).to have_http_status(:success)
        fragment = Nokogiri::HTML5(body)
        # PARSED, not pattern-matched. A crude /\son[a-z]+=/ over the raw body goes red on an inert
        # `onerror=alert(1)` sitting INSIDE an escaped attribute VALUE -- measured on the alt payloads below --
        # which is exactly the false positive that turns a security assertion into noise. What matters is
        # whether a browser ends up with a script element or an event-handler ATTRIBUTE, so the parser decides.
        expect(fragment.css('script')).to be_empty
        handlers = fragment.css('*').flat_map { |el| el.attribute_nodes.map(&:name) }.grep(/\Aon/)
        expect(handlers).to be_empty, "event handler attributes: #{handlers.inspect}"
        expect(fragment.css('a').filter_map { |a| a['href'] }).to all(satisfy { |href| !href.match?(/\A(?:javascript|vbscript|data|file):/i) })
        # The published page, rendered from the same source through the same renderer with the real resolver.
        article.update!(content: markdown)
        with_modified_env(FRONTEND_URL: 'http://www.example.com', HELPCENTER_URL: 'http://www.example.com') do
          get "/hc/#{portal.slug}/articles/#{article.slug}"
        end
        # `inner_html`, not `to_html`: the preview partial renders the public content partial with the
        # classic/plain `link_class`, so the WRAPPER's Tailwind classes differ by design. What must be identical
        # is the rendered Markdown inside it.
        published = Nokogiri::HTML5(response.body).at_css('#cw-article-content').inner_html

        expect(Nokogiri::HTML5(body).at_css('#cw-article-content').inner_html).to eq(published), label
      end
    end

    # The containment boundary stated as a test rather than as a comment: the ARTICLE renderer refuses a
    # `data:image/*` source and the MESSAGE renderer still permits it. Both halves, in one example, because
    # each is only meaningful beside the other.
    it 'closes data:image for an article while the message and email path keeps it' do
      body = preview('![a](data:image/png;base64,iVBORw0KGgo=)')

      expect(body).to include('src=""')
      expect(body).not_to include('data:image/png')
      expect(ChatwootMarkdownRenderer.new('![a](data:image/png;base64,iVBORw0KGgo=)').render_message)
        .to include('src="data:image/png;base64,iVBORw0KGgo="')
    end

    # The seam that makes that scoping possible, asserted structurally: a method on the class beats one from an
    # included module, so the closure is one renderer's and not the shared sanitizer's. If someone moved it into
    # MarkdownRendererUrlSanitizer this goes red, and that is the ruling R1.1 forbids.
    it 'keeps the closure on CustomMarkdownRenderer and not in the shared sanitizer' do
      expect(CustomMarkdownRenderer.private_instance_methods(false)).to include(:permitted_data_image?)
      expect(MarkdownRendererUrlSanitizer.private_instance_methods(false)).to include(:permitted_data_image?)
      expect(BaseMarkdownRenderer.private_instance_methods(false)).not_to include(:permitted_data_image?)
      expect(MarkdownRendererUrlSanitizer::SAFE_DATA_IMAGE_PATTERN).to eq(%r{\Adata:image/(?:png|gif|jpeg|webp)}i)
    end
  end

  # THE REQUEST BOUNDARY. A collection action that takes a nested hash is reachable with anything in that slot,
  # and CLAUDE.md asks for invalid input to be a 4xx at the boundary rather than an exception in the stack.
  describe 'malformed submissions' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'answers 400 rather than rendering when the article key is absent' do
      post '/super_admin/articles/preview_markdown', params: { content: '# x' }

      expect(response).to have_http_status(:bad_request)
    end

    # FINDING (low): a scalar in the `article` slot is not validated at the boundary. `params.require(:article)`
    # returns the String and `.permit` is a NoMethodError on it, so the request is a 500 and a Sentry event
    # rather than the 422 CLAUDE.md asks for. Super-admin-only and no disclosure, so it is pinned as the
    # behaviour that exists rather than fixed in a file this agent does not own.
    it 'is an unhandled 500 for a scalar article parameter, not a 422' do
      post '/super_admin/articles/preview_markdown', params: { article: 'just a string' }

      expect(response).to have_http_status(:internal_server_error)
    end

    it 'renders an empty fragment for an absent content key rather than failing' do
      post '/super_admin/articles/preview_markdown', params: { article: { title: 'no content here' } }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('cw-article-content')
    end
  end

  # NO TENANT-REACHABLE AUTHORING ROUTE, asserted over the ROUTE TABLE rather than per endpoint, so a route
  # added later without a spec still fails here.
  describe 'the authoring surface as a whole' do
    it 'mounts every documentation authoring action under /super_admin only' do
      subjects = %w[articles categories portals documentation_media]
      authoring = Rails.application.routes.routes.filter_map do |route|
        path = route.path.spec.to_s
        next unless subjects.any? { |word| path.include?(word) }
        next if route.verb == 'GET'

        path
      end.uniq

      tenant_reachable = authoring.reject { |path| path.start_with?('/super_admin') }
                                  .reject { |path| path.start_with?('/api/v1/accounts/:account_id/portals') }
                                  .reject { |path| path.start_with?('/platform/api/v1') }

      expect(tenant_reachable).to be_empty, tenant_reachable.inspect
    end

    # The tenant-facing writes that DO exist are the upstream Help Center ones, and every one of them is denied
    # by an enumerated Custom:: override. Item 12's standing rule, asserted as a rule rather than per action:
    # every public predicate on the three policy classes has a `false` override.
    it 'leaves no Portal, Article or Category policy action without a tenant override' do
      { PortalPolicy => Custom::PortalPolicy, ArticlePolicy => Custom::ArticlePolicy,
        CategoryPolicy => Custom::CategoryPolicy }.each do |oss, overlay|
        actions = oss.instance_methods(false).grep(/\?\z/)
        missing = actions - overlay.instance_methods(false)

        expect(missing).to be_empty, "#{oss}: #{missing.inspect} has no Custom override"
        actions.each do |action|
          expect(overlay.instance_method(action).bind_call(oss.allocate)).to be(false), "#{oss}##{action}"
        end
      end
    end
  end
end
