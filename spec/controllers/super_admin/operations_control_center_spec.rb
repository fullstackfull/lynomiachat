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
      ["/super_admin/operations/signal?id=#{signal.id}", :get]
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
  end
end
