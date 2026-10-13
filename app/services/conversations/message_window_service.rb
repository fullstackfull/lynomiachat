class Conversations::MessageWindowService
  MESSAGING_WINDOW_24_HOURS = 24.hours
  MESSAGING_WINDOW_7_DAYS = 7.days

  def initialize(conversation)
    @conversation = conversation
  end

  def can_reply?
    return true if messaging_window.blank?

    last_message_in_messaging_window?(messaging_window)
  end

  # Meta's HUMAN_AGENT tag is a claim about BOTH who is sending and when (Messages::HumanAgentTagEligibility), and
  # `can_reply?` cannot answer the "when" half: it reports the EFFECTIVE window, which is already 7 days whenever
  # the installation switch is on, so it cannot tell "still inside the standard window, where a RESPONSE is
  # correct" from "past it, where only a tag will do". These name the two boundaries directly, off the same
  # constants and the same last-incoming-message query the rest of this class uses, so there is still one
  # implementation of the arithmetic.
  #
  # Both are false when the person has never written, which is the honest answer: there is no message to respond
  # to and no message to be within 7 days of.
  def in_standard_messaging_window?
    last_message_in_messaging_window?(MESSAGING_WINDOW_24_HOURS)
  end

  def in_human_agent_window?
    last_message_in_messaging_window?(MESSAGING_WINDOW_7_DAYS)
  end

  private

  def messaging_window
    case @conversation.inbox.channel_type
    when 'Channel::Api'
      api_messaging_window
    when 'Channel::FacebookPage'
      messenger_messaging_window
    when 'Channel::Instagram'
      instagram_messaging_window
    when 'Channel::Tiktok'
      tiktok_messaging_window
    when 'Channel::Whatsapp'
      MESSAGING_WINDOW_24_HOURS
    when 'Channel::TwilioSms'
      twilio_messaging_window
    end
  end

  def last_message_in_messaging_window?(time)
    return false if last_incoming_message.nil?

    Time.current < last_incoming_message.created_at + time
  end

  def api_messaging_window
    return if @conversation.inbox.channel.additional_attributes['agent_reply_time_window'].blank?

    @conversation.inbox.channel.additional_attributes['agent_reply_time_window'].to_i.hours
  end

  # Check medium of the inbox to determine the messaging window
  def twilio_messaging_window
    @conversation.inbox.channel.medium == 'whatsapp' ? MESSAGING_WINDOW_24_HOURS : nil
  end

  def messenger_messaging_window
    meta_messaging_window('ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT')
  end

  def instagram_messaging_window
    meta_messaging_window('ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT')
  end

  def tiktok_messaging_window
    48.hours
  end

  def meta_messaging_window(config_key)
    GlobalConfigService.load(config_key, nil) ? MESSAGING_WINDOW_7_DAYS : MESSAGING_WINDOW_24_HOURS
  end

  def last_incoming_message
    @last_incoming_message ||= @conversation.messages.where(account_id: @conversation.account_id).incoming&.last
  end
end
