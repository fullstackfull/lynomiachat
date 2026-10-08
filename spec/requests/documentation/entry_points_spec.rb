require 'rails_helper'

# /docs and /changelog are the stable addresses the product links to. They redirect into the Help Center's own
# public renderer rather than duplicating it, so the address survives a slug change and the documentation gets the
# existing layouts, locale handling, search and SEO. Nothing asserted that they redirect at all until now.
RSpec.describe 'Lynomia documentation entry points', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:docs_config) do
    { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' }
  end

  describe 'when the platform portals are set up' do
    let!(:docs_portal) do
      create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                      platform_owned: true, account: nil, config: docs_config)
    end
    let!(:changelog_portal) do
      create(:portal, name: 'Lynomia Chat Changelog', slug: Documentation::Library::CHANGELOG_SLUG,
                      platform_owned: true, account: nil, config: docs_config)
    end

    it 'sends /docs into the documentation portal' do
      get '/docs'

      expect(response).to redirect_to("/hc/#{docs_portal.slug}")
    end

    it 'sends /changelog into the changelog portal' do
      get '/changelog'

      expect(response).to redirect_to("/hc/#{changelog_portal.slug}")
    end

    # The locale is left to the portal's own redirect, which is already the one place that decides it, so neither
    # address carries one.
    it 'carries no locale of its own' do
      get '/docs'

      expect(response.location).not_to include('/en')
      expect(response.location).not_to include('/ar')
    end

    it 'refuses to redirect anywhere but this host' do
      get '/docs'

      expect(response.location).to start_with('/hc/').or start_with("http://#{host}/hc/")
    end

    describe 'a contextual help link' do
      let!(:category) do
        create(:category, name: 'Getting started', slug: 'getting-started', locale: 'en', portal: docs_portal,
                          account_id: nil)
      end

      it 'resolves a published article by its key' do
        article = create(:article, title: 'Labels', slug: 'labels', content: 'x', status: :published, locale: 'en',
                                   portal: docs_portal, category: category, account_id: nil, author: super_admin,
                                   meta: { 'doc_key' => 'labels' })

        get '/docs/labels'

        expect(response).to redirect_to("/hc/#{docs_portal.slug}/articles/#{article.slug}")
      end

      it 'is a 404 for a key no article carries, rather than the documentation home page' do
        get '/docs/no-such-key'

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # On a deployed install a missing platform portal is a setup bug. The addresses say so plainly instead of
  # redirecting into nothing, and the message is a translated string rather than a stack trace.
  describe 'when they are not set up' do
    it 'says /docs is not set up' do
      get '/docs'

      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq(I18n.t('documentation.not_set_up'))
    end

    it 'says /changelog is not set up' do
      get '/changelog'

      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq(I18n.t('documentation.not_set_up'))
    end

    it 'says so for a help link too' do
      get '/docs/labels'

      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq(I18n.t('documentation.not_set_up'))
    end

    # The seeder and anything else that must have a portal gets an exception rather than a nil, because routing
    # around a missing portal would hide the setup bug.
    it 'raises rather than returning nil where a portal is required' do
      expect { Documentation::Library.docs_portal! }.to raise_error(ActiveRecord::RecordNotFound, /#{Documentation::Library::DOCS_SLUG}/o)
      expect { Documentation::Library.changelog_portal! }.to raise_error(ActiveRecord::RecordNotFound,
                                                                         /#{Documentation::Library::CHANGELOG_SLUG}/o)
    end
  end
end
