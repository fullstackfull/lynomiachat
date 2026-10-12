require 'rails_helper'

# PART P: a credential the server encrypts at rest must not be sent to the browser
# (docs/p10/07-security-performance.md §secrets). Three were:
# `channel_email.imap_password`, `channel_email.smtp_password` and `channel_twilio_sms.auth_token`, each with
# `encrypts` on the model and each serialized in full to any administrator.
RSpec.describe 'Channel credential exposure', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'an email inbox' do
    let(:channel) do
      create(:channel_email, account: account, imap_enabled: true, imap_address: 'imap.example.com',
                             imap_login: 'dana@example.com', imap_password: 'imap-secret',
                             smtp_enabled: true, smtp_address: 'smtp.example.com',
                             smtp_login: 'dana@example.com', smtp_password: 'smtp-secret')
    end
    let(:inbox) { create(:inbox, channel: channel, account: account) }

    def show
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: admin.create_new_auth_token, as: :json
      response
    end

    it 'reports the passwords as configured without sending either of them' do
      body = show.parsed_body

      expect(body).not_to have_key('imap_password')
      expect(body).not_to have_key('smtp_password')
      expect(body['imap_password_configured']).to be(true)
      expect(body['smtp_password_configured']).to be(true)
    end

    it 'does not leak the values anywhere else in the payload' do
      expect(show.body).not_to include('imap-secret', 'smtp-secret')
    end

    it 'says the password is not configured when there is none' do
      channel.update!(imap_password: '', smtp_password: '')

      expect(show.parsed_body['imap_password_configured']).to be(false)
    end

    # Without this the masking would be a data-loss bug: the settings form sends its whole field set on every
    # save, and the password field now starts empty.
    it 'keeps the stored password when the save leaves the field blank' do
      allow(Net::IMAP).to receive(:new).and_return(instance_double(Net::IMAP, disconnected?: false,
                                                                              login: true, disconnect: true))

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            headers: admin.create_new_auth_token, as: :json,
            params: { channel: { imap_enabled: true, imap_address: 'imap.changed.example.com',
                                 imap_port: 993, imap_login: 'dana@example.com', imap_password: '',
                                 imap_authentication: 'login' } }

      expect(response).to have_http_status(:success)
      expect(channel.reload.imap_address).to eq('imap.changed.example.com')
      expect(channel.reload.imap_password).to eq('imap-secret')
    end

    it 'replaces the stored password when a new one is typed' do
      allow(Net::IMAP).to receive(:new).and_return(instance_double(Net::IMAP, disconnected?: false,
                                                                              login: true, disconnect: true))

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            headers: admin.create_new_auth_token, as: :json,
            params: { channel: { imap_enabled: true, imap_address: 'imap.example.com', imap_port: 993,
                                 imap_login: 'dana@example.com', imap_password: 'rotated',
                                 imap_authentication: 'login' } }

      expect(response).to have_http_status(:success)
      expect(channel.reload.imap_password).to eq('rotated')
    end

    it 'leaves a secret the save did not mention alone' do
      allow(Net::IMAP).to receive(:new).and_return(instance_double(Net::IMAP, disconnected?: false,
                                                                              login: true, disconnect: true))

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            headers: admin.create_new_auth_token, as: :json,
            params: { channel: { imap_enabled: true, imap_address: 'imap.example.com', imap_port: 993,
                                 imap_login: 'dana@example.com', imap_password: 'rotated',
                                 imap_authentication: 'login' } }

      expect(channel.reload.smtp_password).to eq('smtp-secret')
    end
  end

  describe 'a Twilio inbox' do
    let(:channel) { create(:channel_twilio_sms, account: account, auth_token: 'twilio-secret') }

    it 'reports the auth token as configured without sending it, and keeps the identifiers' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}",
          headers: admin.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body).not_to have_key('auth_token')
      expect(body['auth_token_configured']).to be(true)
      expect(body['account_sid']).to be_present
      expect(response.body).not_to include('twilio-secret')
    end
  end
end
