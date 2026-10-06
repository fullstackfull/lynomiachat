require 'rails_helper'

# TENANTS CONSUME LYNOMIA DOCUMENTATION. TENANTS DO NOT AUTHOR DOCUMENTATION.
#
# The Help Center engine stays -- the Lynomia documentation and changelog ARE Help Center portals, managed in Super
# Admin and served at /docs and /changelog. What is removed is the tenant's own authoring surface, and it is removed
# at the policy, not by hiding navigation, so the API is closed too.
#
# Every principal a tenant can be is checked: an administrator, an agent, and a custom role holding EVERY
# permission including knowledge_base_manage, which Enterprise::{Portal,Article}Policy would otherwise accept.
RSpec.describe 'Tenant Help Center removal', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:power_user) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, account_id: account.id, slug: 'tenant-portal') }
  let!(:category) { create(:category, portal: portal, account_id: account.id) }
  let!(:article) { create(:article, portal: portal, category: category, account_id: account.id, author_id: admin.id) }

  before do
    role = CustomRole.create!(account: account, name: 'everything', permissions: CustomRole::PERMISSIONS)
    account.account_users.find_by(user: power_user).update!(custom_role: role)
  end

  # 401 is what Chatwoot's Pundit rescue renders for a denied policy, so that is the contract being asserted.
  def expect_refused(verb, path, user, params = nil)
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
    expect(response).to have_http_status(:unauthorized), "#{verb.upcase} #{path} returned #{response.status}"
  end

  %i[admin agent power_user].each do |principal|
    context "when signed in as #{principal}" do
      let(:user) { send(principal) }

      it 'cannot list, read, create, update or delete portals' do
        base = "/api/v1/accounts/#{account.id}/portals"
        expect_refused(:get, base, user)
        expect_refused(:get, "#{base}/#{portal.slug}", user)
        expect_refused(:post, base, user, { portal: { name: 'new', slug: 'new' } })
        expect_refused(:patch, "#{base}/#{portal.slug}", user, { portal: { name: 'renamed' } })
        expect_refused(:delete, "#{base}/#{portal.slug}", user)
      end

      it 'cannot manage a portal logo, instructions, archive or ssl' do
        base = "/api/v1/accounts/#{account.id}/portals/#{portal.slug}"
        expect_refused(:delete, "#{base}/logo", user)
        expect_refused(:post, "#{base}/send_instructions", user)
        expect_refused(:patch, "#{base}/archive", user)
        expect_refused(:get, "#{base}/ssl_status", user)
      end

      it 'cannot list, create, update, delete or reorder articles' do
        base = "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles"
        expect_refused(:get, base, user)
        expect_refused(:get, "#{base}/#{article.id}", user)
        expect_refused(:post, base, user, { article: { title: 'x', content: 'y', author_id: user.id } })
        expect_refused(:patch, "#{base}/#{article.id}", user, { article: { title: 'renamed' } })
        expect_refused(:delete, "#{base}/#{article.id}", user)
        expect_refused(:post, "#{base}/reorder", user, { positions: { article.id => 1 } })
      end

      it 'cannot publish or bulk-change articles' do
        base = "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles/bulk_actions"
        expect_refused(:patch, "#{base}/update_status", user, { ids: [article.id], status: 'published' })
        expect_refused(:patch, "#{base}/update_category", user, { ids: [article.id], category_id: category.id })
        expect_refused(:delete, "#{base}/delete_articles", user, { ids: [article.id] })
        expect_refused(:post, "#{base}/translate", user, { ids: [article.id], locale: 'ar' })
      end

      it 'cannot manage categories, which is where locales are managed' do
        base = "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories"
        expect_refused(:get, base, user)
        expect_refused(:post, base, user, { category: { name: 'x', slug: 'x', locale: 'ar' } })
        expect_refused(:patch, "#{base}/#{category.slug}", user, { category: { name: 'renamed' } })
        expect_refused(:delete, "#{base}/#{category.slug}", user)
        expect_refused(:post, "#{base}/reorder", user, { positions: { category.id => 1 } })
      end
    end
  end

  it 'leaves the tenant content itself untouched: nothing here deletes a row' do
    expect { expect_refused(:delete, "/api/v1/accounts/#{account.id}/portals/#{portal.slug}", admin) }
      .not_to change(Portal, :count)
    expect(portal.reload).to be_present
    expect(article.reload).to be_present
  end

  describe 'what Lynomia keeps' do
    let!(:docs_portal) do
      create(:portal, slug: Documentation::Library::DOCS_SLUG, platform_owned: true, account_id: nil,
                      config: { 'allowed_locales' => ['en'], 'default_locale' => 'en' })
    end

    it 'still resolves the platform documentation portal, which no tenant query can reach' do
      expect(Documentation::Library.docs_portal).to eq(docs_portal)
      expect(account.portals).not_to include(docs_portal)
      expect(Portal.tenant).to include(portal)
      expect(Portal.platform).not_to include(portal)
    end

    it 'still serves /docs' do
      get '/docs'
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/hc/#{Documentation::Library::DOCS_SLUG}")
    end

    it 'still serves the public renderer the documentation redirects into' do
      get "/hc/#{docs_portal.slug}"
      expect(response).not_to have_http_status(:not_found)
    end
  end

  describe 'onboarding' do
    before do
      account.update!(custom_attributes: { 'onboarding_step' => 'account_details' })
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
    end

    it 'does not create a Help Center for the tenant' do
      allow(Onboarding::HelpCenterCreationService).to receive(:new)

      expect do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { website: 'acme.com', onboarding_step: 'account_details' },
              headers: admin.create_new_auth_token, as: :json
      end.not_to(change { account.portals.count })

      expect(Onboarding::HelpCenterCreationService).not_to have_received(:new)
    end
  end
end
