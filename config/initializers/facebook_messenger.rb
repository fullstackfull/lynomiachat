# ref: https://github.com/jgorset/facebook-messenger#make-a-configuration-provider
class ChatwootFbProvider < Facebook::Messenger::Configuration::Providers::Base
  CHANNEL_APP_SECRET_KEYS = %w[app_secret app_secret_key client_secret api_secret].freeze

  def valid_verify_token?(_verify_token)
    GlobalConfigService.load('FB_VERIFY_TOKEN', '')
  end

  # Lynomia (docs/p11/00-p10-security-closure.md, SEC-5). This must never answer falsy. The gem's verifier
  # begins `return unless app_secret_for(...)` (facebook-messenger-2.0.1/lib/facebook/messenger/server.rb:78),
  # so a nil here skips signature verification for the whole request -- and GlobalConfigService.load returns
  # nil rather than its default when the stored value is blank, which is the ordinary state of an installation
  # that has not configured FB_APP_SECRET. Channel::FacebookPage has no per-channel secret column to fall back
  # on, so there was nothing to verify against and any unsigned body was accepted.
  #
  # With no secret configured the endpoint must reject rather than trust, so this returns a value no caller can
  # know. Verification then fails deterministically and the gem answers 400, which is the honest result for a
  # misconfigured installation.
  def app_secret_for(page_id)
    channel_app_secret_for(page_id).presence ||
      GlobalConfigService.load('FB_APP_SECRET', nil).presence ||
      unconfigured_secret
  end

  def access_token_for(page_id)
    Channel::FacebookPage.where(page_id: page_id).last.page_access_token
  end

  private

  # Stable for the process so two requests are treated alike, and unguessable so nothing can sign with it.
  def unconfigured_secret
    @unconfigured_secret ||= SecureRandom.hex(32)
  end

  def channel_app_secret_for(page_id)
    channel = Channel::FacebookPage.where(page_id: page_id).last
    return if channel.blank?

    channel_app_secret_candidates(channel).first
  end

  def channel_app_secret_candidates(channel)
    secrets = []
    secrets << channel.app_secret if channel.respond_to?(:app_secret)
    secrets.concat(provider_config_app_secrets(channel))
    secrets.compact_blank.uniq
  end

  def provider_config_app_secrets(channel)
    return [] unless channel.respond_to?(:provider_config)

    provider_config = channel.provider_config.to_h.with_indifferent_access
    CHANNEL_APP_SECRET_KEYS.filter_map { |key| provider_config[key].presence }
  end

  def bot
    Chatwoot::Bot
  end
end

Rails.application.reloader.to_prepare do
  Facebook::Messenger.configure do |config|
    config.provider = ChatwootFbProvider.new
  end

  Facebook::Messenger::Bot.on :message do |message|
    Webhooks::FacebookEventsJob.perform_later(message.to_json)
  end

  Facebook::Messenger::Bot.on :delivery do |delivery|
    Rails.logger.info "Recieved delivery status #{delivery.to_json}"
    Webhooks::FacebookDeliveryJob.perform_later(delivery.to_json)
  end

  Facebook::Messenger::Bot.on :read do |read|
    Rails.logger.info "Recieved read status  #{read.to_json}"
    Webhooks::FacebookDeliveryJob.perform_later(read.to_json)
  end

  Facebook::Messenger::Bot.on :message_echo do |message|
    # Add delay to prevent race condition where echo arrives before send message API completes
    # This avoids duplicate messages when echo comes early during API processing
    Webhooks::FacebookEventsJob.set(wait: 2.seconds).perform_later(message.to_json)
  end

  Facebook::Messenger::Bot.on :postback do |postback|
    Webhooks::FacebookEventsJob.perform_later(postback.to_json)
  end
end
