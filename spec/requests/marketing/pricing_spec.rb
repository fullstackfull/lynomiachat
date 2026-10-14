require 'rails_helper'

# The pricing page's contract, which is mostly a contract about what it does NOT say.
#
# docs/official-website/02-verified-feature-inventory.md section 4 establishes that no plan row, price,
# currency amount or tier exists anywhere in this repository, and that the old page's "free trial - no credit
# card" could not be delivered (the trial plan id defaults to nil and there is no plan for it to point at).
# So these examples pin two things: the page publishes only what an operator has marked for the website, and
# the quote request it collects actually works.
describe 'Marketing pricing' do
  # The page is a row now: its heading, standfirst and the "what a quote is based on" cards are sections an
  # operator can edit. The plan table and the form stay in the template because one reads the billing tables
  # and the other is a form.
  before { Marketing::ContentSeeder.apply! }

  describe 'what the page publishes' do
    it 'publishes no price at all when the operator has listed no plan' do
      get '/en/pricing'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('What a quote is based on')
      expect(response.body).not_to match(%r{\$\d|USD \d|\d+\s*/\s*month})
    end

    it 'makes no trial promise, which is the claim the old page could not deliver' do
      get '/en/pricing'

      expect(response.body).to include('no self-service trial on this site today')
      expect(response.body).not_to match(/free trial|no credit card/i)
    end

    it 'publishes a plan the operator has marked for the website' do
      create(:billing_plan, name: 'Team', price_cents: 4900, currency: 'usd', interval: 'month',
                            active: true, listed_on_website: true)

      get '/en/pricing'

      expect(response.body).to include('Team')
      expect(response.body).to include('49.00')
    end

    # `active` means "a customer may subscribe"; it is not permission to put the plan on a public page.
    it 'does not publish an active plan that is not marked for the website' do
      create(:billing_plan, name: 'Negotiated', price_cents: 123_400, active: true, listed_on_website: false)

      get '/en/pricing'

      expect(response.body).not_to include('Negotiated')
      expect(response.body).not_to include('1,234')
    end

    it 'carries its discovery tags and has no dead links, in both locales' do
      ['/pricing', '/en/pricing'].each do |path|
        get path

        expect(response.body).to match(/<link rel="canonical" href="[^"]*#{Regexp.escape(path)}">/)
        expect(response.body).to include('name="description"')
        expect(response.body.scan(/href="(#|)"/)).to be_empty, "#{path} has a dead link"
      end
    end

    it 'appears in the header navigation now that it exists' do
      get '/en/home'

      expect(response.body).to include('href="/en/pricing"')
    end
  end

  describe 'requesting a quote' do
    let(:valid_params) do
      { site_quote_request: { name: 'Noura', email: 'noura@example.com', company: 'Example Co',
                              phone: '+96555555555', team_size: '4-10',
                              channels: %w[whatsapp email], message: 'We sell online.' } }
    end

    it 'stores the request, redirects, and confirms on the page' do
      expect { post '/en/pricing/request', params: valid_params }
        .to change(SiteQuoteRequest, :count).by(1)

      expect(response).to redirect_to('/en/pricing?sent=1')

      quote = SiteQuoteRequest.last
      expect(quote.name).to eq('Noura')
      expect(quote.channels).to eq(%w[whatsapp email])
      expect(quote.status).to eq('new_request')

      follow_redirect!
      expect(response.body).to include('your request has been received')
    end

    # The locale is taken from the URL the form was posted to, not from a field the client controls, so the
    # reply goes back in the language the visitor was reading.
    it 'records the locale of the page the request came from' do
      post '/pricing/request', params: valid_params

      expect(SiteQuoteRequest.last.locale).to eq('ar')
    end

    it 'answers an invalid address with 422 and the form, not a redirect' do
      expect { post '/en/pricing/request', params: { site_quote_request: { name: 'A', email: 'not-an-email' } } }
        .not_to change(SiteQuoteRequest, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('Please check the following before sending')
    end

    it 'answers a POST with no parameters with the form rather than a 400' do
      post '/en/pricing/request'

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # The form offers the catalogue's own channel slugs, and the model validates against the same list, so a
    # value the form never offered cannot be stored.
    it 'rejects a channel the form never offered' do
      expect { post '/en/pricing/request', params: valid_params.deep_merge(site_quote_request: { channels: ['voice'] }) }
        .not_to change(SiteQuoteRequest, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'caps what one request can store' do
      quote = SiteQuoteRequest.new(name: 'a' * 121, email: 'a@b.com', locale: 'en')

      expect(quote).not_to be_valid
      expect(quote.errors[:name]).to be_present
    end
  end

  describe 'the operator notification' do
    let(:valid_params) do
      { site_quote_request: { name: 'Noura', email: 'noura@example.com' } }
    end

    it 'emails the configured address' do
      InstallationConfig.find_or_initialize_by(name: 'MARKETING_QUOTE_NOTIFICATION_EMAIL')
                        .update!(value: 'sales@example.com')
      GlobalConfig.clear_cache

      expect { post '/en/pricing/request', params: valid_params }
        .to have_enqueued_mail(Marketing::QuoteMailer, :new_request)
    end

    # The owner's requirement: a delivery problem must never cost the submission. `deliver_later` is already
    # asynchronous, but ENQUEUEING talks to Redis and can fail after the row is committed -- which would show
    # the visitor a 500 for a request that succeeded, and have them send it again.
    it 'still thanks the visitor when the notification cannot even be queued' do
      InstallationConfig.find_or_initialize_by(name: 'MARKETING_QUOTE_NOTIFICATION_EMAIL')
                        .update!(value: 'sales@example.com')
      GlobalConfig.clear_cache
      delivery = instance_double(ActionMailer::MessageDelivery)
      allow(delivery).to receive(:deliver_later).and_raise(Redis::CannotConnectError, 'down')
      allow(Marketing::QuoteMailer).to receive(:new_request).and_return(delivery)

      expect { post '/en/pricing/request', params: valid_params }
        .to change(SiteQuoteRequest, :count).by(1)

      expect(response).to redirect_to('/en/pricing?sent=1')
    end

    # An unset address costs the alert, not the lead: the row is written first and is listed in Super Admin.
    it 'stores the request and sends nothing when no address is configured' do
      InstallationConfig.find_by(name: 'MARKETING_QUOTE_NOTIFICATION_EMAIL')&.destroy
      GlobalConfig.clear_cache

      expect { post '/en/pricing/request', params: valid_params }
        .to change(SiteQuoteRequest, :count).by(1)

      expect(Marketing::QuoteMailer.new_request(SiteQuoteRequest.last).message)
        .to be_a(ActionMailer::Base::NullMail)
    end
  end
end
