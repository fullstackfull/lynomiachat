require 'rails_helper'

# W5: the discovery layer, judged on the RENDERED output rather than on the presence of a helper.
describe 'Marketing SEO' do
  before { Marketing::ContentSeeder.apply! }

  describe '/sitemap.xml' do
    it 'is served as XML and lists both locales of a page as separate entries' do
      get '/sitemap.xml'

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('application/xml')
      expect(response.body).to include('<loc>')
      expect(response.body).to include('/features</loc>')
      expect(response.body).to include('/en/features</loc>')
    end

    it 'pairs the two locales with hreflang alternates and an Arabic x-default' do
      get '/sitemap.xml'

      expect(response.body).to include('hreflang="ar"')
      expect(response.body).to include('hreflang="en"')
      expect(response.body).to include('hreflang="x-default"')
    end

    it 'lists every published page in both locales and nothing else' do
      get '/sitemap.xml'

      expect(response.body.scan('<url>').size).to eq(SitePage.live.count)
    end

    # A draft answers 404, so announcing it earns a soft-404.
    it 'leaves a draft out' do
      page = SitePage.find_by!(locale: 'en', kind: 'feature', key: 'unified_inbox')
      page.update!(status: :draft)

      get '/sitemap.xml'

      # Locale-specific: the Arabic sibling is still published and still listed at its own address.
      expect(response.body).not_to include("/en/features/#{page.slug}</loc>")
      expect(response.body).to include("/features/#{page.slug}</loc>")
    end

    # Listing a page that asks not to be indexed would be the site contradicting itself in two files.
    it 'leaves a page an operator marked noindex out' do
      page = SitePage.find_by!(locale: 'en', kind: 'feature', key: 'unified_inbox')
      page.update!(meta: { 'noindex' => '1' })

      get '/sitemap.xml'

      expect(response.body).not_to include("/en/features/#{page.slug}</loc>")
    end

    it 'reports the last modification rather than the first publication' do
      page = SitePage.find_by!(locale: 'en', kind: 'standing', key: 'about')
      page.update!(title: 'Edited today')

      get '/sitemap.xml'

      expect(response.body).to include("<lastmod>#{page.reload.updated_at.to_date.iso8601}</lastmod>")
    end

    # D3: the marketing site, and its sitemap, answer on the platform's own host and never on a tenant's.
    it 'is not served on a tenant custom domain' do
      account = create(:account)
      create(:portal, account: account, custom_domain: 'docs.customer.example', slug: 'tenant-portal')

      host! 'docs.customer.example'
      get '/sitemap.xml'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'robots.txt' do
    it 'advertises the marketing sitemap at an absolute address' do
      with_modified_env FRONTEND_URL: 'https://chat.lynomia.com' do
        get '/robots.txt'
      end

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Sitemap: https://chat.lynomia.com/sitemap.xml')
    end

    # A `Sitemap:` line must be absolute, and a crawler reports a wrong one as an error and stops asking --
    # so an installation with no host configured gets the rules and no hint, rather than a relative line.
    it 'advertises nothing when no host is configured' do
      get '/robots.txt'

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('Sitemap:')
      expect(response.body).to include('User-agent: *')
    end

    # The preview URL serves the PUBLISHED page to an anonymous crawler, with a canonical pointing at the
    # clean address -- a duplicate with a correct canonical, which is crawl budget spent for nothing.
    it 'keeps the draft preview parameter out of the index' do
      get '/robots.txt'

      expect(response.body).to include('Disallow: /*?preview=')
    end

    it 'still disallows everything it disallowed before' do
      get '/robots.txt'

      %w[/widget /app/ /super_admin/ /api/ /installation/ /rails/].each do |path|
        expect(response.body).to include("Disallow: #{path}")
      end
    end
  end

  describe 'structured data' do
    def json_ld(body)
      body.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).flatten.map { |raw| JSON.parse(raw) }
    end

    it 'describes the publisher and the site on the home page, once each' do
      get '/en/home'

      types = json_ld(response.body).map { |node| node['@type'] }
      expect(types).to contain_exactly('Organization', 'WebSite')
    end

    # Every value is a fact this repository can point at. None of these exists, so none is claimed.
    it 'claims no rating, no social profile and no price' do
      get '/en/home'

      payload = json_ld(response.body)
      expect(payload.to_json).not_to match(/aggregateRating|sameAs|priceRange|offers|SearchAction/)
    end

    it 'does not repeat the publisher node on every other page' do
      get '/en/features'

      expect(json_ld(response.body).map { |node| node['@type'] }).not_to include('Organization')
    end

    it 'mirrors the visible breadcrumb on a detail page' do
      get '/en/features/unified-inbox'

      breadcrumb = json_ld(response.body).find { |node| node['@type'] == 'BreadcrumbList' }
      expect(breadcrumb).to be_present

      names = breadcrumb['itemListElement'].map { |item| item['name'] }
      # The same three labels the rendered trail shows, in the same order.
      expect(names.size).to eq(3)
      names.each { |name| expect(response.body).to include(name) }
      expect(breadcrumb['itemListElement'].map { |item| item['position'] }).to eq([1, 2, 3])
    end

    it 'builds the FAQ nodes from the same rows the page renders' do
      get '/en/faq'

      faq = json_ld(response.body).find { |node| node['@type'] == 'FAQPage' }
      expect(faq).to be_present
      expect(faq['mainEntity'].size).to eq(SiteFaqEntry.published_for('en').count)

      first = SiteFaqEntry.published_for('en').first
      expect(faq['mainEntity'].first['name']).to eq(first.question)
      expect(faq['mainEntity'].first['acceptedAnswer']['text']).to eq(first.answer)
      expect(response.body).to include(first.question)
    end

    it 'tells a crawler nothing about a page that is not indexable' do
      page = SitePage.find_by!(locale: 'en', kind: 'standing', key: 'faq')
      page.update!(meta: { 'noindex' => '1' })

      get '/en/faq'

      expect(json_ld(response.body)).to be_empty
      expect(response.body).to include('noindex')
    end

    # The one thing a JSON-LD block must never do is end early. `json_escape` is what stops it.
    it 'cannot be broken out of by text an operator typed' do
      entry = SiteFaqEntry.published_for('en').first
      entry.update!(question: 'What about </script><script>alert(1)</script> this?')

      get '/en/faq'

      expect(response.body).not_to include('</script><script>alert(1)')
      faq = json_ld(response.body).find { |node| node['@type'] == 'FAQPage' }
      expect(faq['mainEntity'].first['name']).to include('alert(1)')
    end
  end
end
