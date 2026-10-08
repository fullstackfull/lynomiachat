require 'rails_helper'

# TENANTS CONSUME LYNOMIA DOCUMENTATION. TENANTS DO NOT AUTHOR DOCUMENTATION.
#
# The Help Center engine stays -- the Lynomia documentation and changelog ARE Help Center portals, managed in Super
# Admin and served at /docs and /changelog. What is removed is the tenant's own authoring surface, and it is removed
# at the policy, not by hiding navigation, so the API is closed too.
#
# Every principal a tenant can be is checked: an administrator, an agent, and a custom role holding EVERY
# permission including knowledge_base_manage, which Chatwoot's policies grant on. The custom role is Lynomia's
# own (custom/app/models/custom_role.rb), so this arm keeps working with or without the Enterprise overlay.
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

  # ssl_status used to be checked alongside the other portal member actions. Its only implementation was
  # Enterprise::Api::V1::Accounts::PortalsController#ssl_status (Cloudflare custom domains, which Lynomia does not
  # ship), so the route declaration was removed when the route tree was prepared for Enterprise removal. The
  # surface is closed harder than before -- there is nothing to authorize -- and Custom::PortalPolicy#ssl_status?
  # still refuses, so a restored route would still be denied. Both halves are asserted below.
  it 'offers tenants no portal ssl_status endpoint, and would refuse one' do
    expect(Rails.application.routes.routes.map { |route| route.defaults[:action] }).not_to include('ssl_status')
    expect(Custom::PortalPolicy.instance_method(:ssl_status?).bind_call(PortalPolicy.allocate)).to be(false)
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

      it 'cannot manage a portal logo, instructions or archive' do
        base = "/api/v1/accounts/#{account.id}/portals/#{portal.slug}"
        expect_refused(:delete, "#{base}/logo", user)
        expect_refused(:post, "#{base}/send_instructions", user)
        expect_refused(:patch, "#{base}/archive", user)
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

  # An inbox could be pointed at a Help Center, and upstream never scoped that id to the account:
  # `Inbox belongs_to :portal, optional: true` accepted any portal at all. Tenants have no portal to link now, so
  # the parameter is refused at the boundary rather than silently dropped -- which closes the cross-account
  # reference as well.
  describe 'linking an inbox to a Help Center' do
    let!(:inbox) { create(:inbox, account: account) }
    let!(:other_account_portal) { create(:portal, account_id: create(:account).id, slug: 'someone-else') }

    it 'is refused, with the reason' do
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { portal_id: portal.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('errors.inboxes.help_center_not_available'))
      expect(inbox.reload.portal_id).to be_nil
    end

    it 'is refused for a portal belonging to another account' do
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { portal_id: other_account_portal.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(inbox.reload.portal_id).to be_nil
    end

    it 'is refused for the platform documentation portal' do
      docs = create(:portal, slug: Documentation::Library::DOCS_SLUG, platform_owned: true, account_id: nil)

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { portal_id: docs.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(inbox.reload.portal_id).to be_nil
    end

    # Refusing the parameter must not refuse the rest of the screen's saves.
    it 'leaves every other inbox setting saveable' do
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { name: 'Renamed inbox', greeting_enabled: true },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(inbox.reload.name).to eq('Renamed inbox')
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

    # The public renderer /docs redirects into is still routed to the Help Center's own controller -- that is what
    # this change could have broken, and it is what the route table can prove. How the renderer then responds depends
    # on the request's host (PublicController refuses a host that is not the portal's configured domain), so the
    # rendered page is left to the public portal specs that already cover it. The whole chain was verified against a
    # running production-mode instance: /docs -> /hc/lynomia-docs -> /hc/lynomia-docs/en -> 200.
    it 'still routes the public renderer the documentation redirects into' do
      expect(Rails.application.routes.recognize_path("/hc/#{docs_portal.slug}"))
        .to include(controller: 'public/api/v1/portals', action: 'show')
    end
  end

  describe 'onboarding' do
    before do
      account.update!(custom_attributes: { 'onboarding_step' => 'account_details' })
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
    end

    # Chatwoot's tenant-portal creation lived in the Enterprise onboarding controller, which called
    # Onboarding::HelpCenterCreationService. Both are gone with the overlay, so the invariant now holds because the
    # path does not exist rather than because a Custom:: override neutralises it. The structural half asserts
    # exactly that, so a future upstream merge that reintroduces the call fails here.
    it 'does not create a Help Center for the tenant' do
      expect do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { website: 'acme.com', onboarding_step: 'account_details' },
              headers: admin.create_new_auth_token, as: :json
      end.not_to(change { account.portals.count })

      expect(Api::V1::Accounts::OnboardingsController.private_instance_methods(false)).not_to include(:create_help_center)
      expect('Onboarding::HelpCenterCreationService'.safe_constantize).to be_nil
    end
  end
end
