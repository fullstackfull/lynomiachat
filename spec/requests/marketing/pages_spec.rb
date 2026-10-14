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

  describe 'the catalogue itself' do
    # The link graph is curated by hand, so a typo in it is a NoMethodError on nil in the detail template.
    it 'resolves every related feature and every named channel' do
      Marketing::Catalog::COLLECTIONS.each_value do |entries|
        entries.each do |entry|
          entry.related_ids.each do |id|
            expect(Marketing::Catalog.feature(id)).to be_present, "#{entry.id} relates to unknown feature #{id}"
          end
          entry.channel_ids.each do |id|
            expect(Marketing::Catalog.channel(id)).to be_present, "#{entry.id} names unknown channel #{id}"
          end
        end
      end
    end

    # A page with no copy renders a heading and nothing else, which is the thin page this site must not have.
    it 'has detail copy in both locales for every entry that has a page' do
      %w[ar en].each do |locale|
        I18n.with_locale(locale) do
          Marketing::Catalog::COLLECTIONS.each do |scope, entries|
            entries.select(&:detail?).each do |entry|
              key = "marketing.#{scope}.#{entry.id}.detail"
              expect(I18n.t("#{key}.lede", default: nil)).to be_present, "#{locale}/#{entry.id} has no lede"
              expect(I18n.t("#{key}.points", default: [])).to be_present, "#{locale}/#{entry.id} has no points"
            end
          end
        end
      end
    end
  end

  describe 'the catalogue detail pages' do
    let(:channel_paths) do
      Marketing::Catalog.channels.select(&:detail?).map { |entry| "/channels/#{entry.slug}" }
    end
    let(:feature_paths) do
      Marketing::Catalog.features.select(&:detail?).map { |entry| "/features/#{entry.slug}" }
    end

    it 'gives every feature a page, in both locales, with its own canonical' do
      (feature_paths + feature_paths.map { |path| "/en#{path}" }).each do |path|
        get path

        expect(response).to have_http_status(:success), "#{path} did not render"
        expect(response.body).to match(/<link rel="canonical" href="[^"]*#{Regexp.escape(path)}">/),
                                 "#{path} canonical does not point at itself"
      end
    end

    it 'has no dead links on any feature page' do
      (feature_paths + feature_paths.map { |path| "/en#{path}" }).each do |path|
        get path
        dead = response.body.scan(/href="(#|)"/)

        expect(dead).to be_empty, "#{path} has #{dead.size} dead link(s)"
      end
    end

    it 'states the prerequisite on a conditional feature page and omits the callout on an available one' do
      get '/en/features/flow-builder'
      expect(response.body).to include('Needs:')

      get '/en/features/unified-inbox'
      expect(response.body).not_to include('Needs:')
    end

    # The six claims docs 02 section 6 struck off, checked on the pages that would be tempted to restore them.
    it 'does not restore a struck-off claim on the pages nearest to it' do
      get '/en/features/security'
      body = response.body
      expect(body).to include('No certification is claimed')
      expect(body).to include('not every action an agent takes')
      expect(body).not_to match(/99\.9|uptime|SOC 2 certified|ISO 27001 certified/i)

      get '/en/features/ai-assist'
      expect(response.body).to include('does not operate an autonomous AI agent')

      get '/en/features/commerce'
      expect(response.body).to include('read-only')

      get '/en/features/analytics'
      expect(response.body).to include('no revenue or order-value reporting')
    end

    it 'gives every channel with a page one, in both locales, with its own canonical' do
      (channel_paths + channel_paths.map { |path| "/en#{path}" }).each do |path|
        get path

        expect(response).to have_http_status(:success), "#{path} did not render"
        expect(response.body).to match(/<link rel="canonical" href="[^"]*#{Regexp.escape(path)}">/),
                                 "#{path} canonical does not point at itself"
      end
    end

    it 'states the prerequisite on every channel page, because every channel needs the customer provider' do
      channel_paths.each do |path|
        get "/en#{path}"

        expect(response.body).to include('You supply:'), "/en#{path} does not say what the customer supplies"
      end
    end

    it 'has no dead links on any detail page' do
      (channel_paths + channel_paths.map { |path| "/en#{path}" }).each do |path|
        get path
        dead = response.body.scan(/href="(#|)"/)

        expect(dead).to be_empty, "#{path} has #{dead.size} dead link(s)"
      end
    end

    it 'puts a breadcrumb on a detail page that leads back to its index' do
      get '/en/channels/whatsapp'

      expect(response.body).to include('aria-label="Breadcrumb"')
      expect(response.body).to include('href="/en/channels"')
    end

    it '404s an unknown slug rather than rendering a page with the slug in the title' do
      get '/en/channels/whatsapp-calling'

      expect(response).to have_http_status(:not_found)
    end

    # TikTok is the one entry the inventory says to mention and not to build a page for.
    it 'gives the beta channel no page of its own, and does not link to one from the index' do
      get '/en/channels/tiktok'
      expect(response).to have_http_status(:not_found)

      get '/en/channels'
      expect(response.body).to include('TikTok')
      expect(response.body).not_to include('/channels/tiktok')
    end

    # The scope travels as a route default, and a route default shares the params namespace with the query
    # string. If a query parameter could win, `?scope=features` would read the wrong catalogue and the wrong
    # I18n branch for the same URL.
    it 'ignores a scope supplied in the query string' do
      get '/en/channels/whatsapp?scope=features'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('href="/en/channels"')
    end

    it 'does not restore a struck-off claim on the WhatsApp page' do
      get '/en/channels/whatsapp'

      expect(response.body).to include('are not part of this product')
      expect(response.body).not_to match(/360dialog is offered|voice calling is available/i)
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
