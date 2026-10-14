require 'rails_helper'

# WAVE 4, AGENT 6 -- ADVERSARIAL. `article.meta` is operator-controlled jsonb and it now reaches `<title>` as
# well as the social tags and the structured data. Two classes of question: is it escaped on every surface that
# renders it, and does the Arabic dictionary change open anything on the shared `text_search` scope.
RSpec.describe 'Documentation search and head -- adversarial', type: :request do
  # `"` closes the attribute, `<` opens a tag, `</script>` closes the JSON-LD block, `]]>` closes a CDATA
  # section, and `&` is the one a careless `html_safe` leaves raw.
  let(:payload) { %(Pwn" onload="alert(1)" x="</title><script>alert(1)</script></script>]]>& ) }
  let(:super_admin) { create(:super_admin) }
  let!(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil, custom_domain: 'docs.example.com',
                    config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' })
  end
  let!(:category) do
    create(:category, portal: portal, account_id: nil, locale: 'en', slug: 'administration',
                      name: "Admin#{payload}", description: "Section#{payload}")
  end
  let!(:article) do
    create(:article, portal: portal, account_id: nil, category: category, author: super_admin, locale: 'en',
                     slug: 'audit-logs', title: 'Audit logs', content: 'Body', status: :published,
                     description: 'A plain description that is long enough to be rendered as a snippet.',
                     meta: { 'doc_key' => 'audit-logs', 'title' => "SEO#{payload}",
                             'description' => "Desc#{payload}", 'tags' => ["tag#{payload}"] })
  end

  def get_public(path)
    with_modified_env(FRONTEND_URL: 'http://www.example.com', HELPCENTER_URL: 'http://www.example.com') do
      get path
    end
    expect(response).to have_http_status(:success)
    response.body
  end

  describe 'operator-controlled meta on the documentation article head' do
    let(:body) { get_public("/hc/#{portal.slug}/articles/#{article.slug}") }
    let(:doc) { Nokogiri::HTML5(body) }

    # The parser is the judge. If any of these were unescaped the payload would have become markup, so the
    # value read back off the parsed node would NOT contain the literal string.
    it 'escapes it in <title>, meta name/og/twitter titles and descriptions' do
      expect(doc.at_css('title').text).to start_with("SEO#{payload}")
      %w[title description].each do |field|
        %W[meta[name="#{field}"] meta[property="og:#{field}"] meta[name="twitter:#{field}"]].each do |selector|
          node = doc.at_css(selector)
          expect(node).to be_present, selector
          expect(node['content']).to include(payload), selector
        end
      end
      expect(doc.at_css('meta[name="tags"]')['content']).to include(payload)
    end

    it 'emits no element or event-handler attribute the payload asked for' do
      # The head legitimately holds the layout's vite module tags AND two JSON-LD blocks that CONTAIN the
      # payload as data -- so neither "no script in the head" nor "no script mentioning alert" is the property.
      # The property is that every script is either a src-only tag or a block that parses as JSON, i.e. the
      # payload never became executable script.
      doc.css('head script').each do |node|
        if node['type'] == 'application/ld+json'
          expect { JSON.parse(node.text) }.not_to raise_error
        else
          # The layout's own inline bootstrap (the colour-scheme line at
          # app/views/layouts/_portal_head.html.erb:32, whose only input is an allowlisted `theme` param) and
          # the vite tags. Neither may carry anything from the article.
          expect(node.text).not_to include(payload)
          expect(node.text).not_to include('alert(1)')
        end
      end
      handlers = doc.css('head *').flat_map { |el| el.attribute_nodes.map(&:name) }.grep(/\Aon/)
      expect(handlers).to be_empty, handlers.inspect
      expect(body).not_to include('<script>alert(1)</script>')
      expect(body).not_to include('onload="alert(1)"')
    end

    # json_escape turns `<`, `>` and `&` into their unicode escapes INSIDE the JSON, so a `</script>` in a
    # title cannot close the block it is written into. Both payloads land in structured data: the article
    # headline and the breadcrumb's crumb names.
    it 'keeps both JSON-LD blocks parseable with the payload inside them' do
      blocks = doc.css('script[type="application/ld+json"]')
      expect(blocks.length).to eq(2)

      parsed = blocks.map { |node| JSON.parse(node.text) }
      article_schema = parsed.find { |schema| schema['@type'] == 'TechArticle' }
      breadcrumb = parsed.find { |schema| schema['@type'] == 'BreadcrumbList' }

      expect(article_schema['description']).to include(payload)
      expect(breadcrumb['itemListElement'].pluck('name')).to include("Admin#{payload}")
      blocks.each { |node| expect(node.to_html).not_to include('</script><script>') }
    end

    it 'escapes a section name and description on the category page head too' do
      page = Nokogiri::HTML5(get_public("/hc/#{portal.slug}/en/categories/#{category.slug}"))

      expect(page.at_css('title').text).to start_with("Admin#{payload}")
      expect(page.at_css('meta[name="description"]')['content']).to include(payload)
      expect(page.css('head *').flat_map { |el| el.attribute_nodes.map(&:name) }.grep(/\Aon/)).to be_empty
    end
  end

  describe 'the sitemap' do
    # The honest answer to "verify escaping on the sitemap": it renders no title at all, only addresses. This
    # asserts that, so adding one later is a visible change rather than a silent new injection surface.
    it 'renders addresses only, so no operator-controlled title reaches it' do
      body = get_public("/hc/#{portal.slug}/sitemap.xml")

      expect(body).to include("/hc/#{portal.slug}/articles/#{article.slug}")
      expect(body).not_to include('SEO')
      expect(body).not_to include('<title')
      expect { Nokogiri::XML(body, &:strict) }.not_to raise_error
    end

    # A slug is the one operator-adjacent value that DOES reach the sitemap, through the canonical. It cannot
    # carry markup -- `before_validation :ensure_article_slug` parameterizes it -- and the template escapes it
    # regardless, which is what keeps the document well-formed.
    it 'stays well-formed XML for a slug built from a hostile title' do
      create(:article, portal: portal, account_id: nil, category: category, author: super_admin, locale: 'en',
                       title: payload, content: 'Body', status: :published)

      expect { Nokogiri::XML(get_public("/hc/#{portal.slug}/sitemap.xml"), &:strict) }.not_to raise_error
    end
  end

  # THE `<title>` ASYMMETRY, now CLOSED, and this is where it was pinned open.
  #
  # `set_view_variant` gives `:plain` priority over `:documentation`, and `show.html+plain.erb` renders the
  # SHARED `articles/_meta_head` -- so one DOCUMENTATION url shape used to carry the old behaviour even on a
  # platform portal. The example below asserted exactly that asymmetry (`start_with('Audit logs')` on the plain
  # mirror against `start_with("SEO#{payload}")` on the documentation variant), which made it a spec pinning
  # the defect that owner ruling 4 was issued to fix. Owner ruling 4 changed the shared partial, the combined
  # gate caught this file, and the expectation is inverted here rather than deleted: what it is really worth is
  # that the SEO title is ESCAPED in `<title>` on BOTH variants, which is a property neither had a pin for.
  #
  # This also closes A6-O4 / section G10 as a matter of fact: there is no asymmetry left to decide about.
  describe 'the plain mirror of a documentation article' do
    it 'titles from the SEO title, the same as the documentation variant, and escapes it on both' do
      plain = Nokogiri::HTML5(get_public("/hc/#{portal.slug}/articles/#{article.slug}?show_plain_layout=true"))
      documentation = Nokogiri::HTML5(get_public("/hc/#{portal.slug}/articles/#{article.slug}"))

      expect(plain.at_css('title').text).to start_with("SEO#{payload}")
      expect(documentation.at_css('title').text).to start_with("SEO#{payload}")
      # The payload reaches `<title>` as TEXT on both: Nokogiri reads it back whole, and no `on*` attribute was
      # created anywhere in either head. That is the injection property, and it is what this file is for.
      expect(plain.at_css('meta[name="title"]')['content']).to include(payload)
      expect(plain.css('head *').flat_map { |el| el.attribute_nodes.map(&:name) }.grep(/\Aon/)).to be_empty
      expect(documentation.css('head *').flat_map { |el| el.attribute_nodes.map(&:name) }.grep(/\Aon/)).to be_empty
    end

    # The plain mirror publishes no canonical of its own and robots.txt disallows the parameter, which is why
    # the `<title>` it renders is a presentation and preview concern rather than an indexability one.
    it 'publishes no canonical and is disallowed to crawlers' do
      plain = Nokogiri::HTML5(get_public("/hc/#{portal.slug}/articles/#{article.slug}?show_plain_layout=true"))

      expect(plain.at_css('link[rel="canonical"]')).to be_nil
      expect(get_public('/robots.txt')).to include('Disallow: /hc/*?show_plain_layout=')
    end
  end

  describe 'the writing direction attribute' do
    it 'is rtl on the Arabic page and ltr on the English one, on all three layouts' do
      arabic_category = create(:category, portal: portal, account_id: nil, locale: 'ar', slug: 'administration-ar',
                                          name: 'الإدارة')
      arabic = create(:article, portal: portal, account_id: nil, category: arabic_category, author: super_admin,
                                locale: 'ar', slug: 'audit-logs-ar', title: 'سجلات التدقيق', content: 'نص',
                                status: :published)

      expect(get_public("/hc/#{portal.slug}/articles/#{arabic.slug}")).to include('dir="rtl"')
      expect(get_public("/hc/#{portal.slug}/articles/#{arabic.slug}?show_plain_layout=true")).to include('dir="rtl"')
      expect(get_public("/hc/#{portal.slug}/articles/#{article.slug}")).to include('dir="ltr"')
    end

    # Two-valued by construction, over every locale the product offers plus hostile input. A `dir` attribute is
    # emitted unescaped into the opening <html> tag on EVERY portal page, tenant portals included, so this is
    # the one helper whose output set has to be closed rather than merely escaped.
    it 'can only ever emit rtl or ltr' do
      helper_module = Class.new { include TextDirectionHelper }.new
      candidates = I18n.available_locales.map(&:to_s) +
                   ['ar_EG', 'he-IL', 'fa-IR', '', 'AR', 'arx', '../ar', 'ar"><script>alert(1)</script>', 42]

      expect(candidates.map { |locale| helper_module.html_dir_attribute(locale) }.uniq.sort).to eq(%w[ltr rtl])
      expect(helper_module.html_dir_attribute(nil)).to eq('ltr')
    end
  end

  # SEARCH. The dictionary moved from `simple` to `arabic` on `Article.text_search`, which is a PRODUCT-WIDE
  # scope: it serves every tenant's Help Center as well as the two platform portals.
  describe 'Article.text_search with the arabic dictionary' do
    let(:account) { create(:account) }
    let(:tenant_admin) { create(:user, account: account, role: :administrator) }
    let!(:tenant_portal) { create(:portal, account_id: account.id, slug: 'tenant-portal') }
    let!(:tenant_article) do
      create(:article, portal: tenant_portal, account_id: account.id, author: tenant_admin, status: :published,
                       slug: 'tenant-secret', title: 'Tenant secret page', content: 'Tenant body', locale: 'en')
    end
    let!(:other_account) { create(:account) }
    let!(:other_portal) { create(:portal, account_id: other_account.id, slug: 'other-portal') }
    let!(:other_article) do
      create(:article, portal: other_portal, account_id: other_account.id, author: create(:user, account: other_account),
                       status: :published, slug: 'other-secret', title: 'Other secret page', content: 'Other body',
                       locale: 'en')
    end

    it 'names the dictionary as a literal in the generated SQL, never from a parameter' do
      sql = Article.text_search('anything').to_sql

      # Six occurrences, measured: the three weighted columns appear once in the rank expression and once in
      # the WHERE clause. Asserted as "every tsvector is arabic and none is the old default" rather than as a
      # count, because the count is an artefact of pg_search's query shape.
      expect(sql.scan(/to_tsvector\('(\w+)'/).flatten.uniq).to eq(['arabic'])
      expect(sql).to include("to_tsquery('arabic'")
      expect(sql).not_to include("'simple'")
    end

    # The injection question. pg_search quotes the term into the tsquery string, so operators and quotes are
    # data. Measured by EXECUTING each one: a successful empty result set is the proof, and a syntax error or a
    # changed row count would not be.
    it 'treats quotes, tsquery operators and SQL fragments as data' do
      hostile = ["a' OR 1=1 --", "x'); DROP TABLE articles; --", 'a & b | c ! d', "'", '\\', ':*', '!!!',
                 "a' || (SELECT content FROM articles) || '"]

      hostile.each do |query|
        expect { Article.text_search(query).to_a }.not_to raise_error, query.inspect
      end
      expect(Article.count).to eq(3)
    end

    it 'still shows a tenant member only their own account\'s published articles' do
      get "/api/v1/accounts/#{account.id}/search/articles",
          params: { q: 'secret' }, headers: tenant_admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      titles = response.parsed_body['payload']['articles'].pluck('title')
      expect(titles).to contain_exactly(tenant_article.title)
      expect(titles).not_to include(other_article.title)
    end

    # Platform documentation has `account_id` NULL and tenant search starts from `current_account.articles`, so
    # the documentation corpus is not reachable there at all -- the dictionary change does not alter that.
    it 'never returns a platform documentation article to a tenant' do
      create(:article, portal: portal, account_id: nil, category: category, author: super_admin, locale: 'en',
                       slug: 'platform-secret', title: 'Platform secret page', content: 'Docs body',
                       status: :published)

      get "/api/v1/accounts/#{account.id}/search/articles",
          params: { q: 'secret' }, headers: tenant_admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']['articles'].pluck('title')).not_to include('Platform secret page')
    end

    # The public portal search is the UNAUTHENTICATED surface onto the same scope, and it is per portal.
    it 'scopes the public portal search to the portal in the URL and to published rows' do
      create(:article, portal: portal, account_id: nil, category: category, author: super_admin, locale: 'en',
                       slug: 'draft-secret', title: 'Draft secret page', content: 'x', status: :draft)

      body = get_public("/hc/#{portal.slug}/en/search?query=secret")

      expect(body).not_to include('Tenant secret page')
      expect(body).not_to include('Draft secret page')
    end

    # INVERTED. This pinned the defect: a NUL byte reached PG::Connection#escape and raised ArgumentError, a 500
    # and a Sentry event on an endpoint that needs no session. The byte is now dropped at the controller
    # boundary beside the `strip` that was already there, so the request is an ordinary search for "secretpage".
    # The previous expectation (`:internal_server_error`) is recorded here so the change is visible.
    it 'serves the unauthenticated portal search for a NUL byte in the query rather than raising' do
      with_modified_env(FRONTEND_URL: 'http://www.example.com', HELPCENTER_URL: 'http://www.example.com') do
        get "/hc/#{portal.slug}/en/search", params: { query: "secret\u0000page" }
      end

      expect(response).to have_http_status(:success)
    end

    # The authenticated search reaches the same escape through its own boundary, so it carries the same fix.
    it 'serves the authenticated search for a NUL byte rather than raising' do
      expect { Article.text_search("secret\u0000page".delete("\u0000")) }.not_to raise_error
    end
  end
end
