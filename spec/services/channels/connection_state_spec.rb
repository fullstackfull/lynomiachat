require 'rails_helper'

# One honest answer per inbox (docs/p10/06-channel-lifecycle-health.md). The point of each example is that the
# status comes from a fact the repository holds -- a Redis latch, a column, a stored provider reading -- and that
# silence renders `unknown` rather than green.
RSpec.describe Channels::ConnectionState do
  let(:account) { create(:account) }

  def state_for(inbox)
    described_class.new(inbox).call
  end

  # Straight onto the row. Instagram validates its access token's presence and the token is write-only once
  # loaded, so a plain `update!` on a reloaded channel fails for a reason that has nothing to do with expiry.
  def expire_token(channel, at)
    channel.expires_at = at
    channel.save!(validate: false)
  end

  def store_health(channel, attributes)
    attributes.each { |name, value| channel[name] = value }
    channel.save!(validate: false)
  end

  describe 'a channel with no external provider' do
    it 'is unknown with nothing recorded, for the web widget' do
      state = state_for(create(:inbox, account: account, channel: create(:channel_widget, account: account)))

      expect([state.status, state.source_class]).to eq([Operations::Health::UNKNOWN, 'absent'])
      expect(state.reason).to include('no external provider')
    end

    it 'is unknown for an API inbox' do
      state = state_for(create(:inbox, account: account, channel: create(:channel_api, account: account)))

      expect(state.status).to eq(Operations::Health::UNKNOWN)
    end
  end

  describe 'a provider-backed channel that nothing reports on' do
    it 'says so instead of saying it is fine' do
      state = state_for(create(:channel_telegram, account: account).inbox)

      expect([state.status, state.source_class]).to eq([Operations::Health::UNKNOWN, 'absent'])
      expect(state.reason).to include('Nothing in this installation reports')
    end
  end

  describe 'the reauthorization latch' do
    let(:inbox) { create(:channel_instagram, account: account).inbox }

    it 'is critical, and names how many errors were counted' do
      inbox.channel.authorization_error!
      inbox.channel.prompt_reauthorization!

      state = state_for(inbox)

      expect(state.status).to eq(Operations::Health::CRITICAL)
      expect(state.reason).to include('needs to be reconnected')
      expect(state.detail[:attempts]).to eq(1)
    end

    # Email's threshold is 10, so a single error is counted without latching -- which is exactly the state
    # nothing used to report, on either the channel or the inbox.
    it 'is a warning while errors are counted but the latch has not tripped' do
      email_inbox = create(:channel_email, account: account).inbox
      email_inbox.channel.authorization_error!

      state = state_for(email_inbox)

      expect(state.status).to eq(Operations::Health::WARNING)
      expect(state.detail[:attempts]).to eq(1)
    end

    it 'is healthy when nothing is reported against it' do
      state = state_for(inbox)

      expect([state.status, state.source_class]).to eq([Operations::Health::HEALTHY, 'probed'])
      expect(state.detail[:checked]).to include('reauth_latch')
    end
  end

  describe 'a stored token expiry' do
    let(:inbox) { create(:channel_instagram, account: account).inbox }

    it 'is critical once the authorization has expired' do
      expire_token(inbox.channel, 1.day.ago)

      state = state_for(inbox.reload)

      expect(state.status).to eq(Operations::Health::CRITICAL)
      expect(state.reason).to include('expired')
      expect(state.detail[:expired_at]).to be_present
    end

    # The ten-day window is Instagram's own, from its refresh service.
    it 'is a warning inside the window the refresh service uses' do
      expire_token(inbox.channel, 5.days.from_now)

      state = state_for(inbox.reload)

      expect(state.status).to eq(Operations::Health::WARNING)
      expect(state.reason).to include('expires soon')
    end

    it 'reads the refresh token for TikTok, whose access token lasts a day and renews itself' do
      tiktok = create(:channel_tiktok, account: account, expires_at: 1.minute.from_now,
                                       refresh_token_expires_at: 2.days.ago)

      state = state_for(tiktok.inbox)

      expect(state.status).to eq(Operations::Health::CRITICAL)
    end
  end

  describe 'WhatsApp' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                sync_templates: false, validate_provider_config: false)
    end

    it 'is critical when no credentials are configured' do
      store_health(channel, provider_config: {})

      state = state_for(channel.inbox.reload)

      expect(state.status).to eq(Operations::Health::CRITICAL)
      expect(state.reason).to include('No provider credentials')
    end

    it 'surfaces the risky reading the provider health sync stored' do
      store_health(channel, phone_number_health: { 'status' => 'RESTRICTED', 'quality_rating' => 'RED' },
                            phone_number_health_checked_at: Time.current)

      state = state_for(channel.inbox.reload)

      expect(state.status).to eq(Operations::Health::WARNING)
      expect(state.detail).to include(status: 'RESTRICTED', quality_rating: 'RED')
    end

    it 'reports a failed health check without quoting the provider message' do
      store_health(channel, phone_number_health_error: 'GET https://graph.facebook.com/... token=SECRET failed',
                            phone_number_health_checked_at: Time.current)

      state = state_for(channel.inbox.reload)

      expect(state.status).to eq(Operations::Health::WARNING)
      expect(state.as_json.to_json).not_to include('SECRET', 'graph.facebook.com')
    end

    it 'is healthy with credentials and a clean reading' do
      state = state_for(channel.inbox)

      expect(state.status).to eq(Operations::Health::HEALTHY)
      expect(state.detail[:checked]).to contain_exactly('reauth_latch', 'provider_health')
    end
  end
end
