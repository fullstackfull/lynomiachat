require 'rails_helper'

# The CMS screens for the website's navigation, questions and retired URLs.
#
# These are full Administrate resources -- an index route and a matching dashboard -- so unlike the
# hand-written Super Admin pages in this repository none of them needs an entry in the navigation exclusion
# array. Every example that loads a page is therefore also a check that the shared navigation partial, which
# renders on EVERY Super Admin page, still builds with these controllers in the route table.
RSpec.describe 'Super Admin website CMS', type: :request do
  let(:super_admin) { create(:super_admin) }

  # Anonymous first, before anything signs in: `sign_out` does not clear a Warden session in a request spec.
  describe 'authorization' do
    it 'refuses an anonymous visitor on every CMS list' do
      %w[site_nav_links site_faq_entries site_redirects].each do |resource|
        get "/super_admin/#{resource}"

        expect(response).to have_http_status(:redirect)
      end
    end

    it 'refuses an anonymous visitor on a write' do
      expect { post '/super_admin/site_redirects', params: { site_redirect: { from_path: '/x', to_path: '/y' } } }
        .not_to change(SiteRedirect, :count)
    end
  end

  context 'when signed in as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    describe 'navigation links' do
      let!(:link) do
        SiteNavLink.create!(locale: 'en', placement: 'header', label: 'Features', page_kind: 'standing',
                            page_key: 'features', position: 1)
      end

      it 'lists them in the order the public navigation renders them' do
        SiteNavLink.create!(locale: 'en', placement: 'header', label: 'Pricing', page_kind: 'standing',
                            page_key: 'pricing', position: 0)

        get '/super_admin/site_nav_links'

        expect(response).to have_http_status(:success)
        expect(response.body.index('Pricing')).to be < response.body.index('Features')
      end

      # The one question an operator has about a nav row that a saved record cannot answer on its own.
      it 'says whether the link will actually appear' do
        get "/super_admin/site_nav_links/#{link.id}"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('page:standing:features')
        # The target page does not exist, so the public navigation would drop this link.
        expect(link.resolves).to be(false)
      end

      it 'resolves once the target page is published' do
        SitePage.create!(locale: 'en', kind: 'standing', key: 'features', title: 'Features', status: :published)

        expect(link.resolves).to be(true)
      end

      it 'creates one from the form' do
        expect do
          post '/super_admin/site_nav_links',
               params: { site_nav_link: { locale: 'ar', placement: 'footer_product', label: 'الأسعار',
                                          page_kind: 'standing', page_key: 'pricing', position: '2',
                                          visible: '1' } }
        end.to change(SiteNavLink, :count).by(1)

        expect(SiteNavLink.last.target).to eq('page:standing:pricing')
      end

      it 'refuses a link with both a page and an external URL' do
        expect do
          post '/super_admin/site_nav_links',
               params: { site_nav_link: { locale: 'en', placement: 'header', label: 'Both',
                                          page_kind: 'standing', page_key: 'pricing',
                                          href: 'https://example.com' } }
        end.not_to change(SiteNavLink, :count)

        # Administrate re-renders the form with the errors beside their fields, at the status this
        # repository's rule asks for on invalid input.
        expect(response).to have_http_status(:unprocessable_entity)
      end

      # The nav is a public href, so the allowlist is the thing that matters most on this form.
      it 'refuses a javascript: link' do
        expect do
          post '/super_admin/site_nav_links',
               params: { site_nav_link: { locale: 'en', placement: 'header', label: 'Bad',
                                          href: 'javascript:alert(1)' } }
        end.not_to change(SiteNavLink, :count)
      end

      it 'reorders and hides from the form' do
        patch "/super_admin/site_nav_links/#{link.id}",
              params: { site_nav_link: { locale: 'en', placement: 'header', label: 'Features',
                                         page_kind: 'standing', page_key: 'features', position: '9',
                                         visible: '0' } }

        expect(link.reload.position).to eq(9)
        expect(link.visible).to be(false)
      end
    end

    describe 'FAQ entries' do
      let!(:entry) do
        SiteFaqEntry.create!(locale: 'en', question: 'Do you publish prices?',
                             answer: 'Not today. Ask for a quote.', position: 0)
      end

      it 'lists and shows them' do
        get '/super_admin/site_faq_entries'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Do you publish prices?')

        get "/super_admin/site_faq_entries/#{entry.id}"
        expect(response.body).to include('Not today. Ask for a quote.')
      end

      it 'creates one from the form' do
        expect do
          post '/super_admin/site_faq_entries',
               params: { site_faq_entry: { locale: 'ar', question: 'هل تدعمون واتساب؟',
                                           answer: 'نعم، عبر واجهة واتساب الرسمية.', position: '1',
                                           visible: '1' } }
        end.to change(SiteFaqEntry, :count).by(1)
      end

      it 'refuses a linked page with a kind and no key' do
        expect do
          post '/super_admin/site_faq_entries',
               params: { site_faq_entry: { locale: 'en', question: 'Q', answer: 'A',
                                           link_page_kind: 'feature', link_label: 'Read more' } }
        end.not_to change(SiteFaqEntry, :count)
      end
    end

    describe 'redirects' do
      it 'creates one for a renamed slug' do
        expect do
          post '/super_admin/site_redirects',
               params: { site_redirect: { from_path: '/en/features/old-name',
                                          to_path: '/en/features/new-name',
                                          permanent: '1', reason: 'renamed' } }
        end.to change(SiteRedirect, :count).by(1)

        expect(SiteRedirect.last.status).to eq(:moved_permanently)
      end

      # An absolute `to_path` is an open redirect, and raise_on_open_redirects is on in this application --
      # so one would raise in production rather than redirect. It is refused on save instead.
      it 'refuses an absolute destination' do
        expect do
          post '/super_admin/site_redirects',
               params: { site_redirect: { from_path: '/en/features/x', to_path: 'https://evil.example/' } }
        end.not_to change(SiteRedirect, :count)
      end

      it 'refuses a protocol-relative destination' do
        expect do
          post '/super_admin/site_redirects',
               params: { site_redirect: { from_path: '/en/features/x', to_path: '//evil.example/' } }
        end.not_to change(SiteRedirect, :count)
      end

      it 'refuses a redirect to itself' do
        expect do
          post '/super_admin/site_redirects',
               params: { site_redirect: { from_path: '/en/features/x', to_path: '/en/features/x' } }
        end.not_to change(SiteRedirect, :count)
      end

      it 'lets an operator retire one' do
        redirect = SiteRedirect.create!(from_path: '/en/features/x', to_path: '/en/features/y')

        expect { delete "/super_admin/site_redirects/#{redirect.id}" }.to change(SiteRedirect, :count).by(-1)
      end
    end
  end
end
