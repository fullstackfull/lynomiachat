require 'rails_helper'

RSpec.describe 'Super Admin Operations Center', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }

  def signal(**attributes)
    defaults = { source: 'email_channel', signal: 'authentication_failed', severity: :critical,
                 account: account, subject: inbox, first_seen_at: 1.hour.ago, last_seen_at: 5.minutes.ago }
    Operations::Signal.create!(defaults.merge(attributes))
  end

  describe 'the Super Admin boundary' do
    it 'redirects an unauthenticated caller away from every page' do
      ['/super_admin/operations', '/super_admin/operations/accounts', '/super_admin/operations/issues'].each do |path|
        get path
        expect(response).to have_http_status(:redirect)
      end
    end

    # The decisive check: a tenant administrator is not an operator. There is no session that makes an account
    # user into a super admin, so these pages are unreachable for them whatever their role or custom role.
    it 'does not let a tenant administrator or agent in' do
      [administrator, agent].each do |user|
        sign_in(user, scope: :user)
        get '/super_admin/operations'
        expect(response).to have_http_status(:redirect)
        sign_out(user)
      end
    end

    it 'refuses the one mutation to an unauthenticated caller' do
      target = signal
      post '/super_admin/operations/open_case', params: { signal_id: target.id }

      expect(response).to have_http_status(:redirect)
      expect(target.reload.support_ticket_id).to be_nil
    end
  end

  context 'when signed in as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    describe 'GET /super_admin/operations' do
      it 'renders the console with the platform probes and the product areas' do
        get '/super_admin/operations'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Operations')
        expect(response.body).to include('Platform')
        expect(response.body).to include('Product areas')
      end

      # The rule the whole console exists to keep: silence is not green.
      it 'says an area with no source is unknown rather than healthy' do
        get '/super_admin/operations'

        expect(response.body).to include('Unknown')
        expect(response.body).to include('No WhatsApp inbox exists')
      end

      it 'says so when nothing has been recorded, instead of implying health' do
        get '/super_admin/operations'

        expect(response.body).to include('Nothing has been recorded')
      end

      it 'shows a recorded issue in the feed' do
        signal(reason: 'The mail server refused the credentials')
        get '/super_admin/operations'

        expect(response.body).to include('Email channel')
        expect(response.body).to include('The mail server refused the credentials')
      end
    end

    describe 'GET /super_admin/operations/accounts' do
      it 'lists accounts with component statuses and no score' do
        account
        get '/super_admin/operations/accounts'

        expect(response).to have_http_status(:success)
        expect(response.body).to include(account.name)
        expect(response.body).to include('There is no health score')
      end
    end

    describe 'GET /super_admin/operations/issues' do
      it 'filters open, resolved and all' do
        open_one = signal
        resolved_one = signal(signal: 'connection_failed', resolved_at: 1.minute.ago)

        get '/super_admin/operations/issues', params: { status: 'open' }
        expect(response.body).to include('Authentication failed')
        expect(response.body).not_to include('Connection failed')

        get '/super_admin/operations/issues', params: { status: 'resolved' }
        expect(response.body).to include('Connection failed')

        get '/super_admin/operations/issues', params: { status: 'all' }
        expect(response.body).to include('Authentication failed').and include('Connection failed')
        expect([open_one, resolved_one].map(&:persisted?)).to all(be(true))
      end
    end

    describe 'POST /super_admin/operations/open_case' do
      it 'opens an operational case with the right shape' do
        target = signal(reason: 'The mail server refused the credentials')

        expect { post '/super_admin/operations/open_case', params: { signal_id: target.id } }
          .to change(Support::Ticket, :count).by(1)

        ticket = Support::Ticket.last
        expect(ticket).to have_attributes(account_id: account.id, category: 'operational', priority: 'urgent',
                                          inbox_id: inbox.id, source_type: 'Operations::Signal',
                                          source_id: target.id)
      end

      it 'links the case back to the issue, with no borrowed creator' do
        target = signal
        post '/super_admin/operations/open_case', params: { signal_id: target.id }

        ticket = Support::Ticket.last
        expect(target.reload.support_ticket_id).to eq(ticket.id)
        # An operator is not an account user, so the case has no creator rather than somebody else's name.
        expect(ticket.created_by_id).to be_nil
      end

      # The dedup rule: a refresh must not generate case spam.
      it 'surfaces the existing case instead of opening a second' do
        target = signal
        post '/super_admin/operations/open_case', params: { signal_id: target.id }
        reference = Support::Ticket.last.reference

        expect { post '/super_admin/operations/open_case', params: { signal_id: target.id } }
          .not_to change(Support::Ticket, :count)
        follow_redirect!
        expect(response.body).to include("#{reference} already covers this issue")
      end

      # A closed case is not worth pointing at: the issue is open again, so a new case is the honest record.
      it 'opens a new case when the linked one is already closed' do
        target = signal
        post '/super_admin/operations/open_case', params: { signal_id: target.id }
        Support::Ticket.last.update!(status: :closed)

        expect { post '/super_admin/operations/open_case', params: { signal_id: target.id } }
          .to change(Support::Ticket, :count).by(1)
      end

      # support_tickets.account_id is NOT NULL because a case belongs to an account, and a queue backlog belongs
      # to the installation. The console says so rather than inventing a synthetic operations account.
      it 'refuses an installation-wide issue with a reason' do
        target = Operations::Signal.create!(source: 'queue', signal: 'no_workers', severity: :critical,
                                            first_seen_at: 1.hour.ago, last_seen_at: 1.minute.ago)

        expect { post '/super_admin/operations/open_case', params: { signal_id: target.id } }
          .not_to change(Support::Ticket, :count)
        follow_redirect!
        expect(response.body).to include('installation wide')
      end

      it 'says so when the issue no longer exists' do
        post '/super_admin/operations/open_case', params: { signal_id: 0 }
        follow_redirect!

        expect(response.body).to include('no longer exists')
      end
    end

    describe 'what the pages never render' do
      it 'carries no credential, token or provider payload' do
        signal(reason: 'The mail server refused the credentials', detail: { code: 'Net::IMAP::NoResponseError' })
        inbox.channel.update!(provider_config: { 'api_key' => 'super-secret-value' }) if
          inbox.channel.respond_to?(:provider_config)

        ['/super_admin/operations', '/super_admin/operations/accounts', '/super_admin/operations/issues'].each do |path|
          get path
          expect(response.body).not_to include('super-secret-value')
          expect(response.body).not_to match(/imap_password|provider_config|access_token/)
        end
      end
    end
  end
end
