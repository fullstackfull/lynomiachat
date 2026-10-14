require 'rails_helper'

# The marketing site's request-level contract.
#
# These examples pin the things the previous site got wrong, so that a regression is a failing test rather than
# a discovery on the live host: the Arabic page is served in Arabic by the server, both locales are reachable
# at their own URLs, every page carries the discovery tags the old one lacked entirely, no link is dead, and
# the site never answers on a tenant's custom domain.
describe 'Marketing pages' do
  let(:pages) { { home: '/home', features: '/features', channels: '/channels', support: '/support' } }

  describe 'the Arabic tree' do
    it 'serves every page in Arabic, right to left, without any client-side switch' do
      pages.each_value do |path|
        get path

        expect(response).to have_http_status(:success), "#{path} did not render"
        expect(response.body).to include('<html lang="ar" dir="rtl">')
      end
    end

    it 'renders Arabic content rather than an English page waiting to be translated' do
      get '/home'

      expect(response.body).to include('كل محادثات عملائك')
    end
  end

  describe 'the English tree' do
    it 'serves every page at its own /en URL, left to right' do
      pages.each_value do |path|
        get "/en#{path}"

        expect(response).to have_http_status(:success), "/en#{path} did not render"
        expect(response.body).to include('<html lang="en" dir="ltr">')
      end
    end

    # One page, one URL. A second address for the same Arabic page would be a duplicate for a crawler to
    # choose between, which is why the locale segment is constrained to `en` alone.
    it 'does not answer at /ar, which would be a second URL for the Arabic page' do
      get '/ar/features'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'discovery tags' do
    it 'gives every page a title, a description, a canonical and a reciprocal hreflang pair' do
      pages.each_value do |path|
        get path
        body = response.body

        expect(body).to match(%r{<title>[^<]+</title>}), "#{path} has no title"
        expect(body).to include('name="description"'), "#{path} has no meta description"
        expect(body).to include('rel="canonical"'), "#{path} has no canonical"
        expect(body).to include('hreflang="ar"').and(include('hreflang="en"')).and(include('hreflang="x-default"'))
      end
    end

    it 'points the canonical of an English page at the English URL, not the Arabic one' do
      get '/en/features'

      expect(response.body).to match(%r{<link rel="canonical" href="[^"]*/en/features">})
    end

    it 'carries Open Graph tags so a shared link renders as a card' do
      get '/home'

      expect(response.body).to include('property="og:title"').and(include('property="og:url"'))
    end
  end

  describe 'links' do
    # The old footer promised four legal documents and a live chat and delivered four empty anchors; the whole
    # page contained no mailto:, tel: or wa.me at all. Nothing here may be a placeholder.
    it 'has no dead links on any page, in either locale' do
      (pages.values + pages.values.map { |path| "/en#{path}" }).each do |path|
        get path
        dead = response.body.scan(/href="(#|)"/)

        expect(dead).to be_empty, "#{path} has #{dead.size} dead link(s)"
      end
    end

    it 'links the live documentation and changelog rather than restating them' do
      get '/home'

      expect(response.body).to include('href="/docs"')
      get '/support'
      expect(response.body).to include('href="/changelog"')
    end

    it 'offers a working email address rather than printing one as text' do
      get '/support'

      expect(response.body).to include('href="mailto:info@lynomia.com"')
    end

    # There is no account-less ticket URL and no post-login return, so the honest action is sign-in-first.
    it 'sends a visitor who wants a ticket to sign in, not to a guessed account id' do
      get '/support'

      expect(response.body).to include('href="/app/login"')
      expect(response.body).not_to match(%r{/app/accounts/\d+/help})
    end
  end

  describe 'host scoping' do
    let!(:portal) do
      create(:portal, name: 'Tenant docs', slug: 'tenant-docs', custom_domain: 'docs.customer.example')
    end

    # A registered custom domain resolves through the same route table, so without the filter the marketing
    # site would also answer inside a customer's own Help Center domain.
    it 'does not answer on a tenant custom domain' do
      host! portal.custom_domain

      get '/features'

      expect(response).to have_http_status(:not_found)
    end

    it 'still answers on the platform host' do
      get '/features'

      expect(response).to have_http_status(:success)
    end
  end

  describe 'availability honesty' do
    it 'labels a conditional capability instead of presenting it as generally available' do
      get '/en/features'

      expect(response.body).to include('setup needed')
      expect(response.body).to include('Needs:')
    end

    # The assertion is about the CLAIM, not the word: the page is allowed to say Lynomia does not operate an
    # autonomous agent, and must not say it does. An earlier version of this example matched on 'autonomous'
    # alone and failed on that very denial.
    it 'never implies an autonomous AI agent' do
      get '/en/features'

      expect(response.body).to include('AI assist for agents')
      expect(response.body).to include('your own OpenAI key')
      expect(response.body).to include('does not operate an autonomous')
      expect(response.body).not_to match(/AI (agent|bot) (that )?(answers|replies|resolves)/i)
      expect(response.body).not_to match(/resolves? (them )?on its own|auto-repl/i)
    end

    it 'claims nine channels, which is the verified count, and marks TikTok as beta' do
      get '/en/channels'

      expect(Marketing::Catalog.channel_count).to eq(9)
      expect(response.body).to include('beta')

      # Scoped to the rendered channel names. A document-wide scan for 'Twitter' matches the twitter:card meta
      # tag in the head, which is an Open Graph declaration and not a claim about a supported channel.
      names = response.body.scan(/<h2[^>]*>\s*([^<]+?)\s*</).flatten
      expect(names.join(' | ')).not_to match(/Twitter|Voice|360dialog/i)
    end
  end
end
