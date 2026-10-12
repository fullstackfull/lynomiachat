require 'rails_helper'

# P9.8: the three claims P9 makes about itself that are only worth as much as a test that tries to break them.
#
#   1. No surface P9 adds ever renders a credential. Proved against records that really hold one -- a WhatsApp
#      cloud channel's api_key, an IMAP mailbox's password, a commerce store's OAuth tokens -- rather than
#      against a channel type that has no credential to leak, which would pass while proving nothing.
#   2. A client cannot write the fields the server owns, however it spells them.
#   3. A case's polymorphic `source` cannot point at an arbitrary class.
RSpec.describe 'P9 hardening', type: :request do
  include_context 'with commerce encryption'

  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before { account.enable_features!('lynomia_support_tickets') }

  describe 'the Operations Center never renders a credential' do
    # Each value is planted on a record the console really reads, and each is distinctive enough that a
    # substring match cannot pass by accident.
    let(:secrets) do
      { whatsapp_api_key: 'p9-leak-whatsapp-api-key',
        imap_password: 'p9-leak-imap-password',
        smtp_password: 'p9-leak-smtp-password',
        salla_access: 'p9-leak-salla-access-token',
        salla_refresh: 'p9-leak-salla-refresh-token' }
    end

    let!(:whatsapp_inbox) do
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                          validate_provider_config: false)
      channel.update!(provider_config: channel.provider_config.merge('api_key' => secrets[:whatsapp_api_key]))
      channel.inbox
    end

    let!(:email_inbox) do
      channel = create(:channel_email, :imap_email, account: account)
      channel.update!(imap_password: secrets[:imap_password], smtp_password: secrets[:smtp_password],
                      smtp_enabled: true, smtp_address: 'smtp.example.com', smtp_port: 587,
                      smtp_login: 'care@example.com')
      channel.inbox
    end

    let!(:store) do
      create(:commerce_store, :salla, account: account,
                                      credentials: { 'access_token' => secrets[:salla_access],
                                                     'refresh_token' => secrets[:salla_refresh],
                                                     'token_type' => 'bearer' })
    end

    before do
      # One open signal per source, each recorded the way the product records it: through the one writer, with a
      # provider's own error prose as the reason. If the allow-list or the reason bound leaked, it would show here.
      email_recorder = Operations::SignalRecorder.new(source: :email_channel, account: account, subject: email_inbox)
      email_recorder.record(
        :authentication_failed, severity: :critical,
                                reason: "LOGIN failed for care@example.com with #{secrets[:imap_password]}",
                                detail: { code: 'Net::IMAP::NoResponseError', imap_password: secrets[:imap_password] }
      )

      whatsapp_recorder = Operations::SignalRecorder.new(source: :whatsapp_channel, account: account,
                                                         subject: whatsapp_inbox)
      whatsapp_recorder.record(
        :delivery_failed, severity: :warning,
                          reason: "Meta rejected the send with api_key=#{secrets[:whatsapp_api_key]}",
                          detail: { error_code: '131049', api_key: secrets[:whatsapp_api_key] }
      )

      store_recorder = Operations::SignalRecorder.new(source: :commerce_store, account: account, subject: store)
      store_recorder.record(
        :sync_failed, severity: :warning,
                      reason: "Salla returned 401 for token #{secrets[:salla_access]}",
                      detail: { store_id: store.id, access_token: secrets[:salla_access] }
      )
    end

    it 'plants values that really are stored, so the assertions below have something to find' do
      expect(whatsapp_inbox.channel.reload.provider_config['api_key']).to eq(secrets[:whatsapp_api_key])
      expect(email_inbox.channel.reload.imap_password).to eq(secrets[:imap_password])
      expect(store.reload.credentials['access_token']).to eq(secrets[:salla_access])
    end

    it 'keeps every planted secret out of the signal rows themselves' do
      rows = Operations::Signal.all.map { |s| [s.reason, s.detail.to_json].join(' ') }.join(' ')

      secrets.each_value { |secret| expect(rows).not_to include(secret) }
      expect(Operations::Signal.pluck(:detail).flat_map(&:keys).uniq)
        .to all(be_in(Operations::SignalRecorder::DETAIL_KEYS))
    end

    it 'keeps every planted secret out of all three console pages' do
      sign_in(super_admin, scope: :super_admin)

      ['/super_admin/operations', '/super_admin/operations/accounts', '/super_admin/operations/issues'].each do |path|
        get path

        expect(response).to have_http_status(:success)
        secrets.each_value do |secret|
          expect(response.body).not_to include(secret), "#{path} leaked a credential"
        end
        expect(response.body).not_to match(/imap_password|smtp_password|provider_config|access_token|refresh_token/)
      end
    end

    it 'keeps every planted secret out of a case opened from an issue' do
      sign_in(super_admin, scope: :super_admin)
      issue = Operations::Signal.find_by(source: 'email_channel')

      post '/super_admin/operations/open_case', params: { signal_id: issue.id }

      ticket = Support::Ticket.last
      expect(ticket).to be_present
      body = [ticket.title, ticket.description, ticket.events.map(&:body).join(' ')].join(' ')
      secrets.each_value { |secret| expect(body).not_to include(secret) }
    end
  end

  describe 'the fields a client may not write' do
    let(:other_account) { create(:account) }
    let(:path) { "/api/v1/accounts/#{account.id}/support/tickets" }

    it 'ignores every server-owned field on create, however it is spelled' do
      post path, params: { ticket: {
        title: 'Mass assignment', account_id: other_account.id, reference_number: 9999,
        created_by_id: create(:user, account: other_account, role: :administrator).id,
        source_type: 'User', source_id: 1,
        first_response_due_at: 1.day.from_now, resolution_due_at: 1.day.from_now,
        first_responded_at: Time.current, first_response_breached_at: Time.current,
        resolution_breached_at: Time.current, sla_paused_at: Time.current, sla_paused_seconds: 9999,
        resolved_at: Time.current, closed_at: Time.current, last_activity_at: 10.years.ago
      } }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:created)
      ticket = Support::Ticket.find(response.parsed_body['payload']['id'])
      expect(ticket.slice(:account_id, :reference_number, :created_by_id, :sla_paused_seconds).values)
        .to eq([account.id, 1, administrator.id, 0])
      expect([ticket.source_type, ticket.source_id,
              ticket.first_response_due_at, ticket.resolution_due_at, ticket.first_responded_at,
              ticket.first_response_breached_at, ticket.resolution_breached_at, ticket.sla_paused_at,
              ticket.resolved_at, ticket.closed_at]).to all(be_nil)
      expect(ticket.last_activity_at).to be > 1.minute.ago
    end

    it 'ignores every server-owned field on update too' do
      ticket = create(:support_ticket, account: account)

      patch "#{path}/#{ticket.id}", params: { ticket: {
        title: 'Renamed', account_id: other_account.id, reference_number: 4242,
        resolution_breached_at: Time.current, sla_paused_seconds: 7, resolved_at: Time.current
      } }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      ticket.reload
      expect(ticket.title).to eq('Renamed')
      expect(ticket.account_id).to eq(account.id)
      expect(ticket.reference_number).to eq(1)
      expect([ticket.resolution_breached_at, ticket.resolved_at]).to all(be_nil)
      expect(ticket.sla_paused_seconds).to eq(0)
    end

    it 'will not let a note be attributed to somebody else' do
      ticket = create(:support_ticket, account: account)
      other = create(:user, account: account, role: :agent)

      post "#{path}/#{ticket.id}/events",
           params: { event: { body: 'Called the customer', user_id: other.id, event_type: 'status_changed' } },
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:created)
      event = Support::TicketEvent.last
      expect(event.user_id).to eq(administrator.id)
      expect(event.event_type).to eq('note')
    end
  end

  describe 'the polymorphic source' do
    it 'accepts only the classes on the allow-list' do
      ticket = build(:support_ticket, account: account, source_type: 'User', source_id: administrator.id)

      expect(ticket).not_to be_valid
      expect(ticket.errors[:source_type]).to be_present
    end

    it 'accepts an Operations::Signal, which is the one thing that opens a case on its own' do
      signal = Operations::Signal.create!(source: 'queue', signal: 'backlog', severity: :warning,
                                          first_seen_at: 1.hour.ago, last_seen_at: 1.minute.ago)
      ticket = build(:support_ticket, account: account, source: signal)

      expect(ticket).to be_valid
    end
  end

  describe 'the audit trail' do
    it 'records a case without copying its description into the audit row' do
      ticket = nil
      Audited.audit_class.as_user(administrator) do
        ticket = create(:support_ticket, account: account, description: 'the customer dictated their card number')
      end

      audit = Audited::Audit.find_by(auditable_type: 'Support::Ticket', auditable_id: ticket.id)
      expect(audit).to be_present
      expect(audit.audited_changes.keys).not_to include('description')
      expect(audit.audited_changes.to_json).not_to include('card number')
    end
  end
end
