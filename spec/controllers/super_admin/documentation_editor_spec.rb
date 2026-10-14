require 'rails_helper'

# Wave 2, Agent 2. Two things are under test and they are independent:
#
#   1. A Super Admin save must stop destroying `meta['doc_key']`. Measured before the fix
#      (docs/documentation-v2/P2-WORKSTREAM-OWNERSHIP.md E1): the form posts `meta` as a whole value, the field
#      does not permit `doc_key`, and the controller assigned the submission over the jsonb column -- so one
#      save of a typo in the title silently broke every contextual-help link for that article.
#   2. The editor's own endpoint: preview of UNSAVED Markdown, rendered by the renderer that publishes it, and
#      reachable by nobody but a super admin.
RSpec.describe 'Super Admin documentation editor', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:portal) { create(:portal, slug: Documentation::Library::DOCS_SLUG, account: nil, platform_owned: true) }
  let(:category) { create(:category, portal: portal, locale: 'en', slug: 'administration', name: 'Administration') }
  let(:article) do
    create(:article, portal: portal, account: nil, category: category, author: super_admin, locale: 'en',
                     slug: 'audit-logs', title: 'Audit logs', content: 'Body',
                     meta: { 'doc_key' => 'audit-logs', 'title' => 'SEO title', 'tags' => ['administration'] })
  end

  describe 'meta is merged, never replaced' do
    before { sign_in(super_admin, scope: :super_admin) }

    # The regression. It fails without ArticleMetaField.merge_submitted: `doc_key` is on no form input, so the
    # submission below does not carry it and a whole-value assignment drops it.
    it 'keeps doc_key through a save that only edits the title' do
      put "/super_admin/articles/#{article.id}", params: {
        article: { title: 'Audit logs, renamed', meta: { title: 'SEO title', description: '', version: '',
                                                         release_date: '', feature_image: '', tags: 'administration' } }
      }

      article.reload
      expect(article.title).to eq('Audit logs, renamed')
      expect(article.meta['doc_key']).to eq('audit-logs')
    end

    it 'still removes a managed key the operator cleared' do
      put "/super_admin/articles/#{article.id}", params: {
        article: { meta: { title: '', description: '', version: '', release_date: '', feature_image: '', tags: '' } }
      }

      expect(article.reload.meta).to eq('doc_key' => 'audit-logs')
    end

    it 'still turns the tags text input into an array' do
      put "/super_admin/articles/#{article.id}", params: {
        article: { meta: { title: 'SEO title', description: '', version: '', release_date: '', feature_image: '',
                           tags: 'administration, audit' } }
      }

      expect(article.reload.meta['tags']).to eq(%w[administration audit])
    end

    # D4: the slug is the corpus file's name and the article's public address, so it left the form. A posted slug
    # is simply not permitted, which is what keeps a rename from 404ing an indexed URL.
    it 'ignores a slug posted by hand' do
      put "/super_admin/articles/#{article.id}", params: { article: { title: 'Still fine', slug: 'renamed-by-hand' } }

      expect(article.reload.slug).to eq('audit-logs')
    end
  end

  # A SECTION IS NOT EDITABLE AT ALL. `manifest.yml` is the sole author of its `name`, `description`,
  # `position` and `icon` (owner ruling), and `slug` and `locale` are the two halves of the key
  # `Documentation::ContentSeeder#upsert_category` looks a section up by
  # (custom/app/services/documentation/content_seeder.rb:98). So the edit surface is withheld at the ROUTE --
  # `resources :categories, except: [:edit, :update]` -- rather than by emptying a form.
  #
  # These examples replace four that asserted which FIELDS the section form dropped. The property is stronger:
  # there is no form and no PUT, so there is nothing to permit.
  #
  # Each request lives in its own example on purpose. Measured: a 404 earlier in an example drops the Devise
  # session, so a page assertion after one reads 302 and would pass for the wrong reason.
  describe 'a documentation section' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'has no update route, so a crafted PUT reaches no controller' do
      put "/super_admin/categories/#{category.id}", params: { category: { name: 'Renamed' } }

      expect(response).to have_http_status(:not_found)
      expect(category.reload.name).to eq('Administration')
    end

    it 'has no edit route' do
      get "/super_admin/categories/#{category.id}/edit"

      expect(response).to have_http_status(:not_found)
    end

    # The owner's requirement that the UI must not promise editability. Administrate decides from the real route
    # table -- `existing_action?` is `routes.include?([resource, action])`
    # (administrate-0.20.1/app/controllers/administrate/application_controller.rb:117-120) -- so withholding the
    # route is what removes the button. Asserted on the page an operator sees, not on the helper.
    it 'offers no Edit link on the section page, which still renders' do
      get "/super_admin/categories/#{category.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Administration')
      expect(response.body).not_to include("/super_admin/categories/#{category.id}/edit")
    end

    it 'offers no Edit link in the section list either' do
      get '/super_admin/categories'

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("/super_admin/categories/#{category.id}/edit")
    end

    # Still creatable: a hand-made section has no manifest row, so nothing authors it but the operator. That is
    # why FORM_ATTRIBUTES keeps every field for `new`.
    it 'is still creatable, with every field offered on the new form' do
      get '/super_admin/categories/new'

      expect(response).to have_http_status(:success)
      %w[name description locale position icon].each do |field|
        expect(response.body).to include(%(name="category[#{field}]"))
      end
    end
  end

  # THE PREVIEW TITLE. `#preview` redirects to the article's public URL with `show_plain_layout=true`, and
  # `set_view_variant` gives `:plain` priority over `:documentation` (base_controller.rb:27-31), so the preview
  # renders the SHARED `articles/_meta_head` rather than the documentation one. That template took `<title>`
  # from `article.title` while taking every other title tag from the SEO title, so an operator previewing never
  # saw the SEO title they had just set.
  #
  # Presentation and preview correctness, not indexability: this variant publishes no canonical and
  # `robots.txt` disallows `/hc/*?show_plain_layout=`, so no crawler was reading either value.
  describe 'the preview title' do
    # `custom_domain` is what satisfies `ensure_custom_domain_request` for a test request, whose host is
    # www.example.com (app/controllers/public_controller.rb:9-20): without it the public page answers 401 and an
    # example here would be measuring the domain guard rather than the title. Same arrangement the existing
    # public portal specs use.
    before do
      portal.update!(custom_domain: 'www.example.com')
      sign_in(super_admin, scope: :super_admin)
    end

    it 'sends Preview to the plain variant of the real public page' do
      get "/super_admin/articles/#{article.id}/preview"

      expect(response).to redirect_to("/hc/#{portal.slug}/articles/#{article.slug}?show_plain_layout=true")
    end

    it 'shows the SEO title the operator set, on the page Preview lands on' do
      article.update!(meta: article.meta.to_h.merge('title' => 'Audit logs, explained'))

      get "/hc/#{portal.slug}/articles/#{article.slug}?show_plain_layout=true"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<title>Audit logs, explained | ')
      # The discriminator: the article heading is still 'Audit logs', so this fails if <title> ignores the
      # override, which is exactly what it used to do.
      expect(response.body).not_to include('<title>Audit logs | ')
    end

    it 'falls back to the article heading when no SEO title is set' do
      article.update!(meta: article.meta.to_h.except('title'))

      get "/hc/#{portal.slug}/articles/#{article.slug}?show_plain_layout=true"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<title>Audit logs | ')
    end
  end

  describe 'ArticleMetaField.merge_submitted' do
    it 'carries every unmanaged key through untouched' do
      stored = { 'doc_key' => 'audit-logs', 'something_else' => 'kept' }

      merged = ArticleMetaField.merge_submitted(stored, { 'title' => 'New' })

      expect(merged).to eq('doc_key' => 'audit-logs', 'something_else' => 'kept', 'title' => 'New')
    end

    it 'returns only the unmanaged keys when the submission is blank' do
      expect(ArticleMetaField.merge_submitted({ 'doc_key' => 'k', 'title' => 'old' }, nil)).to eq('doc_key' => 'k')
    end

    it 'refuses to write a key the form does not offer, so a crafted post cannot set doc_key' do
      merged = ArticleMetaField.merge_submitted({ 'doc_key' => 'real-key' }, { 'doc_key' => 'forged', 'title' => 'T' })

      expect(merged).to eq('doc_key' => 'real-key', 'title' => 'T')
    end
  end

  # The form override itself: Administrate's partial with one branch, so the editor replaces the `content`
  # textarea and every other field still renders through its own field class.
  describe 'GET edit' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'mounts the editor over the content field and leaves the other fields alone' do
      get "/super_admin/articles/#{article.id}/edit"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-component-name="DocumentationArticleEditor"')
      expect(response.body).to include('article[content]')
      # Administrate's own textarea for `content` is gone, replaced by the editor's.
      expect(response.body).not_to include('<textarea name="article[content]"')
      # Unrelated fields still come from their field classes.
      expect(response.body).to include('article_meta_title')
      expect(response.body).to include('name="article[position]"')
    end

    # `new` has no stored article, so the editor's props come from an unsaved record and the portal is not
    # chosen yet. It renders, because that is where an operator writes a new article.
    it 'mounts on the new-article form too' do
      get '/super_admin/articles/new'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-component-name="DocumentationArticleEditor"')
    end

    # D4: the slug left FORM_ATTRIBUTES, so the form no longer offers it.
    it 'renders no slug input' do
      get "/super_admin/articles/#{article.id}/edit"

      expect(response.body).not_to include('name="article[slug]"')
    end
  end

  # THE PREVIEW PANE RESOLVES `media:`. Before this, `preview_markdown` called `render_article` with no resolver,
  # so an operator uploaded an image, the editor inserted the server's own Markdown, and the preview showed an
  # inert comment -- ruling R3 point 6's defect class inverted, a preview showing LESS than the published page.
  describe 'POST preview_markdown with documentation media' do
    # A 4x3 PNG, decoded rather than fixtured, so the intrinsic dimensions the analyzer reads are known here.
    let(:png) do
      Base64.strict_decode64(
        'iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAYAAAC26JiGAAAAFUlEQVR4nGP8z8DAwMDEgAAwFhMDAwBkFQIBrDJfBwAAAABJRU5ErkJggg=='
      )
    end
    let(:key) { 'uploads/0123456789abcdef-step-two.png' }

    before do
      sign_in(super_admin, scope: :super_admin)
      Documentation::MediaUpload.new(portal: portal).attach!(key: key, io: StringIO.new(png), filename: 'step-two.png')
    end

    it 'renders an img for a saved article, at the application-owned delivery path' do
      post '/super_admin/articles/preview_markdown',
           params: { article: { id: article.id, content: "![Step two](media:#{key})" } }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(src="/hc/#{portal.slug}/articles/#{article.slug}/media/#{key}"))
      expect(response.body).to include('alt="Step two"')
      expect(response.body).not_to include('media: unresolved key')
    end

    # The limitation, asserted so it is a known state rather than a surprise: an unsaved article has no slug, so
    # its media has no address yet and the preview says so inertly rather than emitting a broken src.
    it 'emits an inert comment and no img for an unsaved article' do
      post '/super_admin/articles/preview_markdown',
           params: { article: { content: "![Step two](media:#{key})" } }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('media: unresolved key')
      expect(response.body).not_to include('<img')
      expect(response.body).not_to include('src=""')
    end

    # A posted id cannot point the resolver anywhere the operator is not editing: `scoped_resource` is platform
    # portals only, so an article on a tenant portal resolves to nothing rather than to that portal's media.
    it 'ignores an id outside the platform portals' do
      tenant_portal = create(:portal, account: create(:account), slug: 'tenant-portal')
      tenant_article = create(:article, portal: tenant_portal, account_id: tenant_portal.account_id,
                                        author: create(:user, account: tenant_portal.account), locale: 'en',
                                        slug: 'tenant-page', title: 'Tenant page', content: 'x')

      post '/super_admin/articles/preview_markdown',
           params: { article: { id: tenant_article.id, content: "![Step two](media:#{key})" } }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('media: unresolved key')
      expect(response.body).not_to include('tenant-portal')
    end
  end

  describe 'POST preview_markdown' do
    let(:markdown) { "## Heading\n\n| a | b |\n|---|---|\n| 1 | 2 |" }

    it 'renders the unsaved source through the renderer that publishes it' do
      sign_in(super_admin, scope: :super_admin)

      post '/super_admin/articles/preview_markdown', params: { article: { content: markdown } }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<h2>Heading</h2>')
      # The same wrapper the public article page renders, so the preview cannot drift from the published page.
      expect(response.body).to include('id="cw-article-content"')
      expect(response.body).to include('class="tableWrapper"')
    end

    # Tenants are documentation readers only. The editor adds no tenant-reachable authoring surface, and that is
    # enforced by the Super Admin session boundary rather than by hiding a button.
    it 'is unreachable by a tenant administrator' do
      sign_in(create(:user, account: create(:account), role: :administrator), scope: :user)

      post '/super_admin/articles/preview_markdown', params: { article: { content: markdown } }

      # 302 to the Super Admin sign-in, measured: Devise's failure app redirects an HTML request rather than
      # answering 401, and the body carries no rendered Markdown either way.
      expect(response).to have_http_status(:redirect)
      expect(response.body).not_to include('cw-article-content')
    end

    it 'is unreachable unauthenticated' do
      post '/super_admin/articles/preview_markdown', params: { article: { content: markdown } }

      # 302 to the Super Admin sign-in, measured: Devise's failure app redirects an HTML request rather than
      # answering 401, and the body carries no rendered Markdown either way.
      expect(response).to have_http_status(:redirect)
      expect(response.body).not_to include('cw-article-content')
    end
  end
end
