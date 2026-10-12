require 'rails_helper'

# The documentation is the product's public face: it is what a prospect finds before they find the product.
# These examples assert the head a crawler actually receives (docs/product-refinement/03-documentation-seo.md),
# because every element here is either read by a crawler or ignored by one, and the difference is a tag name.
RSpec.describe 'Documentation SEO', type: :request do
  let(:docs_config) do
    { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' }
  end
  # `custom_domain` is what satisfies `ensure_custom_domain_request` for a test request, whose host is
  # www.example.com (app/controllers/public_controller.rb:9-20) -- the same arrangement the existing public
  # portal specs use. It also makes the canonical host the portal's own, which is the production shape for a
  # documentation site on its own domain.
  let!(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: 'lynomia-docs', custom_domain: 'www.example.com',
                    platform_owned: true, account: nil, config: docs_config)
  end
  let!(:category) { create(:category, portal: portal, locale: 'en', slug: 'commerce', name: 'Commerce') }
  # An article's locale FOLLOWS its category's (Article#ensure_locale_in_article), which is how the Help Center
  # models language -- so a translation lives in that language's category, exactly as the content seeder builds
  # it (custom/app/services/documentation/content_seeder.rb).
  let(:arabic_category) { create(:category, portal: portal, locale: 'ar', slug: 'commerce-ar', name: 'التجارة') }
  let!(:article) do
    create(:article, portal: portal, category: category, locale: 'en', slug: 'connect-woocommerce',
                     title: 'Connect WooCommerce', status: :published, account: nil,
                     description: 'Connect a WooCommerce store to Lynomia Chat with a REST API key, in four steps.',
                     meta: { 'description' => 'Connect a WooCommerce store to Lynomia Chat with a REST API key, in four steps.' })
  end

  let(:body) { response.body }

  # The public article address carries no locale: each locale's article has its own slug
  # (config/routes.rb:520, `public_portal_article`).
  def get_article(record = article)
    get "/hc/#{portal.slug}/articles/#{record.slug}"
  end

  describe 'one article, one language' do
    before { get_article }

    it 'renders' do
      expect(response).to have_http_status(:success)
    end

    it 'names the one address it should be indexed under' do
      expect(body).to include('<link rel="canonical" href="http')
      expect(body).to include("/hc/#{portal.slug}/articles/#{article.slug}\">")
    end

    # og:image was emitted as BOTH `name` and `property`. Only `property` is read, so the `name` one was a tag
    # sitting next to the one that works.
    it 'uses property for Open Graph and name for Twitter, never the other way round' do
      expect(body).to include('<meta property="og:type" content="article">')
      expect(body).to include('<meta property="og:url"')
      expect(body).to include('<meta property="og:site_name"')
      expect(body).to include('<meta property="og:title"')
      expect(body).not_to include('name="og:image"')
    end

    # A crawler that reads twitter:* does not fall back to og:* for every field. Before this the card had an
    # image and no text.
    it 'gives the Twitter card its own title and description' do
      expect(body).to include('<meta name="twitter:title"')
      expect(body).to include('<meta name="twitter:description"')
      expect(body).to include('<meta name="twitter:card" content="summary">')
    end

    it 'states when the article was published and last changed' do
      expect(body).to include('<meta property="article:published_time"')
      expect(body).to include('<meta property="article:modified_time"')
    end

    it 'carries a BreadcrumbList and a TechArticle, both parseable' do
      blocks = body.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).flatten.map { |raw| JSON.parse(raw) }

      expect(blocks.map { |block| block['@type'] }).to contain_exactly('BreadcrumbList', 'TechArticle')
      breadcrumb = blocks.find { |block| block['@type'] == 'BreadcrumbList' }
      expect(breadcrumb['itemListElement'].map { |crumb| crumb['name'] })
        .to eq(['Lynomia Chat Documentation', 'Commerce', 'Connect WooCommerce'])
      expect(breadcrumb['itemListElement'].map { |crumb| crumb['position'] }).to eq([1, 2, 3])
    end

    # The author of a documentation page is Lynomia. Putting the staff member who wrote it into public
    # structured data would publish an employee's identity to the whole internet for no reader's benefit.
    it 'attributes the article to the organisation, never to the agent who wrote it' do
      schema = JSON.parse(body.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).flatten.last)

      expect(schema['author']).to eq({ '@type' => 'Organization', 'name' => 'Lynomia Chat Documentation' })
      expect(schema['inLanguage']).to eq('en')
    end

    # With one language there is nothing to alternate between, and an hreflang set of one is noise.
    it 'emits no hreflang when the article has no translation' do
      expect(body).not_to include('rel="alternate" hreflang=')
    end
  end

  describe 'an article with a published translation' do
    let!(:translation) do
      create(:article, portal: portal, category: arabic_category, slug: 'connect-woocommerce-ar',
                       title: 'ربط ووكومرس', status: :published, account: nil, associated_article_id: article.id,
                       description: 'اربط متجر ووكومرس بلينوميا تشات باستخدام مفتاح الواجهة البرمجية في أربع خطوات.')
    end

    it 'links both languages to each other, and names an x-default' do
      get_article

      expect(body).to include('rel="alternate" hreflang="en"')
      expect(body).to include('rel="alternate" hreflang="ar"')
      expect(body).to include('rel="alternate" hreflang="x-default"')
      expect(body).to include("/articles/#{translation.slug}\">")
    end

    # Reciprocity: a crawler ignores an alternate that does not point back, so a one-way link is worth nothing
    # while looking like it works.
    it 'links back from the translation to the original' do
      get_article(translation)

      expect(body).to include("/articles/#{article.slug}\">")
      expect(body).to include('rel="alternate" hreflang="x-default"')
    end

    # Announcing a draft translation earns a soft-404.
    it 'does not announce a translation that is still a draft' do
      translation.update!(status: :draft)
      get_article

      expect(body).not_to include('hreflang="ar"')
    end
  end

  describe 'a category page' do
    before { get "/hc/#{portal.slug}/en/categories/#{category.slug}" }

    # A list is not an article: it has no publication date of its own, and inventing one from the newest
    # article in it would be a number nobody stated.
    it 'is a website rather than an article, with a canonical of its own' do
      expect(response).to have_http_status(:success)
      expect(body).to include('<meta property="og:type" content="website">')
      expect(body).to include("/categories/#{category.slug}\">")
      expect(body).not_to include('article:published_time')
    end
  end

  describe 'the sitemap' do
    let!(:draft) do
      create(:article, portal: portal, category: category, locale: 'en', slug: 'not-published-yet',
                       title: 'Draft', status: :draft, account: nil)
    end
    let!(:translation) do
      create(:article, portal: portal, category: arabic_category, slug: 'connect-woocommerce-ar',
                       title: 'ربط ووكومرس', status: :published, account: nil, associated_article_id: article.id)
    end

    before { get "/hc/#{portal.slug}/sitemap.xml" }

    it 'lists every published article once, with its own canonical and its locale alternates' do
      expect(response).to have_http_status(:success)
      expect(body.scan('<loc>').length).to eq(2)
      expect(body).to include("/articles/#{article.slug}</loc>")
      expect(body).to include("/articles/#{translation.slug}</loc>")
      expect(body).to include('xmlns:xhtml="http://www.w3.org/1999/xhtml"')
      expect(body).to include('<xhtml:link rel="alternate" hreflang="ar"')
      expect(body).to include('hreflang="x-default"')
    end

    it 'leaves a draft out' do
      expect(body).not_to include(draft.slug)
    end

    it 'states a last-modified date, which is the only one this product records' do
      expect(body).to include("<lastmod>#{article.updated_at.to_date.iso8601}</lastmod>")
    end
  end

  describe 'robots.txt' do
    before { get '/robots.txt' }

    # A widget load creates a contact before it renders, so crawling it manufactures contacts.
    it 'keeps the widget out, and the surfaces behind a session with it' do
      expect(response).to have_http_status(:success)
      expect(body).to include('Disallow: /widget')
      expect(body).to include('Disallow: /app/')
      expect(body).to include('Disallow: /super_admin/')
      expect(body).to include('Disallow: /api/')
    end

    # The same article again with a query string. The page's canonical already points at the clean address.
    it 'keeps the parameterised form of an article out of the crawl budget' do
      expect(body).to include('Disallow: /hc/*?theme=')
    end

    it 'points at the sitemap of every portal it serves' do
      expect(body).to include('Sitemap: http')
      expect(body).to include("/hc/#{portal.slug}/sitemap.xml")
    end
  end
end
