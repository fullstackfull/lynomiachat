# WHETHER ONE OUTGOING MESSAGE MAY CLAIM META'S HUMAN_AGENT TAG.
#
# The tag is not a delivery option; it is a statement to Meta about WHO is sending and WHEN. Meta's Messenger
# Platform policy describes it as a tag "that allows businesses to manually respond to user messages within a
# 7-day period", and warns that "Use of tags outside of approved use cases may result in restrictions on your
# ability to send messages"
# (https://developers.facebook.com/documentation/business-messaging/messenger-platform/policy, Messenger
# Platform, checked 2026-10-13, normative). The Send API reference is explicit that a Tagged Message is one
# "being sent outside the standard messaging window" and "must include a message tag that matches the allowed use
# case for the tag and contains non-promotional content", while a Response "must be sent during the standard
# messaging window"
# (https://developers.facebook.com/documentation/business-messaging/messenger-platform/send-messages, Messenger
# Platform, checked 2026-10-13, normative). Meta's documented allowed usage for this tag is human agent support
# where the person's issue cannot be resolved inside the standard window; automated messages are disallowed, and
# the tag requires the Human Agent permission granted through App Review.
#
# WHAT THIS REPLACED. All three Meta send paths applied the tag to EVERY outgoing message whenever the
# installation switch was on. A bot reply, an automation reply, a campaign send and an agent's first reply thirty
# seconds into a live chat all left as MESSAGE_TAG/HUMAN_AGENT. Two claims were false at once: that a human agent
# was writing when none was, and that the standard window had closed when it had not -- which also gave away the
# promotional content a Response inside the window is allowed to carry.
#
# WHAT THE CODE CAN KNOW. Who is sending: `Message#human_response?` is the predicate the product already uses to
# tell an agent's words from a bot's, an automation's and a campaign's, so the tag now rides the same definition
# as first-reply and SLA accounting rather than a second one. And where the conversation sits relative to both
# windows: `Conversations::MessageWindowService` already owns that arithmetic.
#
# WHAT IT CANNOT KNOW, and therefore does not pretend to. Whether this app actually holds Meta's Human Agent
# permission: no Graph endpoint reports an app's granted permissions to the app itself, so there is nothing to
# read. The installation switch is therefore read as the operator's assertion that App Review granted it -- the
# only honest meaning that switch can carry -- instead of as an instruction to tag everything.
#
# FAIL CLOSED. Everything unknown resolves to "not eligible", and the message leaves as an ordinary response. When
# the standard window really has closed Meta then refuses that send and the message is marked failed with Meta's
# own reason. That is the correct trade: a refused message is recoverable by the agent, a Human Agent permission
# withdrawn for tag misuse is not.
class Messages::HumanAgentTagEligibility
  pattr_initialize [:message!, :config_key!]

  def eligible?
    return false unless GlobalConfigService.load(config_key, nil)
    return false unless message.human_response?

    # Inside the 7 days Meta allows a human agent, and past the 24 hours in which a Response is the correct type.
    message_window.in_human_agent_window? && !message_window.in_standard_messaging_window?
  end

  private

  def message_window
    @message_window ||= Conversations::MessageWindowService.new(message.conversation)
  end
end
