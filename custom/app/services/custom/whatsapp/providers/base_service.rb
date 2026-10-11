# The send-side half of package E (docs/p-final/clean-room/specs/E-whatsapp-delivery-status-propagation.md §4.4).
#
# Upstream writes a provider refusal onto the `Message` and returns nothing to the caller, and when there is no
# message it returns before doing even that (app/services/whatsapp/providers/base_service.rb:46). A campaign
# send has no message, so Meta's code and title went to the log and nowhere else -- and package D needs them on
# the recipient, separately, because the recipient list shows the reason and the code as two things.
#
# This keeps the refusal on the instance that saw it. Nothing else changes: `super` still does exactly what it
# did, including the early return, so the conversation-message path is untouched.
module Custom::Whatsapp::Providers::BaseService
  # The last refusal this provider instance saw. Readable only for as long as the instance lives, which is why
  # Custom::Channel::Whatsapp keeps one alive across a template send.
  attr_reader :last_send_failure

  def handle_error(response, message)
    @last_send_failure = ::Whatsapp::SendFailure.from_response(response)
    super
  end
end
