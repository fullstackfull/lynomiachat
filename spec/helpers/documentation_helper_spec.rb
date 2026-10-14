require 'rails_helper'

# R1.4 (docs/documentation-v2/08-orchestrator-rulings.md) named the JSON-LD case explicitly, and agent 081
# verified by reading that it is already safe. This file is what keeps it that way: `documentation_structured_data`
# is the one place this product writes author-controlled text into a `<script>` block, and the protection is two
# layers -- `to_json` escapes the string, and `json_escape` turns `<`, `>` and `&` into unicode escapes so a
# `</script>` in an article title cannot terminate the block early.
#
# Also the first spec for this helper at all, which §N.8 of the P0 report recorded as a gap: the breadcrumb
# builder had been covered only through a rendered page.
RSpec.describe DocumentationHelper do
  let(:portal) do
    create(:portal, slug: 'docs-helper-portal', platform_owned: true, account_id: nil,
                    custom_domain: 'docs-helper.example.com',
                    config: { 'allowed_locales' => ['en'], 'default_locale' => 'en', 'layout' => 'documentation' })
  end
  let(:category) { create(:category, portal: portal, account_id: nil, slug: 'helper-cat', locale: 'en') }
  let(:author) { create(:user, account: create(:account), role: :administrator) }

  describe '#documentation_structured_data' do
    it 'escapes a closing script tag in an article title so the block cannot be terminated early' do
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published,
                                 title: 'Pricing</script><script>alert(1)</script>')

      rendered = helper.documentation_structured_data(helper.documentation_article_schema(portal, article))
      parsed = Nokogiri::HTML5.fragment(rendered)

      # One script element, and the payload survives as DATA inside it rather than as markup.
      expect(parsed.css('*').map(&:name)).to eq(['script'])
      expect(parsed.at_css('script')['type']).to eq('application/ld+json')
      expect(rendered).not_to include('</script><script>')
      expect(JSON.parse(parsed.at_css('script').text)['headline']).to eq(article.title)
    end

    it 'escapes the same payload reaching the breadcrumb through a category name' do
      category.update!(name: 'Plans</script><script>alert(1)</script>')
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published, title: 'A page')

      rendered = helper.documentation_structured_data(helper.documentation_breadcrumb_schema(portal, article))

      expect(Nokogiri::HTML5.fragment(rendered).css('*').map(&:name)).to eq(['script'])
      expect(rendered).not_to include('</script><script>')
    end
  end

  describe '#documentation_article_schema' do
    # R1.4's sibling concern, and the reason the byline rule exists: structured data is the most widely
    # redistributed thing this product emits, so it names the ORGANIZATION and never the author.
    it 'names the portal as author and publisher, never the person who wrote it' do
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published, title: 'A page')

      schema = helper.documentation_article_schema(portal, article)

      expect(schema['author']).to eq({ '@type' => 'Organization', 'name' => portal.display_title('en') })
      expect(schema['publisher']).to eq({ '@type' => 'Organization', 'name' => portal.display_title('en') })
      expect(schema.to_json).not_to include(author.available_name)
    end
  end

  describe '#documentation_breadcrumb_schema' do
    it 'omits the category crumb for a legacy cross-portal row rather than publishing a foreign name' do
      tenant_account = create(:account)
      tenant_portal = create(:portal, account_id: tenant_account.id, slug: 'helper-tenant-portal')
      foreign = create(:category, portal: tenant_portal, account_id: tenant_account.id,
                                  name: 'ForeignCategoryName', slug: 'foreign-cat', locale: 'en')
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published, title: 'A page')
      article.update_column(:category_id, foreign.id) # rubocop:disable Rails/SkipsModelValidations

      names = helper.documentation_breadcrumb_schema(portal, article.reload)['itemListElement'].pluck('name')

      expect(names).to contain_exactly(portal.display_title('en'), article.title)
      expect(names).not_to include(foreign.name)
    end

    it 'includes the category crumb when the category is the rendering portal\'s own' do
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published, title: 'A page')

      names = helper.documentation_breadcrumb_schema(portal, article)['itemListElement'].pluck('name')

      expect(names).to eq([portal.display_title('en'), category.name, article.title])
    end

    # These two used to be ERROR checks in the SEO audit, where neither could fail: `Portal#name` and
    # `Category#name` are presence-validated and `Article#title` is too, so no crumb can be blank, and every
    # `item` is a built string (discovery/098-attack-seo-indexability.md R1 checks 8 and 9). They are
    # properties of this code, so they belong here, where they are assertions rather than theatre.
    it 'gives every crumb a name and an item, which is what makes the block readable at all' do
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published, title: 'A page')

      crumbs = helper.documentation_breadcrumb_schema(portal, article)['itemListElement']

      expect(crumbs.map { |crumb| crumb['name'] }).to all(be_present)
      expect(crumbs.map { |crumb| crumb['item'] }).to all(be_present)
      expect(crumbs.map { |crumb| crumb['position'] }).to eq([1, 2, 3])
    end

    it 'serializes both payloads, and names a url on the article schema' do
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published, title: 'A page')
      payload = [helper.documentation_breadcrumb_schema(portal, article),
                 helper.documentation_article_schema(portal, article)]

      expect { JSON.parse(payload.to_json) }.not_to raise_error
      expect(payload.last['url']).to be_present
    end
  end

  # THE ONE ADDRESS BUILDER every canonical, hreflang, Open Graph URL, JSON-LD url and sitemap <loc> goes
  # through, so a bug here is published five ways at once.
  describe '#portal_absolute_url' do
    it 'builds an absolute URL on the portal custom domain' do
      expect(helper.portal_absolute_url(portal, '/hc/x/articles/y'))
        .to eq('https://docs-helper.example.com/hc/x/articles/y')
    end

    # The arithmetic used to turn a blank host into `https://hc/hc/x/articles/y`: `"https://".chomp('/')` is
    # `"https:/"`, and a path beginning with `/` then re-forms the `//` that makes `hc` the hostname. Every
    # crawler was handed an address on a host that does not exist, and the audit's `start_with?('http')` check
    # passed on it (discovery/098-attack-seo-indexability.md R4).
    it 'returns the path, never an invented hostname, when nothing configures a host' do
      portal.update!(custom_domain: nil)

      with_modified_env(HELPCENTER_URL: nil, FRONTEND_URL: nil) do
        expect(helper.portal_absolute_url(portal, '/hc/x/articles/y')).to eq('/hc/x/articles/y')
        expect(helper.portal_public_host(portal)).to eq('')
      end
    end

    it 'adds the scheme only when the configured host does not carry one' do
      with_modified_env(HELPCENTER_URL: 'http://docs.internal:3000/') do
        portal.update!(custom_domain: nil)

        expect(helper.portal_public_host(portal)).to eq('http://docs.internal:3000')
      end
    end
  end

  # `meta['title']` overrides `<meta name="title">`, `og:title` and `twitter:title` and never `<title>`, so the
  # length a search result truncates is this string -- and the portal suffix is most of the budget.
  describe '#documentation_page_title' do
    it 'is the article title plus the portal title, which is what the templates emit' do
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published, title: 'A page',
                                 meta: { 'title' => 'Short SEO title' })

      expect(helper.documentation_page_title(portal, article)).to eq("A page | #{portal.display_title('en')}")
    end
  end

  # A category's translations share a slug and differ only by locale, because that is how the content seeder
  # upserts them; `associated_category_id` exists on the table and the seeder never writes it.
  describe '#portal_category_locale_alternates' do
    let(:portal) do
      create(:portal, slug: 'docs-helper-portal', platform_owned: true, account_id: nil,
                      custom_domain: 'docs-helper.example.com',
                      config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en',
                                'layout' => 'documentation' })
    end

    it 'pairs the locales of one section and names an x-default' do
      create(:category, portal: portal, account_id: nil, slug: 'commerce', locale: 'ar', name: 'التجارة')
      english = create(:category, portal: portal, account_id: nil, slug: 'commerce', locale: 'en', name: 'Commerce')

      expect(helper.portal_category_locale_alternates(portal, english).map(&:first)).to eq(%w[ar en])
      expect(helper.portal_category_default_alternate_url(portal, english))
        .to eq('https://docs-helper.example.com/hc/docs-helper-portal/en/categories/commerce')
    end

    it 'claims nothing for a section that exists in one locale only' do
      english = create(:category, portal: portal, account_id: nil, slug: 'commerce', locale: 'en', name: 'Commerce')

      expect(helper.portal_category_locale_alternates(portal, english)).to eq([])
      expect(helper.portal_category_default_alternate_url(portal, english)).to be_nil
    end

    # A locale removed from the portal's configuration is no longer served, so announcing it to a crawler earns
    # a soft-404.
    it 'leaves out a row whose locale the portal no longer allows' do
      create(:category, portal: portal, account_id: nil, slug: 'commerce', locale: 'ar', name: 'التجارة')
      english = create(:category, portal: portal, account_id: nil, slug: 'commerce', locale: 'en', name: 'Commerce')
      portal.update!(config: portal.config.merge('allowed_locales' => ['en']))

      expect(helper.portal_category_locale_alternates(portal.reload, english)).to eq([])
    end
  end
end
