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

  # THE WHOLE REFUSAL RESTS ON PREPEND ORDER, and nothing in the three Custom:: files produces it.
  # `Custom::ArticlePolicy#create?` returns `false` unconditionally and never calls `super`, so it closes a route
  # only while it sits AHEAD of the OSS policy in the ancestor chain. That ordering comes from an initializer
  # reading `ChatwootApp.extensions` (config/initializers/01_inject_enterprise_edition_module.rb:24-28,64-88). If a
  # refactor ever turned the prepend into an include, every refusal above would silently become an
  # administrator-is-allowed grant and the request specs would keep passing for the admin arm. So the ordering is
  # asserted rather than assumed.
  it 'prepends every documentation policy ahead of the class it overrides' do
    { PortalPolicy => Custom::PortalPolicy, CategoryPolicy => Custom::CategoryPolicy, ArticlePolicy => Custom::ArticlePolicy }
      .each do |oss_policy, overlay|
        ancestors = oss_policy.ancestors

        expect(ancestors).to include(overlay)
        expect(ancestors.index(overlay)).to be < ancestors.index(oss_policy)
      end
  end

  # CROSS-TENANT AND CROSS-PORTAL ATTEMPTS, each one of the moves the hardening brief named: attaching an article
  # to Lynomia's public documentation portal, moving an article into another tenant's category, reading another
  # tenant's article directly, and doing any of it through update rather than create.
  #
  # These answer 404 rather than 401, and the difference is the point: `before_action :portal` runs ahead of
  # `before_action :check_authorization` (app/controllers/api/v1/accounts/articles_controller.rb:2-3) and resolves
  # the slug inside `Current.account.portals` (:91), so a portal belonging to somebody else is not found before
  # any policy is consulted. Two independent refusals in series, and the assertions below also check that nothing
  # moved -- a status code alone would not prove the write did not happen.
  describe 'reaching across accounts' do
    let(:other_account) { create(:account) }
    let(:other_admin) { create(:user, account: other_account, role: :administrator) }
    let!(:other_portal) { create(:portal, account_id: other_account.id, slug: 'other-tenant-portal') }
    let!(:other_category) { create(:category, portal: other_portal, account_id: other_account.id) }
    let!(:other_article) do
      create(:article, portal: other_portal, category: other_category, account_id: other_account.id, author_id: other_admin.id)
    end
    let!(:docs_portal) do
      create(:portal, slug: Documentation::Library::DOCS_SLUG, platform_owned: true, account_id: nil,
                      config: { 'allowed_locales' => ['en'], 'default_locale' => 'en' })
    end
    let!(:docs_category) { create(:category, portal: docs_portal, account_id: nil, slug: 'docs-category', locale: 'en') }

    def expect_closed(verb, path, params = nil)
      public_send(verb, path, params: params, headers: admin.create_new_auth_token, as: :json)
      expect(response).to have_http_status(:not_found), "#{verb.upcase} #{path} returned #{response.status}"
    end

    it 'cannot create an article in Lynomia\'s public documentation portal' do
      expect do
        expect_closed(:post, "/api/v1/accounts/#{account.id}/portals/#{docs_portal.slug}/articles",
                      { article: { title: 'injected', content: 'x', author_id: admin.id, category_id: docs_category.id } })
      end.not_to change(docs_portal.articles, :count)
    end

    it 'cannot create an article in another tenant\'s portal' do
      expect do
        expect_closed(:post, "/api/v1/accounts/#{account.id}/portals/#{other_portal.slug}/articles",
                      { article: { title: 'injected', content: 'x', author_id: admin.id, category_id: other_category.id } })
      end.not_to change(other_portal.articles, :count)
    end

    it 'cannot read another tenant\'s article directly' do
      expect_closed(:get, "/api/v1/accounts/#{account.id}/portals/#{other_portal.slug}/articles/#{other_article.id}")
    end

    it 'cannot update another tenant\'s article' do
      expect_closed(:patch, "/api/v1/accounts/#{account.id}/portals/#{other_portal.slug}/articles/#{other_article.id}",
                    { article: { title: 'renamed by a stranger' } })
      expect(other_article.reload.title).not_to eq('renamed by a stranger')
    end

    it 'cannot list the categories of Lynomia\'s documentation portal' do
      expect_closed(:get, "/api/v1/accounts/#{account.id}/portals/#{docs_portal.slug}/categories")
    end

    # The bypass the brief asked about by name: not creating a new article, but MOVING an existing one the tenant
    # does own into a category that belongs to Lynomia or to somebody else. Both the single-article update and the
    # bulk category change are closed, and the article's own `category_id` is unchanged after each.
    it 'cannot move its own article into Lynomia\'s documentation portal by update' do
      patch "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles/#{article.id}",
            params: { article: { category_id: docs_category.id, portal_id: docs_portal.id } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(article.reload.category_id).to eq(category.id)
      expect(article.reload.portal_id).to eq(portal.id)
    end

    it 'cannot move its own article into another tenant\'s category by update' do
      patch "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles/#{article.id}",
            params: { article: { category_id: other_category.id } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(article.reload.category_id).to eq(category.id)
    end

    it 'cannot move its own article into another category in bulk' do
      patch "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles/bulk_actions/update_category",
            params: { ids: [article.id], category_id: docs_category.id },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(article.reload.category_id).to eq(category.id)
    end
  end

  # THE CATEGORY-TO-PORTAL RELATIONSHIP, which was the brief's "enforce ownership at the WRITE boundary and again
  # at the READ/publication boundary" and which nothing enforced: `category_id` and `portal_id` are independent
  # columns with no constraint between them, and the public portal lists a category's articles by `category_id`
  # alone. One row with a tenant's portal_id and a documentation category_id published tenant content on /docs.
  describe 'an article whose category belongs to another portal' do
    # custom_domain + `host!` in each request example: with no .env present `DomainHelper.chatwoot_domain?`
    # matches nothing, so the custom domain is the only way PublicController resolves a public request.
    let!(:docs_portal) do
      create(:portal, slug: Documentation::Library::DOCS_SLUG, platform_owned: true, account_id: nil,
                      custom_domain: 'docs-isolation.example.com',
                      config: { 'allowed_locales' => ['en'], 'default_locale' => 'en', 'layout' => 'documentation' })
    end
    let!(:docs_category) { create(:category, portal: docs_portal, account_id: nil, slug: 'docs-cat', locale: 'en') }

    let!(:genuine) do
      create(:article, portal: docs_portal, category: docs_category, account_id: nil, author_id: admin.id,
                       title: 'A real documentation page', content: 'Docs body', status: :published)
    end
    let!(:legacy) do
      article = create(:article, portal: portal, category: category, account_id: account.id,
                                 author_id: tenant_agent.id, title: 'Leaked tenant page',
                                 content: 'Tenant body', status: :published)
      article.update_column(:category_id, docs_category.id) # rubocop:disable Rails/SkipsModelValidations
      article
    end
    # THE READ BOUNDARY, ACROSS EVERY PUBLIC SURFACE THAT PUBLISHES A CATEGORY'S ARTICLES.
    #
    # The first attempt scoped the `Category#articles` association, which broke the home page (ActiveRecord
    # refuses an instance-dependent association inside `joins`). The second scoped one controller
    # before_action -- which an audit then showed was bypassable two ways: the action is conditional on
    # `@portal_layout == 'documentation'`, and `set_view_variant` gives `:plain` priority, so
    # `?show_plain_layout=true` renders a view that re-queries `category.articles` inline and discards the
    # scoped assignment entirely.
    #
    # So the boundary is `Category#portal_articles` / `Article#portal_category`, plain readers that every
    # public site goes through, and these examples assert the SURFACES rather than the assignment.
    #
    # The row is written with `update_column` on purpose: it is exactly what the validation now refuses, so the
    # only way one exists is to have predated it.
    let(:tenant_agent) { create(:user, account: account, role: :agent, display_name: 'TenantAgentByline') }

    it 'cannot be saved, which is the write boundary' do
      intruder = build(:article, portal: portal, category: docs_category, account_id: account.id, author_id: admin.id)

      expect(intruder).not_to be_valid
      expect(intruder.errors[:category]).to include(I18n.t('errors.articles.category_portal_mismatch'))
    end

    it 'is accepted when the category belongs to the same portal' do
      expect(build(:article, portal: portal, category: category, account_id: account.id, author_id: admin.id)).to be_valid
    end

    it 'is accepted with no category at all, as before' do
      expect(build(:article, portal: portal, category: nil, account_id: account.id, author_id: admin.id)).to be_valid
    end

    def get_public(path)
      host! 'docs-isolation.example.com'
      get path
      expect(response).to have_http_status(:success)
      response.body
    end

    it 'is absent from the public category page' do
      body = get_public("/hc/#{docs_portal.slug}/en/categories/#{docs_category.slug}")

      expect(body).not_to include(legacy.title)
      expect(body).to include(genuine.title)
    end

    # The bypass the audit found: the plain variant takes priority over the documentation variant and its view
    # re-queries the category's articles itself, so a controller-level scope never reaches it.
    it 'is absent from the plain-layout category page, which re-queries in its own view' do
      body = get_public("/hc/#{docs_portal.slug}/en/categories/#{docs_category.slug}?show_plain_layout=true")

      expect(body).not_to include(legacy.title)
    end

    it 'is absent from the public documentation home page' do
      body = get_public("/hc/#{docs_portal.slug}/en")

      expect(body).not_to include(legacy.title)
    end

    it 'is absent from the plain-layout home page' do
      body = get_public("/hc/#{docs_portal.slug}/en?show_plain_layout=true")

      expect(body).not_to include(legacy.title)
    end

    # Counts and teasers are the sites the previous pass left to the validation alone.
    it 'does not count towards the category article count, and is not offered as a teaser' do
      expect(docs_category.portal_articles.published).to contain_exactly(genuine)
      expect(docs_category.portal_articles.published.count).to eq(1)
    end

    # `public_author` keys off the ARTICLE's portal, so it cannot help here: the legacy row belongs to a tenant
    # portal and is not platform-owned, so its author is public by that rule. Scoping the article source is
    # what keeps the tenant agent's name off a Lynomia documentation URL.
    it 'does not contribute its author to the public byline strip' do
      body = get_public("/hc/#{docs_portal.slug}/en/categories/#{docs_category.slug}")

      expect(body).not_to include(tenant_agent.available_name)
    end

    it 'is absent from portal search results' do
      body = get_public("/hc/#{docs_portal.slug}/en/search?q=page")

      expect(body).not_to include(legacy.title)
    end

    it 'is absent from the public articles index' do
      body = get_public("/hc/#{docs_portal.slug}/en/articles")

      expect(body).not_to include(legacy.title)
    end

    # A correctly matched article keeps working on every one of those surfaces -- the point of the guard is to
    # drop foreign rows, not to break the portal.
    it 'still publishes the portal\'s own article normally' do
      expect(get_public("/hc/#{docs_portal.slug}/en")).to include(genuine.title)
      expect(get_public("/hc/#{docs_portal.slug}/en/categories/#{docs_category.slug}")).to include(genuine.title)
      expect(get_public("/hc/#{docs_portal.slug}/articles/#{genuine.slug}")).to include(genuine.title)
    end

    # The regression the first attempt caused: the home page joins the articles association.
    it 'still renders the public documentation home page, which joins the articles association' do
      expect(get_public("/hc/#{docs_portal.slug}/en")).to be_present
    end

    # THE OTHER DIRECTION, which none of the examples above reach: the ARTICLE is the documentation portal's and
    # the CATEGORY is a tenant's. That row is genuinely a documentation article, so every portal-scoped article
    # query returns it and it belongs at its own URL and in the sitemap. What must not happen is its foreign
    # category being PUBLISHED beside it -- above all into structured data, which is what a search engine indexes.
    #
    # Both sites proven here were missed by the first all-surfaces sweep and found by re-running it with no
    # exclusion filter: the earlier grep dropped every line containing `portal_category`, which silently
    # swallowed `portal_category_canonical_url` on the structured-data line. Third over-broad-grep miss of this
    # phase; recorded as such in the report.
    context "when the article is the documentation portal's and the category is a tenant's" do
      # Same slug as `docs_category` on purpose -- allowed, because Category scopes slug uniqueness by portal --
      # so the sidebar's active-state comparison really does match a documentation entry on the foreign slug.
      let!(:foreign_category) do
        create(:category, portal: portal, account_id: account.id, name: 'TenantCategoryName',
                          slug: docs_category.slug, locale: 'en')
      end
      let!(:stray) do
        row = create(:article, portal: docs_portal, category: docs_category, account_id: nil, author_id: admin.id,
                               title: 'A documentation page with a foreign category', content: 'Body',
                               status: :published, locale: 'en')
        row.update_column(:category_id, foreign_category.id) # rubocop:disable Rails/SkipsModelValidations
        row
      end

      it 'is what the production audit scope is for' do
        expect(Article.cross_portal_category).to include(stray)
      end

      it 'publishes no foreign crumb in the BreadcrumbList structured data a search engine reads' do
        body = get_public("/hc/#{docs_portal.slug}/articles/#{stray.slug}")
        breadcrumb = Nokogiri::HTML5(body).css('script[type="application/ld+json"]')
                             .map { |node| JSON.parse(node.text) }
                             .find { |payload| payload['@type'] == 'BreadcrumbList' }

        expect(breadcrumb['itemListElement'].pluck('name'))
          .to contain_exactly(docs_portal.display_title('en'), stray.title)
        expect(body).not_to include(foreign_category.name)
      end

      # No URL assertion here, deliberately: the foreign category shares `docs_category`'s slug, so a crumb URL
      # built from it is byte-identical to the legitimate one. The NAME is what distinguishes them, and the
      # structured-data example above asserts the crumb list has no category entry at all.
      it 'renders the article itself without the foreign category name anywhere on the page' do
        body = get_public("/hc/#{docs_portal.slug}/articles/#{stray.slug}")

        expect(body).to include(stray.title)
        expect(body).not_to include(foreign_category.name)
      end

      # The sidebar publishes nothing from the foreign category, but it did compare against its slug, so a
      # documentation entry sharing that slug was marked active and opened. Correctness, not disclosure.
      it 'marks no sidebar entry active from the foreign category slug' do
        expect(get_public("/hc/#{docs_portal.slug}/articles/#{stray.slug}"))
          .not_to include('<details class="group" open>')
      end
    end
  end

  # THE ONE DOCUMENTATION SURFACE THE POLICY CHOKE POINT DOES NOT REACH.
  #
  # `SearchController` runs no `check_authorization` and consults no policy, so every refusal above is irrelevant
  # to it. Before Custom::SearchService#filter_articles narrowed the relation, `GET /search/articles` returned the
  # full body of the workspace's own drafts and archived pages to any member -- including an agent and a custom
  # role -- because `_article.json.jbuilder` renders `article.content`.
  describe 'global search over articles' do
    let!(:draft) do
      create(:article, portal: portal, category: category, account_id: account.id, author_id: admin.id,
                       title: 'Secret pricing plan', content: 'Unreleased pricing', status: :draft)
    end
    let!(:archived) do
      create(:article, portal: portal, category: category, account_id: account.id, author_id: admin.id,
                       title: 'Secret retired policy', content: 'Withdrawn policy', status: :archived)
    end
    let!(:published) do
      create(:article, portal: portal, category: category, account_id: account.id, author_id: admin.id,
                       title: 'Secret published page', content: 'Published body', status: :published)
    end

    let!(:other_account) { create(:account) }
    let!(:other_portal) { create(:portal, account_id: other_account.id, slug: 'another-tenant') }
    let!(:other_admin) { create(:user, account: other_account, role: :administrator) }
    let!(:other_published) do
      create(:article, portal: other_portal, account_id: other_account.id, author_id: other_admin.id,
                       title: 'Secret neighbour page', content: 'Neighbour body', status: :published)
    end

    def search_titles(user)
      get "/api/v1/accounts/#{account.id}/search/articles",
          params: { q: 'Secret' }, headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      response.parsed_body['payload']['articles'].pluck('title')
    end

    %i[admin agent power_user].each do |principal|
      it "returns no draft or archived article to #{principal}" do
        titles = search_titles(send(principal))

        expect(titles).to contain_exactly(published.title)
        expect(titles).not_to include(draft.title, archived.title)
      end
    end

    it 'leaks no body text for an unpublished article' do
      get "/api/v1/accounts/#{account.id}/search/articles",
          params: { q: 'Secret' }, headers: admin.create_new_auth_token, as: :json

      expect(response.body).not_to include('Unreleased pricing')
      expect(response.body).not_to include('Withdrawn policy')
    end

    it 'returns no article belonging to another account' do
      expect(search_titles(admin)).not_to include(other_published.title)
    end

    # Narrowing after `page`/`per` would be wrong if the count still described the wider set: the page would show
    # one row while the UI claimed three, which is how a narrowing silently turns into a disclosure of how many
    # drafts exist.
    it 'counts only what it returns' do
      get "/api/v1/accounts/#{account.id}/search/articles",
          params: { q: 'Secret' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']['articles'].length).to eq(1)
    end

    it 'is also narrowed on the combined search endpoint' do
      get "/api/v1/accounts/#{account.id}/search",
          params: { q: 'Secret' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['articles'].pluck('title')).to contain_exactly(published.title)
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
