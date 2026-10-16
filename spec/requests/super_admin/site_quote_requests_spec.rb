require 'rails_helper'

# The operator's side of the pricing page.
#
# The first example is not really about this resource: Administrate builds the Super Admin navigation by
# enumerating every controller under `super_admin/` in the route table and asking each for an index route and
# a dashboard, and a controller with neither raises inside the navigation partial -- breaking EVERY Super
# Admin page, not just its own. A full Administrate resource needs no entry in the exclusion array at
# app/views/super_admin/application/_navigation.html.erb, and this proves it.
RSpec.describe 'Super Admin site quote requests', type: :request do
  let(:super_admin) { create(:super_admin) }

  # Anonymous first, before anything signs in: `sign_out` does not clear a Warden session in a request spec,
  # so an example that needs to be anonymous cannot undo a shared sign-in.
  it 'refuses an anonymous visitor' do
    get '/super_admin/site_quote_requests'

    expect(response).to have_http_status(:redirect)
  end

  context 'when signed in as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'lists requests, newest first, without breaking the navigation' do
      older = SiteQuoteRequest.create!(name: 'Older', email: 'older@example.com', locale: 'en',
                                       created_at: 2.days.ago)
      newer = SiteQuoteRequest.create!(name: 'Newer', email: 'newer@example.com', locale: 'ar')

      get '/super_admin/site_quote_requests'

      expect(response).to have_http_status(:success)
      expect(response.body.index('Newer')).to be < response.body.index('Older')
      expect(response.body).to include("##{newer.id}").or include(newer.name)
      expect(older.reload.status).to eq('new_request')
    end

    it 'shows a request with what the visitor sent' do
      quote = SiteQuoteRequest.create!(name: 'Noura', email: 'noura@example.com', locale: 'ar',
                                       channels: %w[whatsapp], message: 'We sell online.')

      get "/super_admin/site_quote_requests/#{quote.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('noura@example.com')
      expect(response.body).to include('We sell online.')
    end

    it 'lets the operator move a request along' do
      quote = SiteQuoteRequest.create!(name: 'Noura', email: 'noura@example.com', locale: 'ar')

      patch "/super_admin/site_quote_requests/#{quote.id}",
            params: { site_quote_request: { status: 'contacted' } }

      expect(quote.reload.status).to eq('contacted')
    end

    # These rows are written by visitors on the public page; an operator-created one would be a request
    # nobody sent, so the route does not exist. The id is constrained to digits, so this is answered by the
    # router -- without the constraint it would match `show` with `id: "new"` and 404 from the record lookup
    # instead, which is the same status for a worse reason.
    it 'has no create form' do
      get '/super_admin/site_quote_requests/new'

      expect(response).to have_http_status(:not_found)
    end
  end
end
