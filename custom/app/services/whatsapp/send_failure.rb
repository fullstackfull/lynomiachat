# Why Meta refused a send, in the three parts a campaign recipient stores them in
# (docs/p-final/clean-room/specs/E-whatsapp-delivery-status-propagation.md §2, §4.4).
#
# Upstream records a provider refusal onto the `Message` and returns nothing to the caller, and it skips even
# that when there is no message (app/services/whatsapp/providers/base_service.rb:46). A campaign send has no
# message, so Meta's diagnosis was logged and discarded -- while the recipient list's reason column is the
# operator's only view of it.
#
# Meta's send error and Meta's delivery-report error are different shapes: a send returns one `error` object
# whose human part is `message`, a report returns an `errors` array whose human part is `title`. This handles
# the send shape; the report shape is read where the report is read.
#
# The code and the title are the provider's own diagnostic values and are untrusted text. They are stored and
# displayed, never interpolated into SQL or a log format string (package E §5.2).
class Whatsapp::SendFailure
  attr_reader :code, :title, :message

  def initialize(code: nil, title: nil, message: nil)
    @code = code.presence&.to_s
    @title = title.presence&.to_s
    @message = message.presence&.to_s
  end

  # https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/#sample-response
  #
  # `error_data.details` is the specific sentence about this call -- "this number is not registered", rather
  # than the generic one the type carries -- so it is the better title when Meta sends it.
  def self.from_response(response)
    error = response.try(:parsed_response)
    error = error.is_a?(Hash) ? error['error'] : nil
    return nil if error.blank?

    new(code: error['code'], title: error.dig('error_data', 'details') || error['message'], message: error['message'])
  end

  # A send that never reached Meta: a timeout, a DNS failure, a connection reset. There is no code and no title,
  # and package D's reason chain tolerates having only the message (package E §6).
  def self.from_exception(error)
    new(message: error.message)
  end

  def present?
    [code, title, message].any?(&:present?)
  end
end
