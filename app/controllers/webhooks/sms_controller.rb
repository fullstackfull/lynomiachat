# Bandwidth messaging callbacks.
#
# Lynomia (docs/p11/00-p10-security-closure.md, SC1). Two things were wrong here and both are closed:
#
# 1. The endpoint was unauthenticated, so anyone who knew a configured Bandwidth number could post forged
#    inbound messages into the account that owns it. It now requires the HTTP Basic credentials configured on
#    the Bandwidth Messaging Application, which is the only authentication Bandwidth documents for callbacks
#    (https://dev.bandwidth.com/guides/callbacks/callbacks.html). A channel with no credentials stored cannot
#    authenticate anything, so it fails closed rather than staying open.
#
# 2. The receiving channel was selected from the request body (`to`), which a caller controls. It is now
#    selected from the `:phone_number` the callback URL carries, and the body is never consulted for it.
#
# Bandwidth's handshake requires the challenge: it sends the first delivery with no Authorization header and
# expects 401 WITH a WWW-Authenticate header before it retries with credentials. Without the header it does
# not retry at all, so `request_http_basic_authentication` (which sets it) is load-bearing, not decoration.
# An unknown number takes the same path as a bad password, so the response says nothing about which numbers
# are configured.
class Webhooks::SmsController < ActionController::API
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  def process_payload
    return request_http_basic_authentication('Bandwidth') unless authenticated?

    # Bandwidth sends a JSON array; every event in it is one callback. Only the first used to be enqueued.
    events.each { |event| Webhooks::SmsEventsJob.perform_later(event.merge(channel_id: channel.id)) }
    head :ok
  end

  private

  def authenticated?
    channel.present? && authenticate_with_http_basic { |username, password| channel.callback_credentials_match?(username, password) }
  end

  # The callback URL this product generates strips the leading "+" (Inbox#callback_webhook_url), so that is the
  # spelling operators configure; an escaped "+" arrives decoded and is accepted too. Both name the same
  # channel. Nothing else about the request is trusted for this.
  def channel
    return @channel if defined?(@channel)

    given = params[:phone_number].to_s
    @channel = Channel::Sms.find_by(phone_number: "+#{given}") ||
               Channel::Sms.find_by(phone_number: given)
  end

  def events
    Array(params['_json']).filter_map { |event| event.respond_to?(:to_unsafe_hash) ? event.to_unsafe_hash : nil }
  end
end
