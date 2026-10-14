require 'rails_helper'

# W6's security review, as executable assertions rather than prose. One example per surface the owner named:
# XSS, CSRF, unauthorized publishing, cross-account access, unsafe redirects, uploads, and rate limiting on
# the public form.
#
# `Rack::Attack.enabled` is false outside production, so it is switched on around the throttle examples
# against an in-memory store -- the arrangement spec/requests/platform_support/security/
# abuse_protection_spec.rb established and explains.
RSpec.describe 'Marketing security', type: :request do
  before { Marketing::ContentSeeder.apply! }

  let(:super_admin) { create(:super_admin) }
  let(:about) { SitePage.find_by!(locale: 'en', kind: 'standing', key: 'about') }

  describe 'XSS' do
    # Section bodies are plain text and ERB escapes them. The repository has already shipped a stored XSS
    # through a Markdown path, which is why there is no Markdown here to re-open it.
    it 'escapes markup an operator typed into a section body' do
      sections = about.sections.map do |section|
        section['type'] == 'prose' ? section.merge('body' => '<script>alert(1)</script>') : section
      end
      about.update!(sections: sections)

      get '/en/about'

      expect(response.body).not_to include('<script>alert(1)</script>')
      expect(response.body).to include('&lt;script&gt;')
    end

    it 'escapes markup in a page title, which reaches the <title> and og:title' do
      about.update!(title: 'About</title><script>alert(1)</script>')

      get '/en/about'

      expect(response.body).not_to include('<script>alert(1)')
    end

    it 'escapes markup in an FAQ question, which reaches both the page and the JSON-LD' do
      entry = SiteFaqEntry.published_for('en').first
      entry.update!(question: '</script><script>alert(1)</script>')

      get '/en/faq'

      expect(response.body).not_to include('</script><script>alert(1)')
    end

    # A link target is the one operator value that reaches an attribute rather than a text node.
    it 'never renders a script URL as an href' do
      about.update_columns( # rubocop:disable Rails/SkipsModelValidations
        sections: [{ 'type' => 'hero', 'primary_label' => 'Go', 'primary_target' => 'javascript:alert(1)' }]
      )

      get '/en/about'

      expect(response.body).not_to include('javascript:')
    end
  end

  describe 'CSRF' do
    # THE QUOTE FORM IS THE ONE PUBLIC WRITE, and it inherited `PublicController`'s blanket
    # `skip_before_action :verify_authenticity_token` -- correct for a read-only Help Center, wrong for a
    # write. Measured before the fix: a token-less cross-site POST stored a row.
    it 'refuses a quote request with no authenticity token' do
      ActionController::Base.allow_forgery_protection = true

      expect do
        post '/en/pricing/request', params: { site_quote_request: { name: 'A', email: 'a@example.com' } }
      end.not_to change(SiteQuoteRequest, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    # The other half: the form's own token is accepted, so the fix refuses forgeries and not visitors.
    it 'accepts the submission the real form makes' do
      ActionController::Base.allow_forgery_protection = true
      get '/en/pricing'
      token = response.body[/name="authenticity_token" value="([^"]+)"/, 1]

      expect(token).to be_present
      expect do
        post '/en/pricing/request',
             params: { authenticity_token: token, site_quote_request: { name: 'A', email: 'a@example.com' } }
      end.to change(SiteQuoteRequest, :count).by(1)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it 'refuses a Super Admin write with no authenticity token' do
      sign_in(super_admin, scope: :super_admin)
      ActionController::Base.allow_forgery_protection = true

      patch "/super_admin/site_pages/#{about.id}", params: { site_page: { title: 'Hijacked' } }

      expect(about.reload.title).not_to eq('Hijacked')
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  describe 'unauthorized publishing' do
    let(:draft) do
      SitePage.create!(locale: 'en', kind: 'feature', key: 'secret_page', slug: 'secret-page',
                       title: 'Not for the public', status: :draft)
    end

    it 'refuses an anonymous publish and keeps the page off the site' do
      post "/super_admin/site_pages/#{draft.id}/publish"

      expect(draft.reload).to be_status_draft

      get '/en/features/secret-page'
      expect(response).to have_http_status(:not_found)
    end

    it 'refuses an anonymous edit of a published page' do
      patch "/super_admin/site_pages/#{about.id}", params: { site_page: { title: 'Defaced' } }

      expect(about.reload.title).not_to eq('Defaced')
    end

    # A draft is not reachable by guessing the preview parameter: it needs a super admin session.
    it 'does not serve a draft to an anonymous visitor who adds the preview parameter' do
      get "/en/features/#{draft.slug}?preview=1"

      expect(response).to have_http_status(:not_found)
    end

    it 'refuses a product user, who is not an operator' do
      sign_in(create(:user))

      post "/super_admin/site_pages/#{draft.id}/publish"

      expect(draft.reload).to be_status_draft
    end
  end

  describe 'cross-account access' do
    # The marketing site has no account scope at all -- it is installation-wide content -- so the boundary
    # that matters is the host: it must never answer inside a tenant's own Help Center domain.
    it 'answers nothing on a tenant custom domain' do
      create(:portal, account: create(:account), custom_domain: 'docs.customer.example', slug: 'tenant-hc')

      host! 'docs.customer.example'
      %w[/en /features /pricing /sitemap.xml].each do |path|
        get path
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'stores no tenant record for a quote request' do
      expect do
        post '/en/pricing/request', params: { site_quote_request: { name: 'A', email: 'a@example.com' } }
      end.to change(SiteQuoteRequest, :count).by(1)

      # A lead is not a customer: no account, no contact, no conversation is created from an unverified
      # stranger's input (SiteQuoteRequest says why).
      expect(Contact.count).to eq(0)
      expect(Conversation.count).to eq(0)
    end
  end

  describe 'unsafe redirects' do
    it 'refuses to store an absolute destination' do
      expect(SiteRedirect.new(from_path: '/en/features/x', to_path: 'https://evil.example/')).not_to be_valid
    end

    it 'does not follow a query parameter into another host' do
      get '/en/features/unified-inbox?redirect_to=https://evil.example/'

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('evil.example')
    end
  end

  describe 'uploads' do
    # Anonymous first, in its own describe with no sign-in: `sign_out` does not clear a Warden session in a
    # request spec, so an example that needs to be anonymous cannot undo a shared sign-in.
    it 'refuses an anonymous upload' do
      expect do
        post "/super_admin/site_pages/#{about.id}/upload_image",
             params: { file: fixture_file_upload('spec/assets/sample.png', 'image/png') }
      end.not_to(change { about.reload.marketing_images.count })
    end

    context 'when signed in as a super admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      # The type is read from the bytes, so a renamed file is refused on its contents.
      it 'refuses a file that is not an image whatever its name claims' do
        disguised = fixture_file_upload('spec/assets/contacts.csv', 'image/png')

        expect do
          post "/super_admin/site_pages/#{about.id}/upload_image", params: { file: disguised }
        end.not_to(change { about.reload.marketing_images.count })
      end

      # An SVG is a script container. It is refused at the boundary rather than relying on the delivery
      # route's disposition being the last line of defence.
      it 'refuses an SVG' do
        svg = Rails.root.join('tmp/w6-upload.svg')
        svg.write("<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>")

        expect do
          post "/super_admin/site_pages/#{about.id}/upload_image",
               params: { file: Rack::Test::UploadedFile.new(svg, 'image/svg+xml') }
        end.not_to(change { about.reload.marketing_images.count })
      ensure
        svg.delete if svg.exist?
      end

      # Marketing media is served by an app-owned route that publishes only attachments of PUBLISHED pages,
      # because robots.txt disallows /rails/ and an ActiveStorage signed id never expires.
      it 'does not serve an image attached to a draft page' do
        post "/super_admin/site_pages/#{about.id}/upload_image",
             params: { file: fixture_file_upload('spec/assets/sample.png', 'image/png') }
        attachment = about.reload.marketing_images.first
        about.update!(status: :draft)

        get "/site-media/#{attachment.id}"

        expect(response).to have_http_status(:not_found)
      end

      it 'does not serve an attachment that belongs to another subsystem' do
        account = create(:account)
        portal = create(:portal, account: account, slug: 'media-portal')
        portal.documentation_media.attach(io: Rails.root.join('spec/assets/sample.png').open,
                                          filename: 'sample.png', content_type: 'image/png')
        foreign = portal.documentation_media.first

        get "/site-media/#{foreign.id}"

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'rate limiting the public form' do
    let(:client_ip) { '203.0.113.42' }

    around do |example|
      previous_store = Rack::Attack.cache.store
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      Rack::Attack.enabled = true
      example.run
    ensure
      Rack::Attack.enabled = false
      Rack::Attack.cache.store = previous_store
    end

    def submit(email)
      post '/en/pricing/request', params: { site_quote_request: { name: 'A', email: email } },
                                  env: { 'REMOTE_ADDR' => client_ip }
    end

    it 'refuses the submission after the limit, and the refusal costs no row' do
      limit = ENV.fetch('RATE_LIMIT_MARKETING_QUOTE', '5').to_i

      limit.times { |index| submit("visitor#{index}@example.com") }
      expect(SiteQuoteRequest.count).to eq(limit)

      expect { submit('one-too-many@example.com') }.not_to change(SiteQuoteRequest, :count)
      expect(response).to have_http_status(:too_many_requests)
    end

    # Both locale paths share one counter, so the English path cannot be used to double the budget.
    it 'counts the Arabic and English paths together' do
      limit = ENV.fetch('RATE_LIMIT_MARKETING_QUOTE', '5').to_i
      limit.times { |index| submit("visitor#{index}@example.com") }

      post '/pricing/request', params: { site_quote_request: { name: 'A', email: 'ar@example.com' } },
                               env: { 'REMOTE_ADDR' => client_ip }

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'does not throttle reading the page' do
      20.times { get '/en/pricing', env: { 'REMOTE_ADDR' => client_ip } }

      expect(response).to have_http_status(:success)
    end
  end
end
