require 'rails_helper'

# Operations Control Center V2: the authorization boundary and the operator actions
# (docs/product-refinement/07-operations-control-center-v2.md, docs/product-refinement/08-security-performance.md).
#
# Operations is privileged and installation-wide. The brief's requirement for every new Super Admin mutation is
# asserted here in full: unauthenticated, tenant administrator, tenant agent, Super Admin, an invalid object,
# idempotency, and the audit trail. Plus the one that matters most on this surface -- no secret in the HTML.
RSpec.describe 'Super Admin Operations Control Center', type: :request do
  let(:super_admin) { create(:super_admin, name: 'Hisham Operator') }
  let(:account) { create(:account, name: 'Hisham Test') }
  let(:inbox) { create(:inbox, account: account) }
  let(:signal) do
    Operations::SignalRecorder.new(source: :email_channel, account: account, subject: inbox)
                              .record(:authentication_failed, severity: :critical, reason: 'IMAP LOGIN refused')
  end

  # Every V2 endpoint, so a new one cannot be added without appearing in the boundary tests below.
  let(:reads) do
    [
      ['/super_admin/operations/queue', :get],
      ["/super_admin/operations/signal?id=#{signal.id}", :get],
      ["/super_admin/operations/account?id=#{account.id}", :get],
      ['/super_admin/operations/channels', :get],
      ['/super_admin/operations/commerce', :get]
    ]
  end
  let(:mutations) do
    [
      ['/super_admin/operations/acknowledge_signal', :post],
      ['/super_admin/operations/suppress_signal', :post],
      ['/super_admin/operations/resume_signal', :post]
    ]
  end

  describe 'the authorization boundary' do
    it 'refuses an unauthenticated visitor on every endpoint' do
      (reads + mutations).each do |path, verb|
        process(verb, path, params: { id: signal.id })

        expect(response).to have_http_status(:redirect), "#{verb.upcase} #{path} did not redirect"
        expect(response.location).to include('super_admin/sign_in')
      end
    end

    it 'refuses a tenant ADMINISTRATOR on every endpoint' do
      admin = create(:user, account: account, role: :administrator)
      sign_in(admin, scope: :user)

      (reads + mutations).each do |path, verb|
        process(verb, path, params: { id: signal.id })

        expect(response).to have_http_status(:redirect), "#{verb.upcase} #{path} let a tenant admin through"
        expect(response.location).to include('super_admin/sign_in')
      end
    end

    it 'refuses a tenant AGENT on every endpoint' do
      agent = create(:user, account: account, role: :agent)
      sign_in(agent, scope: :user)

      (reads + mutations).each do |path, verb|
        process(verb, path, params: { id: signal.id })

        expect(response).to have_http_status(:redirect), "#{verb.upcase} #{path} let a tenant agent through"
        expect(response.location).to include('super_admin/sign_in')
      end
    end

    # The negative tests above only mean something if the positive one passes.
    it 'admits a Super Admin' do
      sign_in(super_admin, scope: :super_admin)

      get '/super_admin/operations/queue'

      expect(response).to have_http_status(:success)
    end

    # A tenant admin who is ALSO signed in as a super admin in the same browser is a real situation: Warden
    # keys both Devise scopes into one cookie and the Super Admin nav links straight to the agent dashboard.
    # The operator identity must be the one that acts, and the tenant one must not grant anything.
    it 'acts as the super admin, not the co-resident tenant session' do
      tenant_admin = create(:user, account: account, role: :administrator)
      sign_in(tenant_admin, scope: :user)
      sign_in(super_admin, scope: :super_admin)

      post '/super_admin/operations/acknowledge_signal', params: { id: signal.id }

      expect(signal.reload.acknowledged_by_id).to eq(super_admin.id)
      expect(signal.events.last.actor_id).to eq(super_admin.id)
      expect(Custom::AuditLog.where(comment: 'operations.signal.acknowledged').last.user_id).to eq(super_admin.id)
    end
  end

  context 'when signed in as a Super Admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    describe 'the queue' do
      it 'lists a signal that needs action and links to it' do
        signal

        get '/super_admin/operations/queue'

        expect(response.body).to include('Attention queue', 'Authentication failed', 'Hisham Test')
        expect(response.body).to include("/super_admin/operations/signal?id=#{signal.id}")
      end

      it 'does not pretend an empty needs-action queue means nothing is wrong' do
        get '/super_admin/operations/queue'

        expect(response.body).to include('That is not the same as nothing being wrong')
      end
    end

    describe 'the signal detail' do
      it 'shows what happened, who is affected and the timeline' do
        get "/super_admin/operations/signal?id=#{signal.id}"

        expect(response.body).to include('What happened', 'Who is affected', 'Timeline', 'IMAP LOGIN refused')
      end

      it 'redirects with a message for an id that does not exist' do
        get '/super_admin/operations/signal?id=999999'

        expect(response).to redirect_to('/super_admin/operations/queue')
        expect(flash[:alert]).to eq('That operational issue no longer exists.')
      end
    end

    describe 'account 360' do
      it 'shows the account in one place, with usage against its plan' do
        get "/super_admin/operations/account?id=#{account.id}"

        expect(response.body).to include('Commercial', 'Usage against the plan', 'Channels', 'Commerce stores',
                                         'Recent operator activity', 'Hisham Test')
      end

      # The console's standing rule: never pretend stored data is live.
      it 'says when it was read and that no provider was contacted' do
        get "/super_admin/operations/account?id=#{account.id}"

        expect(response.body).to include('No provider was contacted')
      end

      it 'redirects with a message for an account that does not exist' do
        get '/super_admin/operations/account?id=999999'

        expect(response).to redirect_to('/super_admin/operations/accounts')
        expect(flash[:alert]).to eq('That account no longer exists.')
      end

      # The two honesty rules on one page: an API inbox has no provider to be connected to, and a store nobody
      # has called has no observation either way. Neither may render as healthy.
      describe 'with an inbox and a store' do
        include_context 'with commerce encryption'

        it 'reports both as unknown rather than green' do
          create(:channel_api, account: account)
          create(:commerce_store, account: account, name: 'Hisham Store')

          get "/super_admin/operations/account?id=#{account.id}"

          expect(response.body).to include('This channel has no external provider to stay connected to')
          expect(response.body).to include('Hisham Store')
          expect(response.body).to include('No provider request recorded')
          expect(response.body).to include('No webhook received yet')
        end
      end
    end

    describe 'acknowledge' do
      it 'records the operator and audits it' do
        post '/super_admin/operations/acknowledge_signal', params: { id: signal.id, reason: 'On it' }

        expect(response).to redirect_to("/super_admin/operations/signal?id=#{signal.id}")
        expect(signal.reload).to be_acknowledged
        expect(Custom::AuditLog.where(comment: 'operations.signal.acknowledged').count).to eq(1)
      end

      it 'is idempotent and says so rather than erroring' do
        post '/super_admin/operations/acknowledge_signal', params: { id: signal.id }
        post '/super_admin/operations/acknowledge_signal', params: { id: signal.id }

        expect(flash[:notice]).to eq('Already in that state, so nothing changed.')
        expect(Custom::AuditLog.where(comment: 'operations.signal.acknowledged').count).to eq(1)
      end

      it 'redirects with a message for an invalid object' do
        post '/super_admin/operations/acknowledge_signal', params: { id: 999_999 }

        expect(response).to redirect_to('/super_admin/operations/queue')
        expect(flash[:alert]).to eq('That operational issue no longer exists.')
      end
    end

    describe 'suppress' do
      it 'requires a reason, and refuses with the reason shown to the operator' do
        post '/super_admin/operations/suppress_signal',
             params: { id: signal.id, suppressed_until: 2.hours.from_now.iso8601, reason: '' }

        expect(flash[:alert]).to match(/reason is required/)
        expect(signal.reload.suppressed_until).to be_nil
      end

      # The exact value the merge gate found answering 500: a thirteenth month from the datetime-local field.
      it 'answers a date-shaped deadline that is not a real date with the controlled refusal' do
        post '/super_admin/operations/suppress_signal',
             params: { id: signal.id, suppressed_until: '2026-13-45T99:99:99', reason: 'Known Meta incident' }

        expect(response).to redirect_to("/super_admin/operations/signal?id=#{signal.id}")
        expect(flash[:alert]).to match(/real date and time/)
        expect(signal.reload).to have_attributes(suppressed_until: nil, suppression_reason: nil)
        expect(signal.events).to be_empty
        expect(Custom::AuditLog.where(auditable: signal, comment: 'operations.signal.suppressed')).to be_empty
      end

      it 'refuses an effectively permanent suppression' do
        post '/super_admin/operations/suppress_signal',
             params: { id: signal.id, suppressed_until: 1.year.from_now.iso8601, reason: 'Forever please' }

        expect(flash[:alert]).to match(/may not exceed/)
        expect(signal.reload.suppressed_until).to be_nil
      end

      it 'suppresses with a bounded deadline and a reason' do
        post '/super_admin/operations/suppress_signal',
             params: { id: signal.id, suppressed_until: 6.hours.from_now.iso8601, reason: 'Known Meta incident' }

        expect(signal.reload).to be_suppressed
        expect(signal.suppression_reason).to eq('Known Meta incident')
      end
    end

    describe 'resume' do
      it 'returns a handled signal to the queue' do
        post '/super_admin/operations/acknowledge_signal', params: { id: signal.id }
        post '/super_admin/operations/resume_signal', params: { id: signal.id }

        expect(signal.reload).not_to be_acknowledged
        expect(Operations::Signal.attention_queue).to include(signal)
      end
    end

    # The channel matrix (docs/product-refinement/10-operations-ui.md §channels).
    describe 'GET /super_admin/operations/channels' do
      it 'names the channel types this installation reports nothing about' do
        create(:channel_telegram, account: account)

        get '/super_admin/operations/channels'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('No recent error is not')
        expect(response.body).to include('Nothing in this installation reports whether this connection still works')
      end
    end

    # Commerce operations (docs/product-refinement/09-commerce-operations.md).
    describe 'GET /super_admin/operations/commerce' do
      include_context 'with commerce encryption'

      let!(:store) { create(:commerce_store, account: account, name: 'Hisham Store') }

      it 'separates what the status says from what the provider last did' do
        get '/super_admin/operations/commerce?view=all'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Hisham Store')
        expect(response.body).to include('No provider request has been recorded')
      end

      it 'shows a failing store with its classified error code and nothing else' do
        Commerce::StoreHealthRecorder.api_failure(store, Commerce::Error.new('AUTH_INVALID', reason: 'tokens_rejected'))

        get '/super_admin/operations/commerce?view=failing'

        expect(response.body).to include('AUTH_INVALID', 'tokens_rejected', '1 failure in a row')
      end

      it 'never renders a store credential' do
        store.update!(credentials: { 'consumer_key' => 'ck_visible_secret', 'consumer_secret' => 'cs_visible_secret' })

        get '/super_admin/operations/commerce?view=all'

        expect(response.body).not_to include('ck_visible_secret')
        expect(response.body).not_to include('cs_visible_secret')
      end
    end

    # The console renders a signal's reason and detail, both of which originate in provider prose. The recorder
    # redacts on the way in; this asserts nothing gets past it onto the page.
    describe 'secrets' do
      let(:inbox_with_password) do
        channel = create(:channel_email, account: account, imap_password: 'hunter2-the-imap-password', imap_enabled: true)
        channel.inbox
      end

      it 'renders no credential on the queue or the detail page' do
        leaky = Operations::SignalRecorder.new(source: :email_channel, account: account, subject: inbox_with_password)
                                          .record(:authentication_failed, severity: :critical,
                                                                          reason: 'LOGIN failed for password=hunter2-the-imap-password')

        get '/super_admin/operations/queue'
        expect(response.body).not_to include('hunter2-the-imap-password')

        get "/super_admin/operations/signal?id=#{leaky.id}"
        expect(response.body).not_to include('hunter2-the-imap-password')
        expect(response.body).to include('[redacted]')
      end
    end

    # Two defects the existing examples could not see, because asserting a 200 and the absence of secrets
    # passes just as well on a page that silently renders neither its title nor its pagination.
    describe 'what the operator can actually see on the page' do
      it 'renders the page title the layout asks for' do
        get '/super_admin/operations/queue'

        # `content_for(:page_title)` was a key nothing reads: layouts/super_admin/application.html.erb
        # renders `content_for(:title)`, so every V2 page was titled " - Lynomia Chat".
        expect(response.body).to include('<title>')
        expect(response.body).to match(/<title>\s*Operations — Queue/)
      end

      it 'renders working pagination controls when there is more than one page' do
        # Both must exist BEFORE the request: `signal` is a lazy let, and a queue holding one row has one
        # page, which renders no pagination however the helper is called.
        second = Operations::SignalRecorder.new(source: :whatsapp_channel, account: account, subject: inbox)
                                           .record(:reauthorization_required, severity: :warning,
                                                                              reason: 'Token expired')
        expect([signal.id, second.id].uniq.length).to eq(2)

        get '/super_admin/operations/queue', params: { per_page: 1 }

        # `paginate …, theme: 'administrate' rescue nil` named a theme with no app/views/kaminari
        # directory behind it, so the call raised and the rescue beside it swallowed the raise --
        # pagination was absent from every Operations page and nothing failed.
        expect(response.body).to include('pagination')
        expect(response.body).to include('page=2')
      end
    end
  end
end
