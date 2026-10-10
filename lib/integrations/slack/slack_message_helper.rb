module Integrations::Slack::SlackMessageHelper
  def process_message_payload
    return unless conversation

    handle_conversation
    success_response
  rescue Slack::Web::Api::Errors::MissingScope => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    disable_and_reauthorize
  end

  def handle_conversation
    create_message unless message_exists?
  end

  def success_response
    { status: 'success' }
  end

  def disable_and_reauthorize
    integration_hook.prompt_reauthorization!
    integration_hook.disable
  end

  def message_exists?
    conversation.messages.exists?(external_source_ids: { slack: params[:event][:ts] })
  end

  def create_message
    resolved_sender, sender_name, sender_avatar_url = resolve_slack_sender
    slack_sender_attrs = {}
    slack_sender_attrs[:sender_name] = sender_name if sender_name
    slack_sender_attrs[:sender_avatar_url] = sender_avatar_url if sender_avatar_url
    @message = conversation.messages.build(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      content: formatted_message_content,
      external_source_id_slack: params[:event][:ts],
      private: private_note?,
      sender: resolved_sender,
      additional_attributes: slack_sender_attrs
    )
    process_attachments(params[:event][:files]) if attachments_present?
    @message.save!
  end

  def slack_hosted?(url)
    uri = URI.parse(url.to_s)
    return false unless uri.scheme == 'https' && uri.userinfo.nil?

    host = uri.host.to_s.downcase
    host == 'slack.com' || host.end_with?(SLACK_FILE_HOST_SUFFIX)
  rescue URI::InvalidURIError
    false
  end

  def attachments_present?
    params[:event][:files].present?
  end

  def process_attachments(attachments)
    Integrations::Slack::AttachmentImporter
      .new(message: @message, access_token: integration_hook.access_token)
      .import(attachments)
  end

  def conversation
    @conversation ||= Conversation.where(identifier: params[:event][:thread_ts]).first
  end

  def resolve_slack_sender
    return [nil, nil, nil] unless params[:event][:user]

    slack_user = slack_client.users_info(user: params[:event][:user])[:user]
    chatwoot_user = conversation.account.users.from_email(slack_user[:profile][:email])
    return [chatwoot_user, nil, nil] if chatwoot_user

    sender_name = slack_user.dig(:profile, :display_name).presence ||
                  slack_user[:real_name].presence ||
                  slack_user[:name]
    sender_avatar_url = slack_user.dig(:profile, :image_192).presence
    [nil, sender_name, sender_avatar_url]
  rescue Slack::Web::Api::Errors::MissingScope
    raise
  rescue StandardError
    [nil, nil, nil]
  end

  def formatted_message_content
    text = Slack::Messages::Formatting.unescape(params[:event][:text] || '')
    Integrations::Slack::EmojiFormatter.format(text)
  end

  def private_note?
    params[:event][:text].strip.downcase.starts_with?('note:', 'private:')
  end
end
