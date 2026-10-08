class Instagram::Messenger::SendOnInstagramService < Instagram::BaseSendService
  # The Graph version this send path talks. It is NOT `INSTAGRAM_API_VERSION`: that one governs
  # graph.instagram.com, where the Instagram Login generation lives, and this is the older Facebook-Page
  # generation on graph.facebook.com. Bumping one must not silently bump the other, so they are separate keys.
  #
  # The default is the version this path has always sent on. It is stated here, and overridable, so that Meta
  # retiring it is an environment change rather than a code change and a deploy -- which is what it was when the
  # version was written into the URL.
  DEFAULT_API_VERSION = 'v11.0'.freeze

  private

  def channel_class
    Channel::FacebookPage
  end

  # Deliver a message with the given payload.
  # @see https://developers.facebook.com/docs/messenger-platform/instagram/features/send-message
  def send_message(message_content)
    access_token = channel.page_access_token
    app_secret_proof = calculate_app_secret_proof(GlobalConfigService.load('FB_APP_SECRET', ''), access_token)
    query = { access_token: access_token }
    query[:appsecret_proof] = app_secret_proof if app_secret_proof

    response = HTTParty.post(
      "https://graph.facebook.com/#{api_version}/me/messages",
      body: message_content,
      query: query
    )

    process_response(response, message_content)
  end

  def api_version
    GlobalConfigService.load('INSTAGRAM_MESSENGER_API_VERSION', DEFAULT_API_VERSION)
  end

  def calculate_app_secret_proof(app_secret, access_token)
    Facebook::Messenger::Configuration::AppSecretProofCalculator.call(
      app_secret, access_token
    )
  end

  def merge_human_agent_tag(params)
    global_config = GlobalConfig.get('ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT')

    return params unless global_config['ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT']

    params[:messaging_type] = 'MESSAGE_TAG'
    params[:tag] = 'HUMAN_AGENT'
    params
  end
end
