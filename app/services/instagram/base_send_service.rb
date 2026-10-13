class Instagram::BaseSendService < Base::SendOnChannelService
  pattr_initialize [:message!]

  private

  delegate :additional_attributes, to: :contact

  def perform_reply
    send_attachments if message.attachments.present?
    send_content if message.content.present?
  rescue StandardError => e
    handle_error(e)
  end

  def send_attachments
    message.attachments.each do |attachment|
      send_message(attachment_message_params(attachment))
    end
  end

  def send_content
    send_message(message_params)
  end

  def handle_error(error)
    ChatwootExceptionTracker.new(error, account: message.account, user: message.sender).capture_exception
  end

  def message_params
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        text: message.outgoing_content
      }
    }

    merge_human_agent_tag(params)
  end

  def attachment_message_params(attachment)
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        attachment: {
          type: attachment_type(attachment),
          payload: {
            url: attachment.download_url
          }
        }
      }
    }

    merge_human_agent_tag(params)
  end

  def process_response(response)
    parsed_response = response.parsed_response
    if response.success? && parsed_response['error'].blank?
      message.update!(source_id: parsed_response['message_id'])
      parsed_response
    else
      external_error = external_error(parsed_response)
      Rails.logger.error("Instagram response for message_id=#{message.id}: #{external_error}")
      Messages::StatusUpdateService.new(message, 'failed', external_error).perform
      nil
    end
  end

  def external_error(response)
    error_message = response.dig('error', 'message')
    error_code = response.dig('error', 'code')

    # https://developers.facebook.com/docs/messenger-platform/error-codes
    # Access token has expired or become invalid. This may be due to a password change,
    # removal of the connected app from Instagram account settings, or other reasons.
    channel.authorization_error! if error_code == 190

    "#{error_code} - #{error_message}"
  end

  def attachment_type(attachment)
    return attachment.file_type if %w[image audio video file].include? attachment.file_type

    'file'
  end

  # Methods to be implemented by child classes
  def send_message(message_content)
    raise NotImplementedError, 'Subclasses must implement send_message'
  end

  # The two Instagram generations differ only in which installation switch asserts the Human Agent approval, so
  # the rule lives here once and each subclass names its key. Eligibility itself is
  # Messages::HumanAgentTagEligibility's: the switch used to be the whole condition, which tagged bot, automation
  # and campaign sends as human-agent work and tagged ordinary replies made well inside the 24-hour window.
  #
  # Unlike the Messenger path this leaves `messaging_type` unset when the tag does not apply, which is what both
  # Instagram paths have always sent.
  def merge_human_agent_tag(params)
    return params unless Messages::HumanAgentTagEligibility.new(message: message, config_key: human_agent_config_key).eligible?

    params[:messaging_type] = 'MESSAGE_TAG'
    params[:tag] = 'HUMAN_AGENT'
    params
  end

  def human_agent_config_key
    raise NotImplementedError, 'Subclasses must implement human_agent_config_key'
  end
end
