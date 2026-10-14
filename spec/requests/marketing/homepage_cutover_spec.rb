require 'rails_helper'

# THE HOMEPAGE CUTOVER: `/` is the website, on the platform's own host and nowhere else.
#
# `/` is the one address three different things have a claim on, and this file is the contract between them:
# the marketing site wants it, a tenant's Help Center custom domain already had it, and the dashboard answers
# it everywhere else. The decision is made once, by host, in Marketing::OfficialHost, and the Rails root
# declines by request constraint rather than DashboardController being changed -- so the examples below that
# assert the custom-domain and dashboard behaviour are asserting that the cutover left them alone.
#
# WHY `with_modified_env` AND `host!` ARE EVERYWHERE HERE. FRONTEND_URL is unset in the test environment and a
# request spec's default host is `www.example.com`, so "the platform's own host" has to be stated. That is
# also what keeps the rest of the suite's `get '/'` examples (spec/controllers/dashboard_custom_domain_spec.rb,
# spec/requests/search_indexing_spec.rb) meaning what they meant before the cutover.
describe 'The homepage cutover' do
  let(:official_host) { 'chat.lynomia.test' }

  before { Marketing::ContentSeeder.apply! }

  describe 'on the platform host' do
    around do |example|
      with_modified_env(FRONTEND_URL: "https://#{official_host}") { example.run }
    end

    before { host! official_host }

    it 'serves the Arabic homepage at /' do
      get '/'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<html lang="ar" dir="rtl">')
      expect(response.body).to include('كل محادثات عملائك')
    end

    it 'serves the English homepage at /en' do
      get '/en'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<html lang="en" dir="ltr">')
    end

    # The failure this guards against is the obvious one for a root change: `/` redirecting to the page that
    # redirects back to `/`.
    it 'answers / directly rather than redirecting anywhere' do
      get '/'

      expect(response).to have_http_status(:ok)
      expect(response.headers['Location']).to be_nil
    end

    # A redirect row is only consulted when a detail-page slug 404s
    # (Marketing::EntriesController, custom/app/controllers/marketing/entries_controller.rb:53), so the
    # homepage is structurally out of its reach. This is the example that keeps it that way: the operator can
    # save the row -- `/` is a legal `from_path` -- and it still cannot move the front door.
    it 'cannot be redirected away by an operator-saved redirect row' do
      SiteRedirect.create!(from_path: '/', to_path: '/en', permanent: true)

      get '/'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<html lang="ar" dir="rtl">')
    end

    describe 'the addresses the homepage used to have' do
      it 'sends /home to / permanently' do
        get '/home'

        expect(response).to have_http_status(:moved_permanently)
        expect(response).to redirect_to('/')
      end

      it 'sends /en/home to /en permanently, keeping the locale' do
        get '/en/home'

        expect(response).to have_http_status(:moved_permanently)
        expect(response).to redirect_to('/en')
      end

      # An operator's link to a draft homepage is `/home?preview=1`. A Rails block redirect returns a path and
      # nothing carries the query across, so this is the half that has to be done by hand.
      it 'carries the query string, so an old preview link still previews' do
        get '/home?preview=1'

        expect(response).to redirect_to('/?preview=1')
      end

      # The query string is the only part of that Location an outsider controls, and it is interpolated into
      # a header. The path in front of it is a literal and Rails builds the Location from the request's own
      # scheme and host, so the destination is this host's `/` whatever the query says.
      it 'keeps the redirect same-origin for a hostile query string' do
        get '/home?next=//evil.example/path&x=%0d%0aSet-Cookie:+a=b'

        location = URI.parse(response.headers['Location'])
        expect(location.host).to eq(official_host)
        expect(location.path).to eq('/')
        expect(response.headers.keys.map(&:downcase)).not_to include('set-cookie')
      end

      it 'lands somewhere that answers, in one hop' do
        get '/home'
        follow_redirect!

        expect(response).to have_http_status(:success)
        expect(response.body).to include('<html lang="ar" dir="rtl">')
      end
    end

    describe 'discovery metadata' do
      it 'points the canonical of each homepage at its new address' do
        get '/'
        expect(response.body).to include(%(<link rel="canonical" href="https://#{official_host}/">))

        get '/en'
        expect(response.body).to include(%(<link rel="canonical" href="https://#{official_host}/en">))
      end

      it 'pairs the two homepages with hreflang and x-defaults to Arabic' do
        get '/'

        expect(response.body).to include(%(hreflang="ar" href="https://#{official_host}/">))
        expect(response.body).to include(%(hreflang="en" href="https://#{official_host}/en">))
        expect(response.body).to include(%(hreflang="x-default" href="https://#{official_host}/">))
      end

      # The whole point of moving the route rather than adding a second one: nothing may still advertise the
      # old address. This covers the canonical, the hreflang set, og:url and every link in the chrome.
      it 'advertises /home nowhere, in either locale' do
        ['/', '/en'].each do |path|
          get path

          expect(response.body).not_to include('/home"')
          expect(response.body).not_to include('/home?')
        end
      end

      it 'lists the new addresses in the sitemap and the old one nowhere' do
        get '/sitemap.xml'

        expect(response.body).to include("<loc>https://#{official_host}/</loc>")
        expect(response.body).to include("<loc>https://#{official_host}/en</loc>")
        expect(response.body).not_to include('/home<')
      end
    end

    describe 'links that resolve through the CMS' do
      it 'resolves an operator-entered home target to /' do
        SiteNavLink.create!(locale: 'ar', placement: 'header', label: 'الصفحة الرئيسية',
                            page_kind: 'standing', page_key: 'home', position: 99)

        get '/'

        href = response.body[/<a href="([^"]*)"[^>]*>\s*الصفحة الرئيسية/m, 1]
        expect(href).to eq('/')
      end

      it 'links home from a detail page breadcrumb, in the trail and in its structured data' do
        get '/en/features/unified-inbox'

        expect(response).to have_http_status(:success)
        breadcrumb = response.body[%r{<nav aria-label="[^"]*"[^>]*>.*?</nav>}m]
        expect(breadcrumb).to include('href="/en"')

        nodes = response.body.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).flatten
        trail = nodes.map { |raw| JSON.parse(raw) }.find { |node| node['@type'] == 'BreadcrumbList' }
        expect(trail['itemListElement'].first['item']).to eq("https://#{official_host}/en")
      end
    end

    # The editor's "Preview" button builds this path from the route table (SitePage#public_path), so the
    # cutover had to move it too -- and a draft homepage is the one page an operator cannot check any other
    # way, because its published address is the site's front door.
    describe 'previewing a draft homepage' do
      let(:home) { SitePage.find_by(locale: 'ar', kind: 'standing', key: 'home') }

      it 'previews at /?preview=1 for a signed-in super admin' do
        home.update!(status: :draft)

        expect(home.public_path(preview: true)).to eq('/?preview=1')

        sign_in(create(:super_admin), scope: :super_admin)
        get '/?preview=1'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('<meta name="robots" content="noindex, nofollow">')
      end

      it 'still answers 404 at / for a visitor while the homepage is a draft' do
        home.update!(status: :draft)

        get '/'

        expect(response).to have_http_status(:not_found)
      end
    end

    describe 'the surfaces the cutover must not touch' do
      it 'leaves /app and /app/login with the dashboard' do
        ['/app', '/app/login'].each do |path|
          get path

          expect(response).to have_http_status(:success)
          expect(response.body).to include('<div id="app"></div>')
        end
      end

      it 'leaves /docs and /changelog pointing into the documentation portals' do
        config = { allowed_locales: ['en'], default_locale: 'en', layout: 'documentation' }
        docs = create(:portal, name: 'Docs', slug: Documentation::Library::DOCS_SLUG,
                               platform_owned: true, account: nil, config: config)
        changelog = create(:portal, name: 'Changelog', slug: Documentation::Library::CHANGELOG_SLUG,
                                    platform_owned: true, account: nil, config: config)

        get '/docs'
        expect(response).to redirect_to("/hc/#{docs.slug}")

        get '/changelog'
        expect(response).to redirect_to("/hc/#{changelog.slug}")
      end

      # The latch an unfinished installation sets, which `/` has always honoured
      # (DashboardController#ensure_installation_onboarding). The homepage took `/` and with it this.
      it 'still sends an unfinished installation to the setup wizard' do
        Redis::Alfred.set(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING, true)

        get '/'

        expect(response).to redirect_to('/installation/onboarding')
      ensure
        Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)
      end
    end
  end

  # D3, and the breakage a root change causes if nobody draws this line: a tenant whose Help Center is served
  # from their own domain still owns `/` on it.
  describe 'on a tenant Help Center custom domain' do
    let(:account) { create(:account) }
    let!(:portal) do
      create(:portal, account: account, slug: 'tenant-hc', custom_domain: 'help.customer.example',
                      config: { allowed_locales: ['en'], default_locale: 'en', layout: 'classic' })
    end

    around do |example|
      with_modified_env(FRONTEND_URL: "https://#{official_host}") { example.run }
    end

    before { host! portal.custom_domain }

    it 'renders that portal at / rather than the marketing homepage' do
      get '/'

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('<html lang="ar" dir="rtl">')
      expect(response.body).not_to include('كل محادثات عملائك')
    end

    it 'does not leak the English homepage onto it either' do
      get '/en'

      expect(response).to have_http_status(:not_found)
    end
  end

  # Every other host: a stale DNS record, a load-balancer probe, an IP address. `/` keeps the behaviour it had
  # before the cutover, which is the safe direction -- the website appears where it was configured to, not
  # wherever the application happens to answer.
  describe 'on an unrecognised host' do
    around do |example|
      with_modified_env(FRONTEND_URL: "https://#{official_host}") { example.run }
    end

    before { host! 'stale.example.com' }

    it 'leaves / with the dashboard' do
      get '/'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<div id="app"></div>')
      expect(response.body).not_to include('كل محادثات عملائك')
    end
  end

  # With the variable unset there is no official host to match, so `/` cannot become the website by accident
  # on an installation that has not been told its own address.
  describe 'with FRONTEND_URL unset' do
    it 'leaves / with the dashboard' do
      get '/'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<div id="app"></div>')
    end
  end

  describe Marketing::OfficialHost do
    it 'matches only the FRONTEND_URL host' do
      with_modified_env FRONTEND_URL: 'https://chat.lynomia.com' do
        expect(described_class.matches?(instance_double(ActionDispatch::Request, host: 'chat.lynomia.com'))).to be(true)
        expect(described_class.matches?(instance_double(ActionDispatch::Request, host: 'help.customer.example'))).to be(false)
      end
    end

    # Not a HELPCENTER_URL match: on an installation that serves documentation from its own hostname, that
    # host belongs to the Help Center and the marketing homepage must not take its root.
    it 'does not match the help centre host, and matches nothing when unconfigured' do
      with_modified_env FRONTEND_URL: '', HELPCENTER_URL: 'https://docs.lynomia.com' do
        expect(described_class.matches?(instance_double(ActionDispatch::Request, host: 'docs.lynomia.com'))).to be(false)
        expect(described_class.matches?(instance_double(ActionDispatch::Request, host: ''))).to be(false)
      end
    end
  end
end
