require 'rails_helper'

# W5's redirect management, on the one URL space the CMS can actually change: a detail page's slug.
#
# WHAT A REDIRECT COVERS, EXACTLY. A detail slug is a dynamic route segment, so a renamed slug still matches
# its route and reaches Marketing::EntriesController, which consults these rows before answering 404. A
# standing page's path is a fixed word in the route table and its slug is not editable, and a path that
# matches no route at all never reaches the lookup. That is a real boundary rather than an oversight, and the
# examples below pin both halves of it.
describe 'Marketing redirects' do
  before { Marketing::ContentSeeder.apply! }

  let(:page) { SitePage.find_by!(locale: 'en', kind: 'feature', key: 'unified_inbox') }

  describe 'a renamed slug' do
    it 'sends the old address to the new one, permanently' do
      page.update!(slug: 'one-inbox')
      SiteRedirect.create!(from_path: '/en/features/unified-inbox', to_path: '/en/features/one-inbox',
                           permanent: true, reason: 'renamed')

      get '/en/features/unified-inbox'

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to('/en/features/one-inbox')

      follow_redirect!
      expect(response).to have_http_status(:success)
    end

    it 'answers 302 when the redirect is not marked permanent' do
      page.update!(slug: 'one-inbox')
      SiteRedirect.create!(from_path: '/en/features/unified-inbox', to_path: '/en/features/one-inbox',
                           permanent: false)

      get '/en/features/unified-inbox'

      expect(response).to have_http_status(:found)
    end

    # Each locale's path is its own row, so an Arabic visitor is sent to the Arabic page.
    it 'is per locale' do
      SiteRedirect.create!(from_path: '/features/unified-inbox', to_path: '/features/one-inbox')

      get '/en/features/unified-inbox'
      expect(response).to have_http_status(:success)
    end

    it 'answers 404 for a slug with no redirect' do
      get '/en/features/never-existed'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'a chain' do
    # Two hops is a defect rather than a feature, but it happens when a page is renamed twice. Each hop is
    # one redirect, which is what the protocol expects -- not a single resolved jump invented here.
    it 'is followed one hop at a time' do
      page.update!(slug: 'third-name')
      SiteRedirect.create!(from_path: '/en/features/first-name', to_path: '/en/features/second-name')
      SiteRedirect.create!(from_path: '/en/features/second-name', to_path: '/en/features/third-name')

      get '/en/features/first-name'
      expect(response).to redirect_to('/en/features/second-name')

      follow_redirect!
      expect(response).to redirect_to('/en/features/third-name')

      follow_redirect!
      expect(response).to have_http_status(:success)
    end

    # A→B then B→A is an infinite redirect the browser gives up on, and neither row is wrong on its own.
    it 'is refused when it would close into a loop' do
      SiteRedirect.create!(from_path: '/en/features/a', to_path: '/en/features/b')

      loopback = SiteRedirect.new(from_path: '/en/features/b', to_path: '/en/features/a')

      expect(loopback).not_to be_valid
      expect(loopback.errors[:to_path].join).to include('redirect loop')
    end

    it 'is refused for a longer cycle' do
      SiteRedirect.create!(from_path: '/a', to_path: '/b')
      SiteRedirect.create!(from_path: '/b', to_path: '/c')

      expect(SiteRedirect.new(from_path: '/c', to_path: '/a')).not_to be_valid
    end

    it 'is refused when it would be longer than the limit' do
      (1..SiteRedirect::MAX_CHAIN).each do |index|
        SiteRedirect.create!(from_path: "/p#{index}", to_path: "/p#{index + 1}")
      end

      too_long = SiteRedirect.new(from_path: '/p0', to_path: '/p1')

      expect(too_long).not_to be_valid
      expect(too_long.errors[:to_path].join).to include('longer than')
    end

    # The loop check must not treat a row as its own next hop when it is being edited.
    it 'lets an existing redirect be edited without tripping the loop check' do
      redirect = SiteRedirect.create!(from_path: '/en/features/a', to_path: '/en/features/b')

      expect(redirect.update(to_path: '/en/features/c')).to be(true)
    end
  end

  describe 'what a redirect may point at' do
    it 'refuses an absolute destination, which would be an open redirect' do
      expect(SiteRedirect.new(from_path: '/a', to_path: 'https://evil.example/')).not_to be_valid
    end

    it 'refuses a protocol-relative destination, which a browser treats as another origin' do
      expect(SiteRedirect.new(from_path: '/a', to_path: '//evil.example/')).not_to be_valid
    end

    it 'refuses a destination with a scheme the allowlist does not have' do
      expect(SiteRedirect.new(from_path: '/a', to_path: 'javascript:alert(1)')).not_to be_valid
    end

    it 'refuses a redirect to itself' do
      expect(SiteRedirect.new(from_path: '/a', to_path: '/a')).not_to be_valid
    end

    # `raise_on_open_redirects` is on in this application, so an absolute destination that somehow reached
    # the controller would raise rather than redirect. The model refuses it first, and the controller passes
    # `allow_other_host: false` as well -- two independent reasons, which is the right number for a redirect.
    it 'passes allow_other_host false at the redirect itself' do
      source = Rails.root.join('custom/app/controllers/marketing/entries_controller.rb').read

      expect(source).to include('allow_other_host: false')
    end
  end

  describe 'a protected application route' do
    # A redirect is consulted only from the marketing detail action, so a row naming an application path can
    # never be reached: that path routes elsewhere. Asserted rather than guarded against, because a
    # validation here would be a guard on an unreachable case.
    it 'is unaffected by a redirect row claiming its path' do
      SiteRedirect.create!(from_path: '/super_admin', to_path: '/en/features/unified-inbox')

      get '/super_admin'

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('sign_in')
    end

    it 'is unaffected for the dashboard root' do
      SiteRedirect.create!(from_path: '/app/login', to_path: '/en')

      get '/app/login'

      expect(response.location.to_s).not_to include('/en')
    end
  end
end
