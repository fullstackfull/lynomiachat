require 'rails_helper'

# The editable sales setting as an operator actually meets it: a screen reachable from the leads it governs,
# with a field that saves, a button that clears and a button that proves delivery.
#
# The first example is not really about this screen. SuperAdmin::MarketingSettingsController is hand-written,
# so it has no index route and no dashboard -- and Administrate enumerates every controller under
# `super_admin/` from the route table and raises for exactly that, inside the navigation partial that renders
# on EVERY Super Admin page. The entry in the exclusion array at
# app/views/super_admin/application/_navigation.html.erb is what stops that, and this proves it is there.
RSpec.describe 'Super Admin website sales settings', type: :request do
  let(:super_admin) { create(:super_admin) }

  # GlobalConfig keeps the value in Redis, which a rolled-back test transaction does not undo.
  before { GlobalConfig.clear_cache }

  after { GlobalConfig.clear_cache }

  def configure(address)
    InstallationConfig.find_or_initialize_by(name: Marketing::QuoteNotification::KEY).update!(value: address)
    GlobalConfig.clear_cache
  end

  # Anonymous first, before anything signs in: `sign_out` does not clear a Warden session in a request spec.
  describe 'authorization' do
    it 'refuses an anonymous visitor on the read' do
      get '/super_admin/marketing_settings'

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('sign_in')
    end

    it 'refuses an anonymous visitor on the write, and changes nothing' do
      patch '/super_admin/marketing_settings', params: { quote_notification_email: 'attacker@example.com' }

      expect(response).to have_http_status(:redirect)
      expect(Marketing::QuoteSettings.address).to be_nil
    end

    it 'refuses an anonymous visitor on the test send' do
      configure('sales@example.com')

      expect { post '/super_admin/marketing_settings/test_email' }
        .not_to change(ActionMailer::Base.deliveries, :size)

      expect(response).to have_http_status(:redirect)
    end

    # A tenant user is not an operator. The Super Admin scope is a separate Devise model, so a signed-in
    # product user has no session here at all.
    it 'refuses a signed-in product user' do
      sign_in(create(:user))

      get '/super_admin/marketing_settings'

      expect(response).to have_http_status(:redirect)
    end
  end

  context 'when signed in as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    describe 'the three states' do
      it 'says nothing is sent while no address is stored' do
        get '/super_admin/marketing_settings'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Not configured')
        expect(response.body).to include('Sales Quote Notification Email')
        expect(response.body).to include('بريد استقبال طلبات عروض الأسعار')
        expect(response.body).not_to include('translation missing')
      end

      # The owner's rule: a stored address is not a success state, and the screen must not claim delivery it
      # has not observed.
      it 'reports an address with no delivery yet as unproven rather than working' do
        configure('sales@example.com')

        get '/super_admin/marketing_settings'

        expect(response.body).to include('Configured')
        expect(response.body).to include('sales@example.com')
        expect(response.body).to include('No notification has been sent yet')
      end

      it 'reports a delivery problem with what the mail server said' do
        configure('sales@example.com')
        quote = SiteQuoteRequest.create!(name: 'Noura', email: 'noura@example.com', locale: 'en')
        # rubocop:disable Rails/SkipsModelValidations
        quote.update_columns(notification_attempted_at: Time.current,
                             notification_error: 'Net::SMTPAuthenticationError: bad credentials')
        # rubocop:enable Rails/SkipsModelValidations

        get '/super_admin/marketing_settings'

        expect(response.body).to include('Delivery problem')
        expect(response.body).to include('Net::SMTPAuthenticationError')
        expect(response.body).to include("##{quote.id}")
      end

      it 'reports the last real delivery once there has been one' do
        configure('sales@example.com')
        quote = SiteQuoteRequest.create!(name: 'Noura', email: 'noura@example.com', locale: 'en')
        quote.update_columns(notification_attempted_at: Time.current, notification_error: nil)  # rubocop:disable Rails/SkipsModelValidations

        get '/super_admin/marketing_settings'

        expect(response.body).to include('Last delivered')
        expect(response.body).to include("##{quote.id}")
      end
    end

    describe 'saving' do
      it 'stores an address and says where requests now go' do
        patch '/super_admin/marketing_settings', params: { quote_notification_email: 'sales@example.com' }

        expect(response).to redirect_to('/super_admin/marketing_settings')
        expect(Marketing::QuoteSettings.address).to eq('sales@example.com')
        expect(flash[:notice]).to include('sales@example.com')
      end

      it 'replaces an address that is already stored' do
        configure('first@example.com')

        patch '/super_admin/marketing_settings', params: { quote_notification_email: 'second@example.com' }

        expect(Marketing::QuoteSettings.address).to eq('second@example.com')
      end

      it 'refuses a malformed address with an error and keeps the stored one' do
        configure('sales@example.com')

        patch '/super_admin/marketing_settings', params: { quote_notification_email: '<script>alert(1)</script>' }

        expect(flash[:error]).to be_present
        expect(Marketing::QuoteSettings.address).to eq('sales@example.com')
      end

      it 'treats a missing parameter as empty rather than raising' do
        configure('sales@example.com')

        patch '/super_admin/marketing_settings'

        expect(response).to have_http_status(:redirect)
        expect(Marketing::QuoteSettings.address).to be_nil
      end

      it 'records the change in the audit trail' do
        expect { patch '/super_admin/marketing_settings', params: { quote_notification_email: 'sales@example.com' } }
          .to change { Custom::AuditLog.where(comment: Marketing::QuoteSettings::AUDIT_EVENT).count }.by(1)

        expect(Custom::AuditLog.where(comment: Marketing::QuoteSettings::AUDIT_EVENT).last.user_id)
          .to eq(super_admin.id)
      end
    end

    describe 'clearing' do
      it 'turns notifications off and leaves the requests listed' do
        configure('sales@example.com')
        SiteQuoteRequest.create!(name: 'Noura', email: 'noura@example.com', locale: 'en')

        post '/super_admin/marketing_settings/clear'

        expect(Marketing::QuoteSettings.address).to be_nil
        expect(Marketing::QuoteSettings.status).to eq(:unconfigured)
        expect(SiteQuoteRequest.count).to eq(1)
      end

      # Turning notifications off must not be reachable by a link somebody pastes into a chat.
      it 'is not reachable by GET' do
        get '/super_admin/marketing_settings/clear'

        expect(response).to have_http_status(:not_found)
      end
    end

    describe 'the test email' do
      it 'sends one message to the configured address and reports it' do
        configure('sales@example.com')

        expect { post '/super_admin/marketing_settings/test_email' }
          .to change(ActionMailer::Base.deliveries, :size).by(1)

        expect(ActionMailer::Base.deliveries.last.to).to eq(['sales@example.com'])
        expect(flash[:notice]).to include('sales@example.com')
      end

      it 'refuses, rather than inventing a recipient, when nothing is configured' do
        expect { post '/super_admin/marketing_settings/test_email' }
          .not_to change(ActionMailer::Base.deliveries, :size)

        expect(flash[:error]).to be_present
      end

      it 'reports a delivery failure instead of answering 500' do
        configure('sales@example.com')
        delivery = instance_double(ActionMailer::MessageDelivery)
        allow(delivery).to receive(:deliver_now).and_raise(Net::SMTPServerBusy, 'try later')
        allow(Marketing::QuoteMailer).to receive(:test_notification).and_return(delivery)

        post '/super_admin/marketing_settings/test_email'

        expect(response).to have_http_status(:redirect)
        expect(flash[:error]).to include('Net::SMTPServerBusy')
      end

      it 'is not reachable by GET' do
        get '/super_admin/marketing_settings/test_email'

        expect(response).to have_http_status(:not_found)
      end
    end

    # The owner asked for this to be reachable from the leads it governs rather than from an undocumented
    # configuration key.
    describe 'discoverability from the Quote Requests screen' do
      it 'links to the settings screen whatever the state' do
        configure('sales@example.com')

        get '/super_admin/site_quote_requests'

        expect(response.body).to include('/super_admin/marketing_settings')
        expect(response.body).to include('Website Sales Settings')
      end

      it 'warns on the list when no address is configured' do
        get '/super_admin/site_quote_requests'

        expect(response.body).to include('No quote notification address is configured')
        expect(response.body).to include('/super_admin/marketing_settings')
      end

      it 'warns on the list when the last notification failed' do
        configure('sales@example.com')
        quote = SiteQuoteRequest.create!(name: 'Noura', email: 'noura@example.com', locale: 'en')
        quote.update_columns(notification_attempted_at: Time.current, notification_error: 'Net::SMTPError: x')  # rubocop:disable Rails/SkipsModelValidations

        get '/super_admin/site_quote_requests'

        expect(response.body).to include('could not be delivered')
      end
    end

    # The whole point of the screen: a visitor submitting the form after an operator changes the address is
    # emailed to the new one, with nothing restarted and nothing redeployed.
    it 'sends the next quote request to the newly saved address' do
      # The public page is a CMS row, so it has to exist for the form to be reachable at all.
      Marketing::ContentSeeder.apply!
      patch '/super_admin/marketing_settings', params: { quote_notification_email: 'new-sales@example.com' }

      perform_enqueued_jobs do
        post '/en/pricing/request', params: { site_quote_request: { name: 'Noura', email: 'noura@example.com' } }
      end

      expect(response).to redirect_to('/en/pricing?sent=1')
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).to include('new-sales@example.com')
    end
  end
end
