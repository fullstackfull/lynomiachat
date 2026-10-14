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

  # The same guarantee for a SECTION, which had the same hole. `upsert_category` looks a section up by
  # `find_or_initialize_by(slug:, locale:)` (custom/app/services/documentation/content_seeder.rb:98), so a
  # renamed slug makes the next seed create a second category at the manifest slug and leave every article on
  # the renamed one.
  describe "a documentation section's slug" do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'ignores a slug posted by hand' do
      put "/super_admin/categories/#{category.id}", params: { category: { name: 'Renamed', slug: 'renamed-by-hand' } }

      expect(category.reload.slug).to eq('administration')
      expect(category.name).to eq('Renamed')
    end

    it 'renders no slug input' do
      get "/super_admin/categories/#{category.id}/edit"

      expect(response.body).to include('name="category[name]"')
      expect(response.body).not_to include('name="category[slug]"')
    end
  end

  # `locale` is the other half of `find_or_initialize_by(slug:, locale:)`. A section that exists in only one
  # locale is the shape that exposes it: every shipped section exists in both, so the uniqueness validation
  # refuses the flip with a 422 and hides the hole.
  describe "a documentation section's locale" do
    # BOTH locales allowed on the portal, deliberately. `Category` also runs `validate :allowed_locales`
    # (app/models/category.rb:88,123-131), so on a single-locale portal a posted `ar` is refused by THAT
    # validation and an example here would pass without the permitted list doing any work -- which is exactly
    # how a guard gets credited for protection it is not providing.
    let!(:lonely) do
      portal.update!(config: portal.config.to_h.merge('allowed_locales' => %w[en ar], 'default_locale' => 'en'))
      create(:category, portal: portal, locale: 'en', slug: 'single-locale', name: 'Single locale')
    end

    before { sign_in(super_admin, scope: :super_admin) }

    # The save, not the form: Administrate reads the per-action constant for strong params too, so hiding the
    # input without permitting-list parity would leave the write open.
    it 'ignores a locale posted by hand' do
      put "/super_admin/categories/#{lonely.id}", params: { category: { name: 'Renamed', locale: 'ar' } }

      expect(lonely.reload.locale).to eq('en')
      expect(lonely.name).to eq('Renamed')
    end

    it 'renders no locale input on the edit form' do
      get "/super_admin/categories/#{lonely.id}/edit"

      expect(response.body).to include('name="category[name]"')
      expect(response.body).not_to include('name="category[locale]"')
    end

    # Creation still chooses a language, because a hand-made section has to.
    it 'still offers locale on the new form' do
      get '/super_admin/categories/new'

      expect(response.body).to include('name="category[locale]"')
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
