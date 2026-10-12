FactoryBot.define do
  factory :channel_sms, class: 'Channel::Sms' do
    sequence(:phone_number) { |n| "+123456789#{n}1" }
    account
    provider_config do
      { 'account_id' => '1',
        'application_id' => '1',
        'api_key' => '1',
        'api_secret' => '1',
        'callback_username' => 'bw-user',
        'callback_password' => 'bw-secret' }
    end

    # A channel configured before callback authentication existed, used to prove the endpoint fails closed
    # rather than staying open for it (docs/p11/00-p10-security-closure.md).
    trait :without_callback_credentials do
      provider_config do
        { 'account_id' => '1', 'application_id' => '1', 'api_key' => '1', 'api_secret' => '1' }
      end
    end

    after(:create) do |channel_sms|
      create(:inbox, channel: channel_sms, account: channel_sms.account)
    end
  end
end
