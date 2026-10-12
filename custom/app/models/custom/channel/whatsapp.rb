# The one method that makes the send-side of package E possible
# (docs/p-final/clean-room/specs/E-whatsapp-delivery-status-propagation.md §4.4).
#
# Upstream delegates the template send straight to a freshly built provider instance
# (`delegate :send_template, to: :provider_service`, app/models/channel/whatsapp.rb:147), so the instance -- and
# the refusal it just saw -- is unreachable the moment the call returns. The campaign send path has no `Message`
# to carry that refusal, so without this it has no way to learn why Meta said no.
#
# So: one instance, built here, kept for the length of the call, and its refusal left where the caller can read
# it. Nothing else about the send changes.
#
# A send that never reached Meta at all -- a timeout, a reset connection -- is a failure too, and the exception
# is re-raised after it is recorded so that every existing caller still sees exactly what it saw before.
module Custom::Channel::Whatsapp
  # Set on every template send: nil when Meta accepted it, a ::Whatsapp::SendFailure when it did not.
  attr_reader :last_send_failure

  def send_template(phone_number, template_info, message = nil)
    provider = provider_service
    @last_send_failure = nil
    provider.send_template(phone_number, template_info, message).tap do
      @last_send_failure = provider.last_send_failure
    end
  rescue StandardError => e
    @last_send_failure = ::Whatsapp::SendFailure.from_exception(e)
    raise
  end
end
