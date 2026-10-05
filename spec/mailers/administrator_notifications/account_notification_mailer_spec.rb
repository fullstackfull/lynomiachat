require 'rails_helper'

RSpec.describe AdministratorNotifications::AccountNotificationMailer do
  let(:account) { create(:account, name: 'Test Account') }
  let(:mailer) { described_class.with(account: account) }
  let(:class_instance) { described_class.new }

  before do
    allow(described_class).to receive(:new).and_return(class_instance)
    allow(class_instance).to receive(:smtp_config_set_or_development?).and_return(true)
    account.custom_attributes['marked_for_deletion_at'] = 7.days.from_now.iso8601
    account.save!
  end

  describe '#account_deletion_user_initiated' do
    it 'sets the correct subject for user-initiated deletion' do
      mail = mailer.account_deletion_user_initiated(account, 'manual_deletion')
      expect(mail.subject).to eq('Your Chatwoot account deletion has been scheduled')
    end

    it 'names the installation rather than a hard-coded product in the subject and the body' do
      InstallationConfig.where(name: 'BRAND_NAME').first_or_create(value: 'Acme Desk').update!(value: 'Acme Desk')
      GlobalConfig.clear_cache

      mail = mailer.account_deletion_user_initiated(account, 'manual_deletion')

      expect(mail.subject).to eq('Your Acme Desk account deletion has been scheduled')
      expect(mail.body.encoded).to include('The Acme Desk Team')
      expect(mail.body.encoded).not_to include('Chatwoot Team')
    end
  end

  describe '#account_deletion_for_inactivity' do
    it 'sets the correct subject for system-initiated deletion' do
      mail = mailer.account_deletion_for_inactivity(account, 'Account Inactive')
      expect(mail.subject).to eq('Your Chatwoot account is scheduled for deletion due to inactivity')
    end

    it 'links to the configured support destination, and omits the line when none is configured' do
      InstallationConfig.where(name: 'SUPPORT_URL').first_or_create(value: '').update!(value: '')
      GlobalConfig.clear_cache
      expect(mailer.account_deletion_for_inactivity(account, 'Account Inactive').body.encoded).not_to include('get in touch')

      InstallationConfig.find_by(name: 'SUPPORT_URL').update!(value: 'https://help.acme.example')
      GlobalConfig.clear_cache

      expect(mailer.account_deletion_for_inactivity(account, 'Account Inactive').body.encoded).to include('https://help.acme.example')
    end
  end

  describe '#format_deletion_date' do
    it 'formats a valid date string' do
      date_str = '2024-12-31T12:00:00Z'
      formatted = described_class.new.send(:format_deletion_date, date_str)
      expect(formatted).to eq('December 31, 2024')
    end

    it 'handles blank dates' do
      formatted = described_class.new.send(:format_deletion_date, nil)
      expect(formatted).to eq('Unknown')
    end

    it 'handles invalid dates' do
      formatted = described_class.new.send(:format_deletion_date, 'invalid-date')
      expect(formatted).to eq('Unknown')
    end
  end
end
