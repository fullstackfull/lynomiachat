require 'rails_helper'

# Lynomia global documentation (docs/global-documentation/14-security-and-tenancy.md): the proof that platform
# documentation belongs to the platform. Every case here is one the brief asks to be demonstrated rather than
# asserted: who may read it, who may not manage it, and that a tenant cannot reach it even by guessing.
RSpec.describe 'Global documentation ownership', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_admin) { create(:user, account: other_account, role: :administrator) }
  let(:super_admin) { create(:super_admin) }

  let!(:docs_portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil,
                    config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' })
  end
  let!(:docs_category) do
    create(:category, name: 'Getting started', slug: 'getting-started', locale: 'en', portal: docs_portal,
                      account_id: nil)
  end
  let!(:published_article) do
    create(:article, title: 'Welcome', slug: 'welcome', content: 'Hello', status: :published, locale: 'en',
                     portal: docs_portal, category: docs_category, account_id: nil, author: super_admin)
  end
  let!(:draft_article) do
    create(:article, title: 'Not ready', slug: 'not-ready', content: 'Soon', status: :draft, locale: 'en',
                     portal: docs_portal, category: docs_category, account_id: nil, author: super_admin)
  end

  # The public portal serves only on a host this installation knows itself by (DomainHelper.chatwoot_domain?). That
  # is a deployment prerequisite rather than a code path, so the reading examples run with it satisfied, the way a
  # deployed install has it.
  def get_public(path, **)
    with_modified_env(FRONTEND_URL: 'http://www.example.com', HELPCENTER_URL: 'http://www.example.com') do
      get(path, **)
    end
  end

  describe 'the record itself' do
    it 'belongs to no account, and neither do its category or its articles' do
      expect(docs_portal.account_id).to be_nil
      expect(docs_category.account_id).to be_nil
      expect(published_article.account_id).to be_nil
    end

    it 'is absent from every account scope, which is what keeps tenants out of it' do
      expect(Account.all).to all(satisfy { |a| a.portals.exclude?(docs_portal) })
      expect(Account.all).to all(satisfy { |a| a.articles.exclude?(published_article) })
    end

    it 'still requires an account on a tenant portal' do
      expect(Portal.new(name: 'Orphan', slug: 'orphan-portal')).not_to be_valid
    end

    it 'refuses an account on a platform portal' do
      expect(Portal.new(name: 'Both', slug: 'both-portal', platform_owned: true, account: account)).not_to be_valid
    end
  end

  describe 'reading, for everyone' do
    it 'serves a published article to an anonymous visitor' do
      get_public "/hc/#{docs_portal.slug}/articles/#{published_article.slug}"
      expect(response).to have_http_status(:success)
    end

    it 'does not serve a draft to an anonymous visitor' do
      get_public "/hc/#{docs_portal.slug}/articles/#{draft_article.slug}"
      expect(response).to have_http_status(:not_found)
    end

    it 'resolves a contextual help link to the article' do
      get "/docs/#{published_article.slug}"
      expect(response).to redirect_to("/hc/#{docs_portal.slug}/articles/#{published_article.slug}")
    end

    it 'fails safely for a help link whose article does not exist' do
      get '/docs/no-such-article'
      expect(response).to have_http_status(:not_found)
    end

    it 'fails safely for a help link whose article is only a draft' do
      get "/docs/#{draft_article.slug}"
      expect(response).to have_http_status(:not_found)
    end

    # The brief asks that a draft be previewable before it is published. The preview is the real public page, read
    # with a super admin session, so the same URL that refuses an anonymous visitor above serves the draft here.
    it 'serves a draft to a super admin, so it can be read before it is published' do
      sign_in(super_admin, scope: :super_admin)
      get_public "/hc/#{docs_portal.slug}/articles/#{draft_article.slug}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(draft_article.title)
    end

    it 'points the super admin preview action at that page' do
      sign_in(super_admin, scope: :super_admin)
      get "/super_admin/articles/#{draft_article.id}/preview"
      expect(response).to redirect_to(
        "/hc/#{docs_portal.slug}/articles/#{draft_article.slug}?show_plain_layout=true"
      )
    end
  end

  describe 'managing, for nobody but a super admin' do
    it 'does not list the documentation portal for an account administrator' do
      get "/api/v1/accounts/#{account.id}/portals", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('slug')).not_to include(docs_portal.slug)
    end

    it 'refuses an account administrator who names the portal directly' do
      get "/api/v1/accounts/#{account.id}/portals/#{docs_portal.slug}", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses an account administrator editing one of its articles' do
      put "/api/v1/accounts/#{account.id}/portals/#{docs_portal.slug}/articles/#{published_article.id}",
          params: { article: { title: 'Rewritten by a tenant' } },
          headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
      expect(published_article.reload.title).to eq('Welcome')
    end

    it 'refuses an account administrator deleting one of its articles' do
      delete "/api/v1/accounts/#{account.id}/portals/#{docs_portal.slug}/articles/#{published_article.id}",
             headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
      expect(Article.exists?(published_article.id)).to be(true)
    end

    it 'refuses an agent' do
      get "/api/v1/accounts/#{account.id}/portals/#{docs_portal.slug}", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses an administrator of a different account, with no ownership confusion' do
      get "/api/v1/accounts/#{other_account.id}/portals/#{docs_portal.slug}", headers: other_admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses an anonymous caller' do
      put "/api/v1/accounts/#{account.id}/portals/#{docs_portal.slug}/articles/#{published_article.id}",
          params: { article: { title: 'Rewritten' } }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'the tenant Help Center, which must stay separate' do
    let!(:tenant_portal) { create(:portal, name: 'Tenant help', slug: 'tenant-help', account_id: account.id) }
    let!(:tenant_article) do
      create(:article, title: 'A tenant page', slug: 'a-tenant-page', content: 'Private', status: :published,
                       portal: tenant_portal, account_id: account.id, author: admin)
    end

    it 'does not let a tenant article into the documentation portal' do
      expect(docs_portal.articles).not_to include(tenant_article)
    end

    it 'does not let a platform article into the tenant account search' do
      expect(account.articles).not_to include(published_article)
    end

    it 'keeps public search inside its own portal' do
      get_public "/hc/#{tenant_portal.slug}/en/search", params: { query: 'Welcome' }
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(published_article.slug)
    end

    it 'and the other way round' do
      get_public "/hc/#{docs_portal.slug}/en/search", params: { query: 'tenant' }
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(tenant_article.slug)
    end
  end

  describe 'the reserved slug namespace' do
    it 'refuses a tenant portal that would squat the documentation address' do
      portal = account.portals.new(name: 'Docs', slug: 'docs')
      expect(portal).not_to be_valid
      expect(portal.errors[:slug]).to be_present
    end

    it 'refuses a tenant portal that would squat the changelog address' do
      expect(account.portals.new(name: 'Changelog', slug: Documentation::Library::CHANGELOG_SLUG)).not_to be_valid
    end

    it 'allows the platform portals to use them' do
      expect(docs_portal).to be_valid
    end
  end
end
