require 'rails_helper'

# The audit row for a channel configuration change. The OSS concern declares `after_update :create_audit_log_entry`
# and leaves the body empty; Custom::Channelable is what fills it. Before that module existed these examples all
# failed with `expected 1, got 0`, because the callback ran into a no-op.
RSpec.describe Channelable do
  let(:account) { create(:account) }
  let!(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }

  # Every Channelable model reaches the writer through the same OSS callback, so the wiring is asserted once for all
  # twelve rather than per model.
  it 'owns create_audit_log_entry on every Channelable model, with no Enterprise module in the chain' do
    models = [Channel::Api, Channel::Email, Channel::FacebookPage, Channel::Instagram, Channel::Line, Channel::Sms,
              Channel::Telegram, Channel::Tiktok, Channel::TwilioSms, Channel::TwitterProfile, Channel::WebWidget,
              Channel::Whatsapp]

    owners = models.map { |model| model.instance_method(:create_audit_log_entry).owner.to_s }

    expect(owners).to all(eq('Custom::Channelable::InstanceMethods'))
    expect(models.flat_map { |model| model.ancestors.map(&:to_s) }.grep(/Enterprise/)).to be_empty
  end

  describe 'a qualifying update' do
    it 'writes exactly one row' do
      expect { channel.update!(phone_number: '+19998887777') }.to change(Custom::AuditLog, :count).by(1)
    end

    it 'points the row at the inbox, the update action and the account' do
      channel.update!(phone_number: '+19998887777')

      audit = Custom::AuditLog.last
      expect(audit.auditable_type).to eq('Inbox')
      expect(audit.auditable_id).to eq(inbox.id)
      expect(audit.action).to eq('update')
      expect(audit.associated_type).to eq('Account')
      expect(audit.associated_id).to eq(account.id)
    end

    it 'records the changed attribute and its new value' do
      previous = channel.phone_number

      channel.update!(phone_number: '+19998887777')

      expect(Custom::AuditLog.last.audited_changes).to eq('phone_number' => [previous, '+19998887777'])
    end

    it 'attributes the row to the acting user through the Audited store, as the original did' do
      user = create(:user, account: account)

      Audited.audit_class.as_user(user) { channel.update!(phone_number: '+19998887766') }

      expect(Custom::AuditLog.last.user_id).to eq(user.id)
    end

    it 'records several changed attributes in one row' do
      channel.update!(phone_number: '+19998887755', phone_number_health_error: 'stale token')

      expect(Custom::AuditLog.last.audited_changes.keys).to contain_exactly('phone_number', 'phone_number_health_error')
    end
  end

  describe 'a non-qualifying update' do
    it 'writes nothing when the only change is message_templates_last_updated' do
      expect { channel.update!(message_templates_last_updated: Time.zone.now) }.not_to change(Custom::AuditLog, :count)
    end

    it 'writes nothing when the only change is the API channel secret' do
      api_channel = create(:channel_api, account: account)

      expect { api_channel.update!(secret: 'rotated-secret') }.not_to change(Custom::AuditLog, :count)
    end

    # Every channel factory builds an inbox in an after(:create) hook, so the inbox-less case is created directly.
    it 'writes nothing when the channel has no inbox yet' do
      orphan = Channel::Api.create!(account: account, webhook_url: 'http://example.com/first')

      expect { orphan.update!(webhook_url: 'https://example.com/hook') }.not_to change(Custom::AuditLog, :count)
    end

    it 'writes nothing when the only change is updated_at' do
      expect { channel.update!(updated_at: 1.minute.from_now) }.not_to change(Custom::AuditLog, :count)
    end
  end

  # The reason this module deviates from the implementation it replaces. The Enterprise version excepted only
  # `secret`, so every other credential below went into audits.audited_changes in plaintext -- and the reader
  # renders that payload to any administrator of the account.
  describe 'secret safety' do
    it 'never records the WhatsApp api_key when provider_config changes' do
      channel.update!(provider_config: channel.provider_config.merge('api_key' => 'rotated-live-key'))

      payload = Custom::AuditLog.last.audited_changes.fetch('provider_config')
      expect(payload).to eq(%w[[FILTERED] [FILTERED]])
      expect(Custom::AuditLog.last.audited_changes.to_s).not_to include('rotated-live-key')
    end

    it 'never records the WhatsApp business management token' do
      channel.update!(business_management_token: 'EAAG-live-token')

      expect(Custom::AuditLog.last.audited_changes.fetch('business_management_token')).to eq(%w[[FILTERED] [FILTERED]])
      expect(Custom::AuditLog.last.audited_changes.to_s).not_to include('EAAG-live-token')
    end

    # One example per credential-bearing column across the Channelable models that have a factory. The value is a
    # distinctive string so the assertion is that the SECRET ITSELF is absent, not merely that a marker is present.
    [
      [:channel_api, :hmac_token, 'hmac-secret-value'],
      [:channel_email, :imap_password, 'imap-secret-value'],
      [:channel_email, :smtp_password, 'smtp-secret-value'],
      [:channel_instagram, :access_token, 'instagram-secret-value'],
      [:channel_line, :line_channel_secret, 'line-secret-value'],
      [:channel_line, :line_channel_token, 'line-token-value'],
      [:channel_telegram, :bot_token, 'telegram-secret-value'],
      [:channel_tiktok, :access_token, 'tiktok-secret-value'],
      [:channel_tiktok, :refresh_token, 'tiktok-refresh-value'],
      [:channel_widget, :hmac_token, 'widget-hmac-value'],
      [:channel_widget, :website_token, 'widget-website-value']
    ].each do |factory_name, column, secret|
      it "filters #{factory_name}##{column} out of the audit payload" do
        channel_record = create(factory_name, account: account)
        channel_record.reload

        channel_record.update!(column => secret)

        audit = Custom::AuditLog.where(auditable_type: 'Inbox').last
        expect(audit.audited_changes.fetch(column.to_s)).to eq(%w[[FILTERED] [FILTERED]])
        expect(audit.audited_changes.to_s).not_to include(secret)
      end
    end

    it 'still records non-credential configuration in the clear, so the row stays useful' do
      channel.update!(provider: 'whatsapp_cloud')

      expect(Custom::AuditLog.last.audited_changes.fetch('provider').last).to eq('whatsapp_cloud')
    end

    it 'does not filter the hmac_mandatory policy flag, which is not a credential' do
      api_channel = create(:channel_api, account: account)
      api_channel.reload

      api_channel.update!(hmac_mandatory: true)

      expect(Custom::AuditLog.where(auditable_type: 'Inbox').last.audited_changes.fetch('hmac_mandatory')).to eq([false, true])
    end
  end
end
